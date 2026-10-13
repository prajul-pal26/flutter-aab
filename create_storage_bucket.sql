-- ==============================================================================
-- CREATE STORAGE BUCKET & PERMISSIONS FOR AUDIO RECORDINGS
-- Run this in your Supabase SQL Editor:
-- ==============================================================================

-- 1. Create the bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('survey_audios', 'survey_audios', true)
ON CONFLICT (id) DO NOTHING;

-- 2. Allow authenticated surveyors to upload audio files
CREATE POLICY "Allow authenticated audio uploads"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'survey_audios');

-- 3. Allow public reading of audio files
CREATE POLICY "Allow public audio access"
ON storage.objects
FOR SELECT
USING (bucket_id = 'survey_audios');
