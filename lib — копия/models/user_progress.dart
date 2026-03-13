class UserProgress {
  final int streakDays;
  final int totalWordsLearned;
  final int totalWatchMinutes;
  final int dailyGoalMinutes;
  final int todayMinutes;
  final int todayWords;
  final int todayReviewed;
  final int wordsToReview;

  const UserProgress({
    this.streakDays = 0,
    this.totalWordsLearned = 0,
    this.totalWatchMinutes = 0,
    this.dailyGoalMinutes = 15,
    this.todayMinutes = 0,
    this.todayWords = 0,
    this.todayReviewed = 0,
    this.wordsToReview = 0,
  });

  double get dailyProgressPercent {
    if (dailyGoalMinutes <= 0) return 0;
    return (todayMinutes / dailyGoalMinutes).clamp(0.0, 1.0);
  }
}
