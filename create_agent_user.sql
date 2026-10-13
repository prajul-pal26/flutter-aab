-- ==============================================================================
-- CREATE AGENT USER SCRIPT FOR SUPABASE
-- Run this in your Supabase SQL Editor:
-- ==============================================================================

DO $$
DECLARE
  new_user_id UUID := gen_random_uuid();
  user_email TEXT := 'agent@qualitysurvey.com';
  user_pass TEXT := 'UJZjxN5qnlBW';
BEGIN
  -- Check if user already exists
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE email = user_email) THEN
    -- Insert into Supabase Auth
    INSERT INTO auth.users (
      instance_id,
      id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      recovery_sent_at,
      last_sign_in_at,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at,
      confirmation_token,
      email_change,
      email_change_token_new,
      recovery_token
    ) VALUES (
      '00000000-0000-0000-0000-000000000000',
      new_user_id,
      'authenticated',
      'authenticated',
      user_email,
      crypt(user_pass, gen_salt('bf')),
      NOW(),
      NOW(),
      NOW(),
      '{"provider":"email","providers":["email"]}',
      '{"username":"agent","full_name":"Survey Agent"}',
      NOW(),
      NOW(),
      '',
      '',
      '',
      ''
    );

    -- Insert into public.profiles
    INSERT INTO public.profiles (
      id,
      username,
      full_name,
      role
    ) VALUES (
      new_user_id,
      'agent',
      'Survey Agent',
      'surveyor'
    ) ON CONFLICT (id) DO NOTHING;

    RAISE NOTICE 'User % created successfully with ID %', user_email, new_user_id;
  ELSE
    RAISE NOTICE 'User % already exists.', user_email;
  END IF;
END $$;
