import 'package:supabase_flutter/supabase_flutter.dart';

/// Central access point for the Supabase client.
/// Use [supabase] anywhere in the app instead of Supabase.instance.client.
SupabaseClient get supabase => Supabase.instance.client;

const _supabaseUrl = 'https://cwkhqrcuflzbhdznukyh.supabase.co';
const _supabaseAnonKey =
    'sb_publishable_frixdiPAQdw726biwT_eaQ_QL_sf_ZX';

/// Call once in main() before runApp().
Future<void> initSupabase() async {
  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
  );
}
