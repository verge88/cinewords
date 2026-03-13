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
  Future<String> getPlayableUrl(String videoId) async {
    // Check cache first
    if (_urlCache.containsKey(videoId)) {
      final expiry = _cacheExpiry[videoId];
      if (expiry != null && DateTime.now().isBefore(expiry)) {
        debugPrint('StreamService: Using cached URL for $videoId');
        return _urlCache[videoId]!;
      } else {
        _urlCache.remove(videoId);
        _cacheExpiry.remove(videoId);
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
          final url = manifest.muxed.withHighestBitrate().url.toString();
          _cacheUrl(videoId, url);
          debugPrint('StreamService: ✓ Got muxed stream via $clientName');
          return url;
        }

        if (manifest.hls.isNotEmpty) {
          final url = manifest.hls.first.url.toString();
          _cacheUrl(videoId, url);
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
        final url = manifest.muxed.withHighestBitrate().url.toString();
        _cacheUrl(videoId, url);
        return url;
      }
      if (manifest.hls.isNotEmpty) {
        final url = manifest.hls.first.url.toString();
        _cacheUrl(videoId, url);
        return url;
      }
    } catch (e) {
      lastError = e.toString();
      debugPrint('StreamService: ✗ Final retry failed: $e');
    }

    throw Exception(
        'Could not load video. Try setting a proxy in settings. ($lastError)');
  }

  void _cacheUrl(String videoId, String url) {
    _urlCache[videoId] = url;
    _cacheExpiry[videoId] =
        DateTime.now().add(Duration(minutes: _cacheDurationMinutes));
  }

  void dispose() {
    _yt?.close();
    _yt = null;
    _urlCache.clear();
    _cacheExpiry.clear();
  }
}
