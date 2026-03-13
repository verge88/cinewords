-- Drop existing tables to avoid conflicts
DROP TABLE IF EXISTS daily_stats CASCADE;
DROP TABLE IF EXISTS vocabulary CASCADE;
DROP TABLE IF EXISTS word_cards CASCADE;
DROP TABLE IF EXISTS watch_history CASCADE;
DROP TABLE IF EXISTS user_progress CASCADE;
DROP TABLE IF EXISTS subtitles CASCADE;
DROP TABLE IF EXISTS videos CASCADE;
DROP TABLE IF EXISTS profiles CASCADE;

-- Profiles table (extends Supabase auth)
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users ON DELETE CASCADE,
  display_name TEXT,
  streak_days INTEGER DEFAULT 0,
  total_words_learned INTEGER DEFAULT 0,
  total_watch_minutes INTEGER DEFAULT 0,
  daily_goal_minutes INTEGER DEFAULT 15,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Trigger to create profile on sign up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name)
  VALUES (new.id, new.raw_user_meta_data->>'display_name');
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Backfill existing users (Fix for missing profiles error)
INSERT INTO public.profiles (id, display_name)
SELECT id, raw_user_meta_data->>'display_name' 
FROM auth.users
ON CONFLICT (id) DO NOTHING;

-- Videos table
CREATE TABLE videos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  youtube_id TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  thumbnail_url TEXT,
  duration_sec INTEGER,
  channel_name TEXT,
  view_count INTEGER DEFAULT 0,
  category TEXT,
  difficulty TEXT CHECK (difficulty IN ('beginner', 'intermediate', 'advanced')),
  is_featured BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Subtitles table
CREATE TABLE subtitles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  video_id UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
  language TEXT NOT NULL,
  start_ms INTEGER NOT NULL,
  end_ms INTEGER NOT NULL,
  text TEXT NOT NULL,
  translation TEXT,
  sequence_index INTEGER NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Watch history
CREATE TABLE watch_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  video_id UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
  last_position_ms INTEGER DEFAULT 0,
  watch_duration_seconds INTEGER DEFAULT 0,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(user_id, video_id)
);

-- Vocabulary table (SM-2 spaced repetition)
CREATE TABLE vocabulary (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  word TEXT NOT NULL,
  translation TEXT,
  context_sentence TEXT,
  context_video_id TEXT,
  context_timestamp_ms INTEGER,
  phonetic TEXT,
  
  status TEXT DEFAULT 'new' CHECK (status IN ('new', 'learning', 'review', 'mastered')),
  difficulty_score REAL DEFAULT 0.5,
  repetition_count INTEGER DEFAULT 0,
  next_review_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  ease_factor REAL DEFAULT 2.5,
  interval_days INTEGER DEFAULT 1,
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(user_id, word)
);

-- Daily stats for streak tracking
CREATE TABLE daily_stats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  minutes_watched INTEGER DEFAULT 0,
  words_added INTEGER DEFAULT 0,
  words_reviewed INTEGER DEFAULT 0,
  UNIQUE(user_id, date)
);

-- Create indexes for better query performance
CREATE INDEX idx_subtitles_video_id ON subtitles(video_id);
CREATE INDEX idx_watch_history_user_id ON watch_history(user_id);
CREATE INDEX idx_vocabulary_user_id ON vocabulary(user_id);
CREATE INDEX idx_vocabulary_status ON vocabulary(status);
CREATE INDEX idx_daily_stats_user_id ON daily_stats(user_id);

-- Enable Row Level Security
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE watch_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE vocabulary ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_stats ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own profile" ON profiles
  FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update their own profile" ON profiles
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can manage their watch history" ON watch_history
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can manage their vocabulary" ON vocabulary
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can view their daily stats" ON daily_stats
  FOR ALL USING (auth.uid() = user_id);

-- SM-2 Function
CREATE OR REPLACE FUNCTION update_vocabulary_sm2(p_vocab_id UUID, p_quality INTEGER)
RETURNS VOID AS $$
DECLARE
  v_card vocabulary%ROWTYPE;
  v_new_interval INTEGER;
  v_new_reps INTEGER;
  v_new_ease REAL;
  v_new_status TEXT;
