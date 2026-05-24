import 'package:flutter/material.dart';

import '../config/supabase_env.dart';

/// Affiché lorsque `SUPABASE_URL` / `SUPABASE_ANON_KEY` ne sont pas définis.
class SupabaseSetupScreen extends StatelessWidget {
  const SupabaseSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.cloud_off_outlined, size: 56, color: cs.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Configurer Supabase',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Lancez l’application avec les clés du projet Supabase :',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SelectableText(
                    'flutter run --dart-define-from-file=gestia_secrets.json\n\n'
                    'ou\n\n'
                    'flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co '
                    '--dart-define=SUPABASE_ANON_KEY=eyJ...',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'URL configurée : ${SupabaseEnv.url.isEmpty ? "(vide)" : "oui"}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    'Clé anon : ${SupabaseEnv.anonKey.isEmpty ? "(vide)" : "définie"}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
