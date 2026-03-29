import 'package:flutter/material.dart';
import '../../models/movie.dart';
import '../../widgets/vidsrc_player_widget.dart';

class MoviePlayerScreen extends StatelessWidget {
  final Movie movie;

  const MoviePlayerScreen({super.key, required this.movie});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(movie.title),
        centerTitle: true,
      ),
      body: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: VidsrcPlayerWidget(tmdbId: movie.id),
        ),
      ),
    );
  }
}
