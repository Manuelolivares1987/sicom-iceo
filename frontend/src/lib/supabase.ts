import { createClient } from '@supabase/supabase-js'

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!

// Using untyped client since we don't have auto-generated Supabase types.
// Types are enforced at the service layer via manual type assertions.
export const supabase = createClient(supabaseUrl, supabaseAnonKey)
