import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'branding/app_branding_controller.dart';
import 'branding/branding_scope.dart';
import 'config/supabase_env.dart';
import 'models/app_section.dart';
import 'models/section_visibility.dart';
import 'models/user_profile.dart';
import 'screens/login_screen.dart';
import 'screens/quick_access_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/supabase_setup_screen.dart';
import 'screens/taxpayer_signup_screen.dart';
import 'services/gestia_data_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'theme/theme_scope.dart';
import 'widgets/main_shell.dart';

class GestiaApp extends StatefulWidget {
  const GestiaApp({super.key});

  @override
  State<GestiaApp> createState() => _GestiaAppState();
}

class _GestiaAppState extends State<GestiaApp> {
  late final ThemeController _theme;
  late final AppBrandingController _branding;

  @override
  void initState() {
    super.initState();
    _theme = ThemeController();
    _theme.load();
    _branding = AppBrandingController();
    _branding.load();
  }

  @override
  void dispose() {
    _theme.dispose();
    _branding.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _theme,
      builder: (context, _) {
        return ListenableBuilder(
          listenable: _branding,
          builder: (context, _) {
            return ThemeScope(
              notifier: _theme,
              child: BrandingScope(
                notifier: _branding,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  title: _branding.appName,
                  theme: buildGestiaTheme(),
                  darkTheme: buildGestiaDarkTheme(),
                  themeMode: _theme.mode,
                  home: const AppRoot(),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

enum _AuthPhase { splash, welcome, login, signup }

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  _AuthPhase _phase = _AuthPhase.splash;
  UserProfile? _profile;
  bool _loadingProfile = false;
  StreamSubscription<AuthState>? _authSub;
  AppSection _currentSection = AppSection.dashboard;

  @override
  void initState() {
    super.initState();
    if (!SupabaseEnv.isConfigured) return;
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    if (session != null) {
      _loadProfile(session.user.id);
    }
    _authSub = client.auth.onAuthStateChange.listen((data) {
      final s = data.session;
      if (s == null) {
        if (mounted) {
          setState(() {
            _profile = null;
            _loadingProfile = false;
            _currentSection = AppSection.dashboard;
          });
        }
      } else {
        _loadProfile(s.user.id);
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile(String userId) async {
    if (!mounted) return;
    setState(() => _loadingProfile = true);
    try {
      final p = await GestiaDataService.fetchProfile(userId);
      if (!mounted) return;
      setState(() {
        _profile = p;
        _loadingProfile = false;
        if (p != null) {
          if (!isSectionVisible(p.role, _currentSection)) {
            _currentSection = defaultSectionForRole(p.role);
          }
        }
      });
    } catch (e, st) {
      developer.log(
        'Chargement profil échoué',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      setState(() {
        _profile = null;
        _loadingProfile = false;
      });
    }
  }

  Future<void> _signOut() async {
    if (SupabaseEnv.isConfigured) {
      await Supabase.instance.client.auth.signOut();
    }
    if (mounted) {
      setState(() {
        _profile = null;
        _phase = _AuthPhase.welcome;
        _currentSection = AppSection.dashboard;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!SupabaseEnv.isConfigured) {
      return const SupabaseSetupScreen();
    }

    final session = Supabase.instance.client.auth.currentSession;

    if (session != null) {
      if (_loadingProfile) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }
      if (_profile == null) {
        final u = Supabase.instance.client.auth.currentUser;
        final uid = u?.id ?? '—';
        final email = u?.email ?? '—';
        final projectUrl = SupabaseEnv.url.isEmpty
            ? '(SUPABASE_URL non définie — vérifiez --dart-define-from-file)'
            : SupabaseEnv.url;
        return Scaffold(
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Aucune ligne dans `profiles` pour ce compte, ou la '
                      'lecture est bloquée (RLS). Vérifiez ci‑dessous.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Projet : $projectUrl',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'E-mail connecté : $email',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'ID session (doit = profiles.id) :',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      uid,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Dans Supabase → SQL Editor, exécutez la migration '
                      '`20250409120000_get_my_profile_rpc.sql` puis insérez une ligne '
                      'dont id = cet UUID, role = admin_provincial, commune_id = null.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _signOut,
                      child: const Text('Se déconnecter'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      final p = _profile!;
      return MainShell(
        profile: p,
        currentSection: _currentSection,
        onSectionSelected: (section) {
          setState(() => _currentSection = section);
        },
        onLogout: _signOut,
        onProfileChanged: () {
          final id = session.user.id;
          _loadProfile(id);
        },
      );
    }

    switch (_phase) {
      case _AuthPhase.splash:
        return SplashScreen(
          onFinished: () {
            setState(() => _phase = _AuthPhase.welcome);
          },
        );
      case _AuthPhase.welcome:
        return QuickAccessScreen(
          onConnect: () {
            setState(() => _phase = _AuthPhase.login);
          },
          onRegister: () {
            setState(() => _phase = _AuthPhase.signup);
          },
        );
      case _AuthPhase.login:
        return LoginScreen(
          onBack: () {
            setState(() => _phase = _AuthPhase.welcome);
          },
          onOpenSignUp: () {
            setState(() => _phase = _AuthPhase.signup);
          },
        );
      case _AuthPhase.signup:
        return TaxpayerSignupScreen(
          onBack: () {
            setState(() => _phase = _AuthPhase.welcome);
          },
          onOpenLogin: () {
            setState(() => _phase = _AuthPhase.login);
          },
        );
    }
  }
}
