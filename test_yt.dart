import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  final yt = YoutubeExplode();
  final manifest = await yt.videos.streams.getManifest('tpej1HqWbQ8');
  for (var stream in manifest.hls) {
    print('HLS Stream:');
    print('  url: ${stream.url.toString().substring(0, 30)}');
    print('  resolution: ${stream.videoResolution}'); 
  }
  yt.close();
}
