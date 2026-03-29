-- Migration: Add video sources
ALTER TABLE videos 
  ADD COLUMN IF NOT EXISTS source_type TEXT DEFAULT 'youtube',
  ADD COLUMN IF NOT EXISTS video_url TEXT;

-- Drop NOT NULL from youtube_id
ALTER TABLE videos ALTER COLUMN youtube_id DROP NOT NULL;
