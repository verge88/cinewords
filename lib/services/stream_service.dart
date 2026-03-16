import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/io_client.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StreamService {
  YoutubeExplode? _yt;
  final Map<String, String> _urlCache = {};
  final Map<String, DateTime> _cacheExpiry = {};
  static const int _cacheDurationMinutes = 30;
  static const Duration _requestTimeout = Duration(seconds: 15);

  static const String _proxyPrefKey = 'youtube_proxy_url';

  /// Сохранить адрес прокси-сервера (например: "192.168.1.1:8080")
  static Future<void> setProxy(String? proxyUrl) async {
    final prefs = await SharedPreferences.getInstance();
    if (proxyUrl == null || proxyUrl.trim().isEmpty) {
      await prefs.remove(_proxyPrefKey);
    } else {
      await prefs.setString(_proxyPrefKey, proxyUrl.trim());
    }
  }

  /// Получить текущий адрес прокси
  static Future<String?> getProxy() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_proxyPrefKey);
  }

  /// Создать YoutubeExplode с прокси или без
  Future<YoutubeExplode> _createClient() async {
    final proxy = await getProxy();

    if (proxy != null && proxy.isNotEmpty) {
      debugPrint('StreamService: Using proxy: $proxy');
      final httpClient = HttpClient();
      httpClient.findProxy = (uri) => 'PROXY $proxy';
      // Не проверяем сертификаты через прокси
      httpClient.badCertificateCallback =
          (cert, host, port) => true;
      final ioClient = IOClient(httpClient);
      return YoutubeExplode(YoutubeHttpClient(ioClient));
    }

    return YoutubeExplode();
  }

  Future<YoutubeExplode> _getClient() async {
    _yt ??= await _createClient();
    return _yt!;
  }

  /// Пересоздать клиент (например, после смены прокси)
  Future<void> recreateClient() async {
    _yt?.close();
    _yt = await _createClient();
  }

  /// Get best playable stream URL with multiple fallback strategies.
  Future<String> getPlayableUrl(String videoId, {String? quality}) async {
    final cacheKey = quality == null ? videoId : '${videoId}_$quality';
    
    // Check cache first
    if (_urlCache.containsKey(cacheKey)) {
      final expiry = _cacheExpiry[cacheKey];
      if (expiry != null && DateTime.now().isBefore(expiry)) {
        debugPrint('StreamService: Using cached URL for $cacheKey');
        return _urlCache[cacheKey]!;
      } else {
        _urlCache.remove(cacheKey);
        _cacheExpiry.remove(cacheKey);
      }
    }

    final client = await _getClient();
    String? lastError;

    // Все доступные YouTube API клиенты
    final clientConfigs = <List<YoutubeApiClient>?>[
      null, // дефолт
      [YoutubeApiClient.tv],
      [YoutubeApiClient.tvSimplyEmbedded],
      [YoutubeApiClient.safari],
      [YoutubeApiClient.androidVr],
      [YoutubeApiClient.android],
      [YoutubeApiClient.ios],
      [YoutubeApiClient.mediaConnect],
      [YoutubeApiClient.mweb],
      [YoutubeApiClient.webCreator],
      [YoutubeApiClient.androidMusic],
    ];

    for (final clients in clientConfigs) {
      try {
        final clientName =
            clients?.map((c) => c.toString()).join(', ') ?? 'default';
        debugPrint('StreamService: Trying $clientName for $videoId...');

        final StreamManifest manifest;
        if (clients == null) {
          manifest = await client.videos.streams
              .getManifest(videoId)
              .timeout(_requestTimeout);
        } else {
          manifest = await client.videos.streams
              .getManifest(videoId, ytClients: clients)
              .timeout(_requestTimeout);
        }

        if (manifest.muxed.isNotEmpty) {
          final stream = quality == null 
            ? manifest.muxed.withHighestBitrate()
            : manifest.muxed.firstWhere(
                (s) => '${s.videoResolution.height}p' == quality,
                orElse: () => manifest.muxed.withHighestBitrate(),
              );
              
          final url = stream.url.toString();
          _cacheUrl(cacheKey, url);
          debugPrint('StreamService: ✓ Got muxed stream via $clientName');
          return url;
        }

        if (manifest.hls.isNotEmpty) {
          final stream = quality == null 
            ? manifest.hls.first
            : manifest.hls.firstWhere(
                (s) => s.url.toString().contains(quality),
                orElse: () => manifest.hls.first,
              );
          final url = stream.url.toString();
          _cacheUrl(cacheKey, url);
          debugPrint('StreamService: ✓ Got HLS stream via $clientName');
          return url;
        }

        debugPrint(
            'StreamService: $clientName — no muxed/HLS streams available');
      } catch (e) {
        lastError = e.toString();
        final clientName =
            clients?.map((c) => c.toString()).join(', ') ?? 'default';
        debugPrint('StreamService: ✗ $clientName failed: $e');
        continue;
      }
    }

    // Последняя попытка: пересоздать клиент
    try {
      debugPrint('StreamService: Recreating client and retrying...');
      await recreateClient();
      final freshClient = await _getClient();
      final manifest = await freshClient.videos.streams
          .getManifest(videoId)
          .timeout(_requestTimeout);

      if (manifest.muxed.isNotEmpty) {
        final stream = quality == null 
            ? manifest.muxed.withHighestBitrate()
            : manifest.muxed.firstWhere(
                (s) => '${s.videoResolution.height}p' == quality,
                orElse: () => manifest.muxed.withHighestBitrate(),
              );
        final url = stream.url.toString();
        _cacheUrl(cacheKey, url);
        return url;
      }
      if (manifest.hls.isNotEmpty) {
        final stream = quality == null 
            ? manifest.hls.first
            : manifest.hls.firstWhere(
                (s) => s.url.toString().contains(quality),
                orElse: () => manifest.hls.first,
              );
        final url = stream.url.toString();
        _cacheUrl(cacheKey, url);
        return url;
      }
    } catch (e) {
      lastError = e.toString();
      debugPrint('StreamService: ✗ Final retry failed: $e');
    }

    throw Exception(
        'Could not load video. Try setting a proxy in settings. ($lastError)');
  }

  /// Get available video qualities for a video
  Future<List<String>> getAvailableQualities(String videoId) async {
    try {
      final client = await _getClient();
      final manifest = await client.videos.streams.getManifest(videoId).timeout(_requestTimeout);
      final qualities = <String>{};
      
      for (final stream in manifest.muxed) {
        qualities.add('${stream.videoResolution.height}p');
      }
      
      if (qualities.isEmpty) {
        for (final stream in manifest.hls) {
          // Parse resolution from URL if available, else just ignore (HLS is auto-adaptive anyway usually)
          final match = RegExp(r'/(\d+)p/').firstMatch(stream.url.toString());
          if (match != null) {
            qualities.add('${match.group(1)}p');
          }
        }
      }
      
      final sortedQualities = qualities.toList()
        ..sort((a, b) {
          final aVal = int.tryParse(a.replaceAll('p', '')) ?? 0;
          final bVal = int.tryParse(b.replaceAll('p', '')) ?? 0;
          return bVal.compareTo(aVal); // Descending order
        });
        
      return sortedQualities;
    } catch (e) {
      debugPrint('StreamService: Could not get available qualities: $e');
      return [];
    }
  }

  void _cacheUrl(String cacheKey, String url) {
    _urlCache[cacheKey] = url;
    _cacheExpiry[cacheKey] =
        DateTime.now().add(Duration(minutes: _cacheDurationMinutes));
  }

  void dispose() {
    _yt?.close();
    _yt = null;
    _urlCache.clear();
    _cacheExpiry.clear();
  }
}
