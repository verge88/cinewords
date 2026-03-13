import 'package:flutter/material.dart';
import '../models/word_card.dart';
import '../services/supabase_service.dart';

class VocabularyProvider extends ChangeNotifier {
  List<WordCard> _allWords = [];
  List<WordCard> _reviewQueue = [];
  bool _isLoading = false;
  int _currentReviewIndex = 0;

  List<WordCard> get allWords => _allWords;
  List<WordCard> get reviewQueue => _reviewQueue;
  bool get isLoading => _isLoading;
  int get currentReviewIndex => _currentReviewIndex;
  WordCard? get currentReviewCard =>
      _reviewQueue.isNotEmpty && _currentReviewIndex < _reviewQueue.length
          ? _reviewQueue[_currentReviewIndex]
          : null;

  int get newCount => _allWords.where((w) => w.status == 'new').length;
  int get learningCount => _allWords.where((w) => w.status == 'learning').length;
  int get reviewCount => _allWords.where((w) => w.status == 'review').length;
  int get masteredCount => _allWords.where((w) => w.status == 'mastered').length;

  Future<void> loadAll({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      _allWords = await SupabaseService.getUserVocabulary();
      _reviewQueue = await SupabaseService.getWordsToReview();
      _currentReviewIndex = 0;
    } catch (e) {
      debugPrint('Error loading vocabulary: $e');
    }

    if (!silent) {
      _isLoading = false;
    }
    notifyListeners();
  }

  void preparePractice() {
    if (_reviewQueue.isEmpty) {
      final available = _allWords.where((w) => w.status != 'mastered').toList();
      available.shuffle();
      _reviewQueue = available.take(20).toList();
    }
    _currentReviewIndex = 0;
    notifyListeners();
  }

  Future<void> addWord({
    required String word,
    String? translation,
    String? contextSentence,
    String? contextVideoId,
    int? contextTimestampMs,
  }) async {
    try {
      final card = await SupabaseService.addWord(
        word: word,
        translation: translation,
        contextSentence: contextSentence,
        contextVideoId: contextVideoId,
        contextTimestampMs: contextTimestampMs,
      );
      await loadAll(silent: true);
    } catch (e) {
      debugPrint('Error adding word: $e');
      rethrow;
    }
  }

  Future<void> reviewCurrentWord(int quality) async {
    final card = currentReviewCard;
    if (card == null) return;

    try {
      await SupabaseService.reviewWord(card.id, quality);
      _currentReviewIndex++;
      if (_currentReviewIndex >= _reviewQueue.length) {
        // Reload
        await loadAll();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error reviewing word: $e');
    }
  }

  Future<void> deleteWord(String id) async {
    try {
      await SupabaseService.deleteWord(id);
      _allWords.removeWhere((w) => w.id == id);
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting word: $e');
    }
  }
}
