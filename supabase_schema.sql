-- ==============================================================================
-- 1. DISTRICTS TABLE (Static Master Data)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.districts (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
);

-- ==============================================================================
-- 2. CONSTITUENCIES TABLE (403 ACs mapped to Districts)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.constituencies (
    id SERIAL PRIMARY KEY,
    ac_number INT UNIQUE NOT NULL,
    ac_name_en TEXT NOT NULL,
    ac_name_hi TEXT NOT NULL,
    district_id INT REFERENCES public.districts(id) ON DELETE CASCADE NOT NULL
);

-- ==============================================================================
-- 3. PROFILES TABLE (Superadmin & Surveyors)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    full_name TEXT NOT NULL,
    role TEXT DEFAULT 'surveyor' CHECK (role IN ('superadmin', 'surveyor')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==============================================================================
-- 4. SURVEY RESPONSES TABLE
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.survey_responses (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    surveyor_id UUID REFERENCES public.profiles(id) NOT NULL,
    district_id INT REFERENCES public.districts(id) NOT NULL,
    ac_id INT REFERENCES public.constituencies(id) NOT NULL,
    
    -- Survey Questions
    father_name TEXT NOT NULL,
    age INT NOT NULL CHECK (age > 0 AND age < 130),
    
    -- Audio metadata
    audio_file_url TEXT NOT NULL,
    recording_duration_seconds INT,
    
    submitted_at TIMESTAMPTZ DEFAULT NOW()
);

-- Fast Index for AC and District Lookups & Live Stats
CREATE INDEX IF NOT EXISTS idx_responses_ac_id ON public.survey_responses(ac_id);
CREATE INDEX IF NOT EXISTS idx_responses_submitted_at ON public.survey_responses(submitted_at);
