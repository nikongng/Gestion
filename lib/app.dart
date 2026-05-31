import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'branding/app_branding_controller.dart';
import 'branding/branding_scope.dart';
import 'config/supabase_env.dart';
import 'models/app_section.dart';
import 'models/app_role.dart';
import 'models/section_visibility.dart';
import 'models/user_profile.dart';
import 'screens/login_screen.dart';
import 'screens/quick_access_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/supabase_setup_screen.dart';
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

enum _AuthPhase { splash, welcome, login }

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
  bool _focusRecoveryControlOnCollecte = false;
  AppRole _selectedLoginRole = AppRole.taxateur;
  bool _roleGateActive = false;
  Timer? _autoSessionTimer;
  bool _autoSessionEnabled = false;
  bool _checkingMfa = false;
  bool _mfaRequired = false;
  String? _mfaCheckedUserId;
  bool? _mfaCheckedSetting;
  List<Factor> _mfaChallengeFactors = const [];

  static const _autoSessionTimeout = Duration(minutes: 30);

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
            _focusRecoveryControlOnCollecte = false;
            _roleGateActive = false;
            _resetMfaState();
            _stopAutoSession();
          });
        }
      } else {
        _loadProfile(s.user.id);
      }
    });
  }

  @override
  void dispose() {
    _autoSessionTimer?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  void _stopAutoSession() {
    _autoSessionTimer?.cancel();
    _autoSessionTimer = null;
    _autoSessionEnabled = false;
  }

  void _syncAutoSession({required bool enabled, required bool signedIn}) {
    final shouldRun = enabled && signedIn;
    if (_autoSessionEnabled == shouldRun &&
        (_autoSessionTimer != null || !shouldRun)) {
      return;
    }
    _autoSessionEnabled = shouldRun;
    _autoSessionTimer?.cancel();
    _autoSessionTimer = null;
    if (shouldRun) _bumpAutoSession();
  }

  void _bumpAutoSession() {
    if (!_autoSessionEnabled) return;
    _autoSessionTimer?.cancel();
    _autoSessionTimer = Timer(_autoSessionTimeout, _handleAutoSessionTimeout);
  }

  Future<void> _handleAutoSessionTimeout() async {
    if (!mounted || Supabase.instance.client.auth.currentSession == null) {
      return;
    }
    await _signOut();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Session expirée pour inactivité.')),
    );
  }

  void _resetMfaState() {
    _checkingMfa = false;
    _mfaRequired = false;
    _mfaCheckedUserId = null;
    _mfaCheckedSetting = null;
    _mfaChallengeFactors = const [];
  }

  void _ensureMfaRequirement({required bool enabled, required String userId}) {
    if (!enabled) {
      if (_mfaCheckedSetting != false || _checkingMfa || _mfaRequired) {
        _checkingMfa = false;
        _mfaRequired = false;
        _mfaCheckedUserId = userId;
        _mfaCheckedSetting = false;
        _mfaChallengeFactors = const [];
      }
      return;
    }
    if (_mfaCheckedUserId == userId && _mfaCheckedSetting == enabled) {
      return;
    }
    _mfaCheckedUserId = userId;
    _mfaCheckedSetting = enabled;
    _checkingMfa = true;
    _mfaRequired = false;
    _mfaChallengeFactors = const [];
    Future.microtask(() => _checkMfaRequirement(userId));
  }

  Future<void> _checkMfaRequirement(String userId) async {
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser?.id != userId) return;
      final factors = await client.auth.mfa.listFactors();
      final verifiedTotp = factors.totp
          .where((factor) => factor.status == FactorStatus.verified)
          .toList(growable: false);
      final aal = client.auth.mfa.getAuthenticatorAssuranceLevel();
      final needsChallenge =
          verifiedTotp.isNotEmpty &&
          aal.currentLevel != AuthenticatorAssuranceLevels.aal2 &&
          aal.nextLevel == AuthenticatorAssuranceLevels.aal2;
      if (!mounted || client.auth.currentUser?.id != userId) return;
      setState(() {
        _checkingMfa = false;
        _mfaRequired = needsChallenge;
        _mfaChallengeFactors = verifiedTotp;
      });
    } catch (e, st) {
      developer.log('Vérification DFA échouée', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _checkingMfa = false;
        _mfaRequired = false;
        _mfaChallengeFactors = const [];
      });
    }
  }

  void _handleMfaVerified() {
    setState(() {
      _checkingMfa = false;
      _mfaRequired = false;
      _mfaCheckedSetting = null;
      _mfaChallengeFactors = const [];
    });
  }

  Future<void> _loadProfile(String userId) async {
    if (!mounted) return;
    final requestedRole = _roleGateActive ? _selectedLoginRole : null;
    setState(() => _loadingProfile = true);
    try {
      final p = await GestiaDataService.fetchProfile(userId);
      if (!mounted) return;
      if (p != null && p.isSuspended) {
        await Supabase.instance.client.auth.signOut();
        if (!mounted) return;
        setState(() {
          _profile = null;
          _loadingProfile = false;
          _phase = _AuthPhase.login;
          _currentSection = AppSection.dashboard;
          _focusRecoveryControlOnCollecte = false;
          _roleGateActive = false;
          _resetMfaState();
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Compte introuvable.')));
        return;
      }
      if (_roleGateActive && p != null && !p.hasRole(_selectedLoginRole)) {
        await Supabase.instance.client.auth.signOut();
        if (!mounted) return;
        setState(() {
          _profile = null;
          _loadingProfile = false;
          _phase = _AuthPhase.login;
          _roleGateActive = true;
          _currentSection = AppSection.dashboard;
          _focusRecoveryControlOnCollecte = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Compte introuvable.')));
        return;
      }
      setState(() {
        _profile = p;
        _loadingProfile = false;
        _roleGateActive = false;
        if (p != null) {
          if (!isSectionVisibleForRoles(p.roles, _currentSection)) {
            _currentSection = requestedRole != null && p.hasRole(requestedRole)
                ? defaultSectionForRole(requestedRole)
                : defaultSectionForRole(p.role);
          }
        }
      });
    } catch (e, st) {
      developer.log('Chargement profil échoué', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _profile = null;
        _loadingProfile = false;
      });
    }
  }

  Future<void> _signOut() async {
    _stopAutoSession();
    if (SupabaseEnv.isConfigured) {
      await Supabase.instance.client.auth.signOut();
    }
    if (mounted) {
      setState(() {
        _profile = null;
        _phase = _AuthPhase.welcome;
        _currentSection = AppSection.dashboard;
        _focusRecoveryControlOnCollecte = false;
        _roleGateActive = false;
        _resetMfaState();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!SupabaseEnv.isConfigured) {
      return const SupabaseSetupScreen();
    }

    if (_phase == _AuthPhase.splash) {
      return SplashScreen(
        onFinished: () {
          setState(() => _phase = _AuthPhase.welcome);
        },
      );
    }

    final session = Supabase.instance.client.auth.currentSession;

    if (session != null) {
      if (_loadingProfile) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
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
      final branding = BrandingScope.of(context);
      _syncAutoSession(enabled: branding.autoSessionEnabled, signedIn: true);
      _ensureMfaRequirement(
        enabled: branding.twoFactorValidationEnabled,
        userId: session.user.id,
      );
      if (branding.maintenanceModeEnabled && !p.canManageApp) {
        return _MaintenanceScreen(onLogout: _signOut);
      }
      if (_checkingMfa) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (_mfaRequired) {
        return _MfaChallengeScreen(
          factors: _mfaChallengeFactors,
          onVerified: _handleMfaVerified,
          onLogout: _signOut,
        );
      }
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _bumpAutoSession(),
        onPointerMove: (_) => _bumpAutoSession(),
        onPointerSignal: (_) => _bumpAutoSession(),
        child: MainShell(
          profile: p,
          currentSection: _currentSection,
          focusRecoveryControlOnCollecte: _focusRecoveryControlOnCollecte,
          onSectionSelected: (section) {
            setState(() {
              _currentSection = section;
              _focusRecoveryControlOnCollecte = false;
            });
          },
          onOpenRecoveryControl: () {
            setState(() {
              _currentSection = AppSection.recouvrement;
              _focusRecoveryControlOnCollecte = true;
            });
          },
          onRecoveryControlOpened: () {
            if (!_focusRecoveryControlOnCollecte) return;
            setState(() => _focusRecoveryControlOnCollecte = false);
          },
          onLogout: _signOut,
          onProfileChanged: () {
            final id = session.user.id;
            _loadProfile(id);
          },
        ),
      );
    }

    switch (_phase) {
      case _AuthPhase.splash:
        return const SizedBox.shrink();
      case _AuthPhase.welcome:
        return QuickAccessScreen(
          onSelectAccountType: (role) {
            setState(() {
              _selectedLoginRole = role;
              _roleGateActive = true;
              _phase = _AuthPhase.login;
            });
          },
        );
      case _AuthPhase.login:
        return LoginScreen(
          expectedRole: _selectedLoginRole,
          onBack: () {
            setState(() {
              _roleGateActive = false;
              _phase = _AuthPhase.welcome;
            });
          },
        );
    }
  }
}

class _MaintenanceScreen extends StatelessWidget {
  const _MaintenanceScreen({required this.onLogout});

  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.construction_rounded,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 18),
                Text(
                  'Mode maintenance actif',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'L’accès est temporairement réservé à l’administrateur.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout_outlined),
                  label: const Text('Se déconnecter'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MfaChallengeScreen extends StatefulWidget {
  const _MfaChallengeScreen({
    required this.factors,
    required this.onVerified,
    required this.onLogout,
  });

  final List<Factor> factors;
  final VoidCallback onVerified;
  final Future<void> Function() onLogout;

  @override
  State<_MfaChallengeScreen> createState() => _MfaChallengeScreenState();
}

class _MfaChallengeScreenState extends State<_MfaChallengeScreen> {
  final _codeCtrl = TextEditingController();
  Factor? _selectedFactor;
  bool _verifying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.factors.isNotEmpty) _selectedFactor = widget.factors.first;
  }

  @override
  void didUpdateWidget(covariant _MfaChallengeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.factors.contains(_selectedFactor)) {
      _selectedFactor = widget.factors.isEmpty ? null : widget.factors.first;
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final factor = _selectedFactor;
    final code = _codeCtrl.text.trim();
    if (factor == null) {
      setState(() => _error = 'Aucun facteur DFA n’est configuré.');
      return;
    }
    if (code.isEmpty) {
      setState(() => _error = 'Saisissez le code de vérification.');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.mfa.challengeAndVerify(
        factorId: factor.id,
        code: code,
      );
      if (!mounted) return;
      widget.onVerified();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = 'Code DFA incorrect ou expiré.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.phonelink_lock_outlined,
                  size: 54,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 18),
                Text(
                  'Double facteur d’authentification',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Entrez le code généré par votre application '
                  'd’authentification.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                if (widget.factors.length > 1)
                  DropdownButtonFormField<Factor>(
                    initialValue: _selectedFactor,
                    items: [
                      for (final factor in widget.factors)
                        DropdownMenuItem(
                          value: factor,
                          child: Text(
                            factor.friendlyName?.trim().isNotEmpty == true
                                ? factor.friendlyName!.trim()
                                : 'Application d’authentification',
                          ),
                        ),
                    ],
                    onChanged: _verifying
                        ? null
                        : (factor) => setState(() => _selectedFactor = factor),
                    decoration: const InputDecoration(
                      labelText: 'Facteur DFA',
                      border: OutlineInputBorder(),
                    ),
                  ),
                if (widget.factors.length > 1) const SizedBox(height: 12),
                TextField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _verifying ? null : _verify(),
                  decoration: const InputDecoration(
                    labelText: 'Code à 6 chiffres',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _verifying ? null : _verify,
                  icon: _verifying
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_outlined),
                  label: Text(_verifying ? 'Vérification...' : 'Vérifier'),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: _verifying ? null : widget.onLogout,
                  icon: const Icon(Icons.logout_outlined),
                  label: const Text('Se déconnecter'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
