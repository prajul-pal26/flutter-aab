-- ==============================================================================
-- 1. ACTIVATE / CONFIRM USER & INSERT PROFILE (RUN IN SUPABASE SQL EDITOR)
-- ==============================================================================

-- Make sure user is auto-confirmed in auth.users
UPDATE auth.users
SET email_confirmed_at = NOW(),
    confirmed_at = NOW(),
    last_sign_in_at = NOW()
WHERE email = 'agent@qualitysurvey.com';

-- Insert into public.profiles where username is purely 'agent'
INSERT INTO public.profiles (
    id,
    username,
    full_name,
    role
)
SELECT 
    id,
    'agent',
    'Survey Agent',
    'surveyor'
FROM auth.users
WHERE email = 'agent@qualitysurvey.com'
ON CONFLICT (id) DO UPDATE 
SET username = 'agent', role = 'surveyor';