BEGIN
  SELECT * INTO v_card FROM vocabulary WHERE id = p_vocab_id;
  IF NOT FOUND THEN RETURN; END IF;

  -- Quality: 0=Blackout, 1=Incorrect, 2=Incorrect (easy), 3=Hard, 4=Good, 5=Perfect
  IF p_quality < 3 THEN
    v_new_reps := 0;
    v_new_interval := 1;
  ELSE
    v_new_reps := v_card.repetition_count + 1;
    IF v_new_reps = 1 THEN
      v_new_interval := 1;
    ELSIF v_new_reps = 2 THEN
      v_new_interval := 6;
    ELSE
      v_new_interval := ROUND(v_card.interval_days * v_card.ease_factor);
    END IF;
  END IF;

  v_new_ease := v_card.ease_factor + (0.1 - (5 - p_quality) * (0.08 + (5 - p_quality) * 0.02));
  IF v_new_ease < 1.3 THEN
    v_new_ease := 1.3;
  END IF;

  IF v_new_interval > 365 THEN
    v_new_interval := 365;
  END IF;

  IF v_new_interval >= 21 THEN
    v_new_status := 'mastered';
  ELSIF v_new_interval > 1 THEN
    v_new_status := 'review';
  ELSE
    v_new_status := 'learning';
  END IF;

  UPDATE vocabulary SET
    repetition_count = v_new_reps,
    interval_days = v_new_interval,
    ease_factor = v_new_ease,
    next_review_at = CURRENT_TIMESTAMP + (v_new_interval || ' days')::interval,
    status = v_new_status,
    updated_at = CURRENT_TIMESTAMP
  WHERE id = p_vocab_id;
  
  -- Update daily stats
  INSERT INTO daily_stats (user_id, date, words_reviewed)
  VALUES (v_card.user_id, CURRENT_DATE, 1)
  ON CONFLICT (user_id, date) DO UPDATE SET words_reviewed = daily_stats.words_reviewed + 1;
END;
$$ LANGUAGE plpgsql;

-- Streak updating function
CREATE OR REPLACE FUNCTION update_streak(p_user_id UUID)
RETURNS VOID AS $$
DECLARE
  v_last_watch DATE;
  v_current_streak INTEGER;
BEGIN
  SELECT MAX(date) INTO v_last_watch FROM daily_stats WHERE user_id = p_user_id AND minutes_watched > 0;
  
  SELECT streak_days INTO v_current_streak FROM profiles WHERE id = p_user_id;
  
  IF v_last_watch IS NULL OR v_last_watch < CURRENT_DATE - INTERVAL '1 day' THEN
    v_current_streak := 1;
  ELSIF v_last_watch = CURRENT_DATE - INTERVAL '1 day' THEN
    v_current_streak := v_current_streak + 1;
  END IF;
  
  UPDATE profiles SET 
    streak_days = v_current_streak,
    updated_at = CURRENT_TIMESTAMP
  WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql;

-- Trigger to track words added
CREATE OR REPLACE FUNCTION track_word_added()
RETURNS trigger AS $$
BEGIN
  INSERT INTO daily_stats (user_id, date, words_added)
  VALUES (NEW.user_id, CURRENT_DATE, 1)
  ON CONFLICT (user_id, date) DO UPDATE 
  SET words_added = daily_stats.words_added + 1;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS on_word_added ON vocabulary;
CREATE TRIGGER on_word_added
  AFTER INSERT ON vocabulary
  FOR EACH ROW EXECUTE PROCEDURE track_word_added();

-- Trigger to track mastered words
CREATE OR REPLACE FUNCTION track_word_mastered()
RETURNS trigger AS $$
BEGIN
  IF NEW.status = 'mastered' AND OLD.status != 'mastered' THEN
    UPDATE profiles 
    SET total_words_learned = total_words_learned + 1
    WHERE id = NEW.user_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS on_word_mastered ON vocabulary;
CREATE TRIGGER on_word_mastered
  AFTER UPDATE ON vocabulary
  FOR EACH ROW EXECUTE PROCEDURE track_word_mastered();

-- Safely log watch progress and update minutes
CREATE OR REPLACE FUNCTION log_watch_progress(
  p_user_id UUID,
  p_video_id UUID,
  p_position_ms INTEGER,
  p_duration_sec INTEGER
)
RETURNS VOID AS $$
DECLARE
  v_minutes_to_add INTEGER;
BEGIN
  -- 1. Insert or update watch history
  INSERT INTO watch_history (user_id, video_id, last_position_ms, watch_duration_seconds)
  VALUES (p_user_id, p_video_id, p_position_ms, p_duration_sec)
  ON CONFLICT (user_id, video_id) DO UPDATE 
  SET last_position_ms = p_position_ms,
      watch_duration_seconds = watch_history.watch_duration_seconds + p_duration_sec,
      updated_at = CURRENT_TIMESTAMP;

  -- Convert reported seconds chunk into minutes to add (if any)
  v_minutes_to_add := CEIL(p_duration_sec::float / 60.0);
  
  -- 2. Update daily stats
  INSERT INTO daily_stats (user_id, date, minutes_watched)
  VALUES (p_user_id, CURRENT_DATE, v_minutes_to_add)
  ON CONFLICT (user_id, date) DO UPDATE 
  SET minutes_watched = daily_stats.minutes_watched + v_minutes_to_add;

  -- 3. Update profile totals
  UPDATE profiles 
  SET total_watch_minutes = total_watch_minutes + v_minutes_to_add
  WHERE id = p_user_id;

  -- 4. Automatically check streak
  PERFORM update_streak(p_user_id);
END;
$$ LANGUAGE plpgsql;
