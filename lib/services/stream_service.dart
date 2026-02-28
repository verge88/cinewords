import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class StreamService {
  YoutubeExplode? _yt;

  YoutubeExplode get yt {
    _yt ??= YoutubeExplode();
    return _yt!;
  }

  /// Get best playable stream URL with multiple fallback strategies.
  /// Returns (url, isAudioOnly) pair.
  Future<String> getPlayableUrl(String videoId) async {
    // Strategy 1: Muxed stream (audio + video, up to 720p)
    try {
      final url = await _tryMuxed(videoId);
      if (url != null) {
        debugPrint('StreamService: Got muxed stream for $videoId');
        return url;
      }
    } catch (e) {
      debugPrint('StreamService: Muxed failed: $e');
    }

    // Strategy 2: HLS stream
    try {
      final url = await _tryHls(videoId);
      if (url != null) {
        debugPrint('StreamService: Got HLS stream for $videoId');
        return url;
      }
    } catch (e) {
      debugPrint('StreamService: HLS failed: $e');
    }

    // Strategy 3: Recreate client and retry muxed
    try {
      _yt?.close();
      _yt = YoutubeExplode();
      final url = await _tryMuxed(videoId);
      if (url != null) {
        debugPrint('StreamService: Got muxed stream on retry for $videoId');
        return url;
      }
    } catch (e) {
      debugPrint('StreamService: Retry muxed failed: $e');
    }

    // Strategy 4: Try different YouTube clients
    try {
      final url = await _tryWithClients(videoId);
      if (url != null) {
        debugPrint('StreamService: Got stream via alt client for $videoId');
        return url;
      }
    } catch (e) {
      debugPrint('StreamService: Alt client failed: $e');
    }

    throw Exception(
        'Could not get stream for $videoId. The video may be restricted.');
  }

  Future<String?> _tryMuxed(String videoId) async {
    final manifest = await yt.videos.streams.getManifest(videoId);
    if (manifest.muxed.isNotEmpty) {
      final stream = manifest.muxed.withHighestBitrate();
      return stream.url.toString();
    }
    return null;
  }

  Future<String?> _tryHls(String videoId) async {
    final manifest = await yt.videos.streams.getManifest(videoId);
    if (manifest.hls.isNotEmpty) {
      return manifest.hls.first.url.toString();
    }
    return null;
  }

  Future<String?> _tryWithClients(String videoId) async {
    final clients = [
      [YoutubeApiClient.safari],
      [YoutubeApiClient.androidVr],
      [YoutubeApiClient.android],
      [YoutubeApiClient.ios],
    ];

    for (final clientList in clients) {
      try {
        final manifest = await yt.videos.streams.getManifest(
          videoId,
          ytClients: clientList,
        );
        if (manifest.muxed.isNotEmpty) {
          return manifest.muxed.withHighestBitrate().url.toString();
        }
        if (manifest.hls.isNotEmpty) {
          return manifest.hls.first.url.toString();
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// Get separate audio + video URLs for HQ playback
  Future<({String videoUrl, String audioUrl})?> getHqStreams(
      String videoId) async {
    try {
      final manifest = await yt.videos.streams.getManifest(videoId);
      if (manifest.videoOnly.isEmpty || manifest.audioOnly.isEmpty) {
        return null;
      }
      final video = manifest.videoOnly.sortByVideoQuality().last;
      final audio = manifest.audioOnly.withHighestBitrate();
      return (videoUrl: video.url.toString(), audioUrl: audio.url.toString());
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _yt?.close();
    _yt = null;
  }
}
