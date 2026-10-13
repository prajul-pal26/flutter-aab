-- ==============================================================================
-- ADD LOCATION COLUMN TO SURVEY_RESPONSES TABLE
-- Run this in your Supabase SQL Editor:
-- ==============================================================================

ALTER TABLE public.survey_responses 
ADD COLUMN IF NOT EXISTS location JSONB;

-- Fast GIN index for location queries
CREATE INDEX IF NOT EXISTS idx_responses_location 
ON public.survey_responses USING GIN (location);

NOTIFY pgrst, 'reload schema';
