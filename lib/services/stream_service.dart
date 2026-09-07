import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Результат получения потока.
///
/// [url] — URL потока, который нужно открыть в плеере.
/// [qualities] — качества, которые можно вручную переключать.
/// [qualityUrls] — уже полученные URL для каждого ручного качества.
/// [isHls] — является ли основной поток HLS.
class StreamResolution {
  final String url;
  final List<String> qualities;
  final bool isHls;
  final Map<String, String> qualityUrls;

  const StreamResolution({
    required this.url,
    required this.qualities,
    required this.isHls,
    this.qualityUrls = const {},
  });
}

class StreamService {
  StreamService._();

  static final StreamService _instance = StreamService._();

  /// Singleton: клиент и кэш URL живут дольше одного экрана плеера.
  factory StreamService() => _instance;

  static YoutubeExplode? _yt;

  static final Map<String, StreamResolution> _cache = {};
  static final Map<String, DateTime> _cacheExpiry = {};

  static const int _cacheDurationMinutes = 30;
  static const Duration _perClientTimeout = Duration(seconds: 7);
  static const String _proxyPrefKey = 'youtube_proxy_url';

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

      return YoutubeExplode(
        YoutubeHttpClient(IOClient(httpClient)),
      );
    }

    return YoutubeExplode();
  }

  Future<YoutubeExplode> _getClient() async {
    return _yt ??= await _createClient();
  }

  Future<void> recreateClient() async {
    _yt?.close();
    _yt = null;

    _cache.clear();
    _cacheExpiry.clear();

    await _getClient();
  }

  /// Получает URL воспроизведения.
  ///
  /// Если [quality] не задано, возвращается автоматический HLS-поток
  /// либо лучший доступный muxed-поток.
  ///
  /// Если [quality] задано, возвращается muxed-поток, содержащий
  /// одновременно видео и аудио.
  Future<StreamResolution> resolve(
    String videoId, {
    String? quality,
  }) async {
    final requestedQuality =
        quality == null || quality == 'Auto' ? null : quality;

    final key = requestedQuality == null
        ? videoId
        : '${videoId}_$requestedQuality';

    final cached = _getValidCache(key);

    if (cached != null) {
      debugPrint('StreamService: cache hit for $key');
      return cached;
    }

    // При первом resolve сохраняются URL всех доступных muxed-качеств.
    // Поэтому при переключении качества повторный запрос к YouTube
    // в большинстве случаев не требуется.
    if (requestedQuality != null) {
      final baseResolution = _getValidCache(videoId);
      final cachedQualityUrl =
          baseResolution?.qualityUrls[requestedQuality];

      if (baseResolution != null && cachedQualityUrl != null) {
        debugPrint(
          'StreamService: cached quality URL '
          '$requestedQuality for $videoId',
        );

        return _store(
          key,
          StreamResolution(
            url: cachedQualityUrl,
            qualities: baseResolution.qualities,
            isHls: false,
            qualityUrls: baseResolution.qualityUrls,
          ),
        );
      }
    }

    final client = await _getClient();

    // Первые клиенты пробуем параллельно.
    final fastResult = await _race(
      _clientOrder.take(3).map(
            (clients) => _tryClient(
              client,
              videoId,
              clients,
              requestedQuality,
            ),
          ),
    );

    if (fastResult != null) {
      return _store(key, fastResult);
    }

    // Остальные клиенты — последовательно.
    for (final clients in _clientOrder.skip(3)) {
      final result = await _tryClient(
        client,
        videoId,
        clients,
        requestedQuality,
      );

      if (result != null) {
        return _store(key, result);
      }
    }

    // Единственная повторная попытка с новым YoutubeExplode.
    await recreateClient();

    final retryResult = await _tryClient(
      await _getClient(),
      videoId,
      _clientOrder.first,
      requestedQuality,
    );

    if (retryResult != null) {
      return _store(key, retryResult);
    }

    if (requestedQuality != null) {
      throw Exception(
        'Качество $requestedQuality недоступно для этого видео',
      );
    }

    throw Exception(
      'Не удалось получить поток. '
      'Попробуйте сменить прокси или повторить позже.',
    );
  }

  Future<String> getPlayableUrl(
    String videoId, {
    String? quality,
  }) async {
    final resolution = await resolve(
      videoId,
      quality: quality,
    );

    return resolution.url;
  }

  Future<List<String>> getAvailableQualities(String videoId) async {
    try {
      final result = await resolve(videoId);
      return result.qualities;
    } catch (_) {
      return const [];
    }
  }

  Future<StreamResolution?> _tryClient(
    YoutubeExplode client,
    String videoId,
    List<YoutubeApiClient> clients,
    String? requestedQuality,
  ) async {
    try {
      final manifest = await client.videos.streams
          .getManifest(
            videoId,
            ytClients: clients,
          )
          .timeout(_perClientTimeout);

      // Только muxed-потоки можно безопасно передать плееру одним URL:
      // они содержат и видео, и аудио.
      //
      // videoOnly здесь намеренно не используется, потому что в таком
      // потоке отсутствует звук.
      final qualityUrls = <String, String>{};

      for (final stream in manifest.muxed) {
        final quality = '${stream.videoResolution.height}p';

        final existingUrl = qualityUrls[quality];

        if (existingUrl == null) {
          qualityUrls[quality] = stream.url.toString();
        }
      }

      final qualities = qualityUrls.keys.toList()
        ..sort((a, b) {
          final aHeight =
              int.tryParse(a.replaceAll('p', '')) ?? 0;
          final bHeight =
              int.tryParse(b.replaceAll('p', '')) ?? 0;

          return bHeight.compareTo(aHeight);
        });

      // Ручное качество.
      //
      // В старой версии здесь сначала выбирался HLS. Из-за этого
      // запрошенное качество игнорировалось, поскольку HLS URL обычно
      // не содержит строки вида "360p" или "720p".
      if (requestedQuality != null) {
        final selectedUrl = qualityUrls[requestedQuality];

        if (selectedUrl == null) {
          debugPrint(
            'StreamService: ${clients.first} does not provide '
            'muxed quality $requestedQuality',
          );

          return null;
        }

        debugPrint(
          'StreamService: selected $requestedQuality '
          'using ${clients.first}',
        );

        return StreamResolution(
          url: selectedUrl,
          qualities: qualities,
          isHls: false,
          qualityUrls: qualityUrls,
        );
      }

      // Auto: HLS может самостоятельно адаптировать качество.
      if (manifest.hls.isNotEmpty) {
        final hls = manifest.hls.first;

        debugPrint(
          'StreamService: selected HLS Auto using ${clients.first}',
        );

        return StreamResolution(
          url: hls.url.toString(),
          qualities: qualities,
          isHls: true,
          qualityUrls: qualityUrls,
        );
      }

      // Если HLS нет, используем лучший muxed-поток.
      if (manifest.muxed.isNotEmpty) {
        final muxed = manifest.muxed.withHighestBitrate();

        debugPrint(
          'StreamService: selected highest muxed stream '
          'using ${clients.first}',
        );

        return StreamResolution(
          url: muxed.url.toString(),
          qualities: qualities,
          isHls: false,
          qualityUrls: qualityUrls,
        );
      }

      return null;
    } catch (e) {
      debugPrint(
        'StreamService: ✗ ${clients.first} — $e',
      );

      return null;
    }
  }

  StreamResolution? _getValidCache(String key) {
    final resolution = _cache[key];
    final expiry = _cacheExpiry[key];

    if (resolution == null || expiry == null) {
      return null;
    }

    if (DateTime.now().isAfter(expiry)) {
      _cache.remove(key);
      _cacheExpiry.remove(key);
      return null;
    }

    return resolution;
  }

  /// Возвращает первый успешный результат.
  Future<StreamResolution?> _race(
    Iterable<Future<StreamResolution?>> futures,
  ) async {
    final list = futures.toList();

    if (list.isEmpty) {
      return null;
    }

    final completer = Completer<StreamResolution?>();
    var pending = list.length;

    for (final future in list) {
      future.then((result) {
        if (result != null) {
          if (!completer.isCompleted) {
            completer.complete(result);
          }

          return;
        }

        pending--;

        if (pending == 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      }).catchError((_) {
        pending--;

        if (pending == 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      });
    }

    return completer.future;
  }

  StreamResolution _store(
    String key,
    StreamResolution resolution,
  ) {
    _cache[key] = resolution;
    _cacheExpiry[key] = DateTime.now().add(
      const Duration(minutes: _cacheDurationMinutes),
    );

    return resolution;
  }

  /// Клиент общий для всего приложения, поэтому здесь не закрывается.
  void dispose() {}
}
