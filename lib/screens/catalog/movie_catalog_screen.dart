import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
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

  // Debounce поискового ввода фильмов.
  Timer? _searchDebounce;
  String _lastSearchQuery = '';
  static const _searchDebounceDuration = Duration(milliseconds: 400);

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      if (_lastSearchQuery.isNotEmpty) {
        _lastSearchQuery = '';
        _loadTrending();
      }
      return;
    }
    _searchDebounce = Timer(_searchDebounceDuration, () {
      if (!mounted) return;
      if (trimmed == _lastSearchQuery) return;
      _lastSearchQuery = trimmed;
      _searchMovies(trimmed);
    });
  }

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
                  onChanged: _onSearchChanged,
                  onSubmitted: (q) {
                    _searchDebounce?.cancel();
                    final trimmed = q.trim();
                    if (trimmed.isEmpty || trimmed == _lastSearchQuery) {
                      return;
                    }
                    _lastSearchQuery = trimmed;
                    _searchMovies(trimmed);
                  },
                  leading: const Icon(Icons.search),
                  trailing: [
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchDebounce?.cancel();
                          _searchController.clear();
                          _lastSearchQuery = '';
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
    _searchDebounce?.cancel();
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Постер — кэшируется на диске, без повторных загрузок.
              if (movie.posterUrl.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: movie.posterUrl,
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 200),
                  placeholder: (_, __) => Container(color: Colors.grey[900]),
                  errorWidget: (_, __, ___) =>
                      Container(color: Colors.grey[900]),
                )
              else
                Container(color: Colors.grey[900]),

              // Градиент для читаемости заголовка.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.8),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
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
            ],
          ),
        ),
      ),
    ).animate().fadeIn().scale();
  }
}
