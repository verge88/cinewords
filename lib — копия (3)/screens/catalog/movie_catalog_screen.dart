import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';
import '../../models/movie.dart';
import '../../services/kinopoisk_service.dart';
import '../../services/archive_org_service.dart';
import 'movie_detail_screen.dart';

enum CatalogSource { kinopoisk, archive }

class MovieCatalogScreen extends StatefulWidget {
  const MovieCatalogScreen({super.key});

  @override
  State<MovieCatalogScreen> createState() => _MovieCatalogScreenState();
}

class _MovieCatalogScreenState extends State<MovieCatalogScreen> {
  final KinopoiskService _kinopoisk = KinopoiskService();
  final ArchiveOrgService _archive = ArchiveOrgService();
  final TextEditingController _searchController = TextEditingController();
  CatalogSource _source = CatalogSource.kinopoisk;
  List<Movie> _movies = [];
  bool _isLoading = true;
  String? _error;

  Future<List<Movie>> _trending() => _source == CatalogSource.kinopoisk
      ? _kinopoisk.getTrendingMovies()
      : _archive.getTrendingMovies();

  Future<List<Movie>> _search(String q) => _source == CatalogSource.kinopoisk
      ? _kinopoisk.searchMovies(q)
      : _archive.searchMovies(q);

  @override
  void initState() {
    super.initState();
    _loadTrending();
  }

  Future<void> _loadTrending() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final movies = await _trending();
      if (mounted) {
        setState(() {
          _movies = movies;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _searchMovies(String query) async {
    if (query.isEmpty) {
      _loadTrending();
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final movies = await _search(query);
      if (mounted) {
        setState(() {
          _movies = movies;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Movies'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(116),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Column(
              children: [
                SegmentedButton<CatalogSource>(
                  segments: const [
                    ButtonSegment(
                      value: CatalogSource.kinopoisk,
                      label: Text('Kinopoisk'),
                      icon: Icon(Icons.movie_filter_outlined),
                    ),
                    ButtonSegment(
                      value: CatalogSource.archive,
                      label: Text('Archive.org'),
                      icon: Icon(Icons.public),
                    ),
                  ],
                  selected: {_source},
                  onSelectionChanged: (set) {
                    setState(() {
                      _source = set.first;
                      _searchController.clear();
                    });
                    _loadTrending();
                  },
                ),
                const SizedBox(height: 8),
                SearchBar(
                  controller: _searchController,
                  hintText: 'Search movies...',
                  onSubmitted: _searchMovies,
                  leading: const Icon(Icons.search),
                  trailing: [
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _loadTrending();
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? _buildShimmerGrid()
          : _error != null
              ? _buildError()
              : _movies.isEmpty
                  ? _buildEmpty()
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.7,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                      ),
                      itemCount: _movies.length,
                      itemBuilder: (context, index) {
                        final movie = _movies[index];
                        return _MovieCard(movie: movie);
                      },
                    ),
    );
  }

  Widget _buildShimmerGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.7,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
      ),
      itemCount: 6,
      itemBuilder: (context, index) => Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text(_error ?? 'Unknown error'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadTrending,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Text('No movies found'),
    );
  }

  @override
  void dispose() {
    _kinopoisk.dispose();
    _archive.dispose();
    _searchController.dispose();
    super.dispose();
  }
}

class _MovieCard extends StatelessWidget {
  final Movie movie;

  const _MovieCard({required this.movie});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MovieDetailScreen(movie: movie),
          ),
        );
      },
      child: Hero(
        tag: 'movie-${movie.id}',
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            image: movie.posterUrl.isNotEmpty
                ? DecorationImage(
                    image: NetworkImage(movie.posterUrl),
                    fit: BoxFit.cover,
                  )
                : null,
            color: Colors.grey[900],
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.8),
                ],
              ),
            ),
            padding: const EdgeInsets.all(12),
            alignment: Alignment.bottomLeft,
            child: Text(
              movie.title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    ).animate().fadeIn().scale();
  }
}
