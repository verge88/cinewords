import 'package:flutter/material.dart';
import '../models/word_card.dart';
import '../services/supabase_service.dart';

class VocabularyProvider extends ChangeNotifier {
  List<WordCard> _allWords = [];
  List<WordCard> _reviewQueue = [];
  bool _isLoading = false;
  int _currentReviewIndex = 0;

  // Кэш для производных значений — пересчитывается один раз при изменении
  // _allWords (через _recomputeDerived), а не на каждый build/get.
  int _newCount = 0;
  int _learningCount = 0;
  int _reviewCount = 0;
  int _masteredCount = 0;
  List<WordCard> _wordsOnly = const [];
  List<WordCard> _phrasesOnly = const [];

  List<WordCard> get allWords => _allWords;
  List<WordCard> get wordsOnly => _wordsOnly;
  List<WordCard> get phrasesOnly => _phrasesOnly;
  List<WordCard> get reviewQueue => _reviewQueue;
  bool get isLoading => _isLoading;
  int get currentReviewIndex => _currentReviewIndex;
  WordCard? get currentReviewCard =>
      _reviewQueue.isNotEmpty && _currentReviewIndex < _reviewQueue.length
          ? _reviewQueue[_currentReviewIndex]
          : null;

  int get newCount => _newCount;
  int get learningCount => _learningCount;
  int get reviewCount => _reviewCount;
  int get masteredCount => _masteredCount;

  /// Один проход по списку — кэшируем все агрегаты сразу.
  void _recomputeDerived() {
    int n = 0, l = 0, r = 0, m = 0;
    final words = <WordCard>[];
    final phrases = <WordCard>[];
    for (final w in _allWords) {
      switch (w.status) {
        case 'new':
          n++;
          break;
        case 'learning':
          l++;
          break;
        case 'review':
          r++;
          break;
        case 'mastered':
          m++;
          break;
      }
      if (w.type == 'word') {
        words.add(w);
      } else if (w.type == 'phrase') {
        phrases.add(w);
      }
    }
    _newCount = n;
    _learningCount = l;
    _reviewCount = r;
    _masteredCount = m;
    _wordsOnly = words;
    _phrasesOnly = phrases;
  }

  String _currentExerciseType = 'flashcard'; // flashcard, multiple_choice, typing, word_builder
  String get currentExerciseType => _currentExerciseType;

  void setExerciseType(String type) {
    _currentExerciseType = type;
    notifyListeners();
  }

  List<String> getMultipleChoiceOptions(WordCard card) {
    final correct = card.translation ?? '';
    final distractors = _allWords
        .where((w) => w.id != card.id && w.translation != null && w.translation!.isNotEmpty)
        .map((w) => w.translation!)
        .toSet()
        .toList();
    
    distractors.shuffle();
    final options = distractors.take(3).toList();
    options.add(correct);
    options.shuffle();
    return options;
  }

  Future<void> loadAll({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      _allWords = await SupabaseService.getUserVocabulary();
      _reviewQueue = await SupabaseService.getWordsToReview();
      _currentReviewIndex = 0;
      _recomputeDerived();
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
    String? phonetic,
    String? contextSentence,
    String? contextVideoId,
    int? contextTimestampMs,
    String type = 'word',
  }) async {
    try {
      final card = await SupabaseService.addWord(
        word: word,
        translation: translation,
        phonetic: phonetic,
        contextSentence: contextSentence,
        contextVideoId: contextVideoId,
        contextTimestampMs: contextTimestampMs,
        type: type,
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
      _recomputeDerived();
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting word: $e');
    }
  }
}
