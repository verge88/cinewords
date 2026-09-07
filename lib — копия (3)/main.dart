import 'package:cinewords/services/video_catalog_runner.dart';
import 'package:cinewords/services/video_catalog_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'config/supabase_config.dart';
import 'providers/auth_provider.dart';
import 'providers/video_provider.dart';
import 'providers/player_provider.dart';
import 'providers/vocabulary_provider.dart';
import 'providers/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await SupabaseConfig.initialize();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => VideoProvider()),
        ChangeNotifierProvider(create: (_) => PlayerProvider()),
        ChangeNotifierProvider(create: (_) => VocabularyProvider()),
      ],
      child: const CineWordsApp(),
    ),
  );
}


// Вариант 1: Быстрый запуск с предустановками
Future<void> populateDatabase() async {
  final runner = CatalogRunner(Supabase.instance.client);
  await runner.run();
  runner.dispose();
}

// Вариант 2: Ручное добавление одного видео
Future<void> addSingleVideo(String youtubeUrl) async {
  final service = VideoCatalogService(
    supabaseClient: Supabase.instance.client,
  );

  final result = await service.addVideoById(
    youtubeVideoId: youtubeUrl, // или ID
    languages: ['en', 'ru'],
  );

  print('Result: ${result.status}, subtitles: ${result.subtitleCount}');
  service.dispose();
}

// Вариант 3: Кастомный поиск
Future<void> customSearch() async {
  final service = VideoCatalogService(
    supabaseClient: Supabase.instance.client,
    requestDelayMs: 2500,
    targetLanguages: ['en', 'es'],
  );

  final results = await service.searchAndPopulate(
    query: 'cooking tutorial easy recipes',
    maxResults: 20,
    requireCaptions: true,
    onProgress: (current, total, title) {
      print('Processing $current/$total: $title');
    },
  );

  final saved = results.where((r) => r.status == 'ready').length;
  print('Saved $saved videos');
  service.dispose();
}