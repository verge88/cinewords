import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Результат разрешения потока: URL + список качеств из того же манифеста.
class StreamResolution {
  final String url;
  final List<String> qualities;
  final bool isHls;
  const StreamResolution({
    required this.url,
    required this.qualities,
    required this.isHls,
  });
}

class StreamService {
  StreamService._();
  static final StreamService _instance = StreamService._();

  /// Синглтон: клиент и кэш подписи/URL живут дольше одного экрана плеера.
  factory StreamService() => _instance;

  static YoutubeExplode? _yt;
  static final Map<String, StreamResolution> _cache = {};
  static final Map<String, DateTime> _cacheExpiry = {};

  static const int _cacheDurationMinutes = 30;
  static const Duration _perClientTimeout = Duration(seconds: 7);
  static const String _proxyPrefKey = 'youtube_proxy_url';

  /// Порядок подобран по реальным логам: клиенты, которые чаще всего
  /// отдают поток, идут первыми. tv/androidVr оставлены как аварийные.
  static const List<List<YoutubeApiClient>> _clientOrder = [
    [YoutubeApiClient.android],
    [YoutubeApiClient.mediaConnect],

    [YoutubeApiClient.mweb],
    [YoutubeApiClient.tv],
    [YoutubeApiClient.androidVr],
  ];

  static Future<void> setProxy(String? proxyUrl) async {
    final prefs = await SharedPreferences.getInstance();
    if (proxyUrl == null || proxyUrl.trim().isEmpty) {
      await prefs.remove(_proxyPrefKey);
    } else {
      await prefs.setString(_proxyPrefKey, proxyUrl.trim());
    }
  }

  static Future<String?> getProxy() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_proxyPrefKey);
  }

  Future<YoutubeExplode> _createClient() async {
    final proxy = await getProxy();
    if (proxy != null && proxy.isNotEmpty) {
      debugPrint('StreamService: using proxy $proxy');
      final httpClient = HttpClient()
        ..findProxy = ((uri) => 'PROXY $proxy')
        ..badCertificateCallback = ((cert, host, port) => true);
      return YoutubeExplode(YoutubeHttpClient(IOClient(httpClient)));
    }
    return YoutubeExplode();
  }

  Future<YoutubeExplode> _getClient() async => _yt ??= await _createClient();

  Future<void> recreateClient() async {
    _yt?.close();
    _yt = null;
    _cache.clear();
    _cacheExpiry.clear();
    await _getClient();
  }

  /// Главный вход: один манифест → и URL, и качества.
  Future<StreamResolution> resolve(String videoId, {String? quality}) async {
    final key = quality == null ? videoId : '${videoId}_$quality';
    final cached = _cache[key];
    final expiry = _cacheExpiry[key];
    if (cached != null && expiry != null && DateTime.now().isBefore(expiry)) {
      debugPrint('StreamService: cache hit for $key');
      return cached;
    }
    _cache.remove(key);
    _cacheExpiry.remove(key);

    final client = await _getClient();

    // Первые три клиента пробуем одновременно и берём того, кто ответит
    // первым. Раньше каждый неудачник съедал свой таймаут последовательно.
    final fast = await _race(
      _clientOrder.take(3).map((c) => _tryClient(client, videoId, c, quality)),
    );
    if (fast != null) return _store(key, fast);

    for (final clients in _clientOrder.skip(3)) {
      final res = await _tryClient(client, videoId, clients, quality);
      if (res != null) return _store(key, res);
    }

    // Единственный ретрай с пересозданием клиента: помогает, когда
    // закэшированная подпись устарела.
    await recreateClient();
    final retry = await _tryClient(
        await _getClient(), videoId, _clientOrder.first, quality);
    if (retry != null) return _store(key, retry);

    throw Exception('Не удалось получить поток. '
        'Попробуйте сменить прокси или повторить позже.');
  }

  /// Совместимость со старыми вызовами.
  Future<String> getPlayableUrl(String videoId, {String? quality}) async =>
      (await resolve(videoId, quality: quality)).url;

  Future<List<String>> getAvailableQualities(String videoId) async {
    try {
      return (await resolve(videoId)).qualities;
    } catch (_) {
      return const [];
    }
  }

  Future<StreamResolution?> _tryClient(
    YoutubeExplode client,
    String videoId,
    List<YoutubeApiClient> clients,
    String? quality,
  ) async {
    try {
      final manifest = await client.videos.streams
          .getManifest(videoId, ytClients: clients)
          .timeout(_perClientTimeout);

      final qualities = <String>{
        for (final s in manifest.muxed) '${s.videoResolution.height}p',
        for (final s in manifest.videoOnly) '${s.videoResolution.height}p',
      }.toList()
        ..sort((a, b) => (int.tryParse(b.replaceAll('p', '')) ?? 0)
            .compareTo(int.tryParse(a.replaceAll('p', '')) ?? 0));

      // HLS в приоритете: adaptive, быстрее стартует и не ограничен 360p,
      // в отличие от legacy muxed.
      if (manifest.hls.isNotEmpty) {
        final s = quality == null
            ? manifest.hls.first
            : manifest.hls.firstWhere(
                (s) => s.url.toString().contains(quality),
                orElse: () => manifest.hls.first);
        return StreamResolution(
            url: s.url.toString(),
            qualities: qualities.isEmpty ? const ['Auto'] : qualities,
            isHls: true);
      }

      if (manifest.muxed.isNotEmpty) {
        final s = quality == null
            ? manifest.muxed.withHighestBitrate()
            : manifest.muxed.firstWhere(
                (s) => '${s.videoResolution.height}p' == quality,
                orElse: () => manifest.muxed.withHighestBitrate());
        return StreamResolution(
            url: s.url.toString(), qualities: qualities, isHls: false);
      }
      return null;
    } catch (e) {
      debugPrint('StreamService: ✗ ${clients.first} — $e');
      return null;
    }
  }

  /// Первый непустой результат; null, если провалились все.
  Future<StreamResolution?> _race(
      Iterable<Future<StreamResolution?>> futures) async {
    final list = futures.toList();
    if (list.isEmpty) return null;
    final completer = Completer<StreamResolution?>();
    var pending = list.length;
    for (final f in list) {
      f.then((res) {
        if (res != null && !completer.isCompleted) {
          completer.complete(res);
        } else if (--pending == 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      }).catchError((_) {
        if (--pending == 0 && !completer.isCompleted) completer.complete(null);
      });
    }
    return completer.future;
  }

  StreamResolution _store(String key, StreamResolution res) {
    _cache[key] = res;
    _cacheExpiry[key] =
        DateTime.now().add(const Duration(minutes: _cacheDurationMinutes));
    return res;
  }

  /// Намеренно не закрывает клиент: он общий для всего приложения.
  void dispose() {}
}
