import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'video_catalog_service.dart';

/// Утилитарный класс для быстрого запуска каталогизации.
///
/// Пример использования:
/// ```dart
/// final runner = CatalogRunner(Supabase.instance.client);
/// await runner.run();
/// runner.dispose();
/// ```
class CatalogRunner {
  final VideoCatalogService _service;

  CatalogRunner(SupabaseClient client)
      : _service = VideoCatalogService(
    supabaseClient: client,
    requestDelayMs: 2000,   // 2 секунды между запросами
    targetLanguages: ['en'],
  );

  /// Запуск по предустановленным запросам для изучения английского
  Future<void> run() async {
    final queries = [
      'English conversation practice with subtitles',
      'Learn English with stories subtitles',
      'English listening practice beginner',
      'Daily English conversation',
      'English vocabulary lessons',
      'TED talks English subtitles',
      'English pronunciation practice',
      'Business English conversation',
      'IELTS listening practice',
      'English grammar explained',
    ];

    debugPrint('========================================');
    debugPrint(' VIDEO CATALOG POPULATION');
    debugPrint(' Queries: ${queries.length}');
    debugPrint(' Max per query: 30');
    debugPrint('========================================');

    final results = await _service.batchSearchAndPopulate(
      queries: queries,
      maxResultsPerQuery: 30,
      requireCaptions: true,
      languages: ['en'],
      onProgress: (current, total, title) {
        debugPrint('  [$current/$total] $title');
      },
    );

    // Итого
    int totalReady = 0;
    int totalSkipped = 0;
    int totalFailed = 0;
    int totalSubs = 0;

    for (final entry in results.entries) {
      final query = entry.key;
      final list = entry.value;

      final ready = list.where((r) => r.status == 'ready').length;
      final skipped = list.where((r) => r.status == 'skipped').length;
      final failed = list.where((r) => r.status == 'failed').length;
      final subs = list.fold<int>(0, (sum, r) => sum + r.subtitleCount);

      debugPrint('Query: "$query" → ready=$ready, '
          'skipped=$skipped, failed=$failed, subtitles=$subs');

      totalReady += ready;
      totalSkipped += skipped;
      totalFailed += failed;
      totalSubs += subs;
    }

    debugPrint('========================================');
    debugPrint(' TOTAL: ready=$totalReady, skipped=$totalSkipped, '
        'failed=$totalFailed');
    debugPrint(' Total subtitle lines: $totalSubs');
    debugPrint('========================================');

    // Статистика из базы
    final stats = await _service.getStats();
    debugPrint(' DB Stats: $stats');
  }

  void dispose() {
    _service.dispose();
  }
}