import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_env.dart';

/// Initialise Supabase si l’URL et la clé anon sont fournies.
Future<void> initSupabaseIfConfigured() async {
  if (!SupabaseEnv.isConfigured) return;
  await Supabase.initialize(
    url: SupabaseEnv.url,
    anonKey: SupabaseEnv.anonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
}

bool get isSupabaseReady => SupabaseEnv.isConfigured;
