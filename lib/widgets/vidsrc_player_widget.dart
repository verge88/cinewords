import 'package:flutter/material.dart';
import 'vidapi_player_widget.dart';

class VidsrcPlayerWidget extends StatelessWidget {
  final int tmdbId;
  final bool isTvShow;
  final int? season;
  final int? episode;

  const VidsrcPlayerWidget({
    super.key,
    required this.tmdbId,
    this.isTvShow = false,
    this.season,
    this.episode,
  });

  String get _embedUrl {
    if (isTvShow) {
      return 'https://vidsrc.to/embed/tv/$tmdbId/${season ?? 1}/${episode ?? 1}';
    } else {
      return 'https://vidsrc.to/embed/movie/$tmdbId';
    }
  }

  @override
  Widget build(BuildContext context) {
    return VidApiPlayerWidget(embedUrl: _embedUrl);
  }
}
