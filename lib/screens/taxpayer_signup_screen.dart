import 'package:flutter/material.dart';

import '../branding/branding_scope.dart';
import '../services/gestia_data_service.dart';
import '../theme/app_colors.dart';
import '../widgets/theme_mode_menu_button.dart';

class TaxpayerSignupScreen extends StatefulWidget {
  const TaxpayerSignupScreen({
    super.key,
    required this.onBack,
    required this.onOpenLogin,
  });

  final VoidCallback onBack;
  final VoidCallback onOpenLogin;

  @override
  State<TaxpayerSignupScreen> createState() => _TaxpayerSignupScreenState();
}

class _TaxpayerSignupScreenState extends State<TaxpayerSignupScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final fullName = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (fullName.isEmpty || email.isEmpty || password.isEmpty || confirm.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Remplissez tous les champs.')),
      );
      return;
    }
    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Le mot de passe doit contenir au moins 6 caractères.'),
        ),
      );
      return;
    }
    if (password != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La confirmation du mot de passe ne correspond pas.'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await GestiaDataService.registerContribuable(
        email: email,
        password: password,
        fullName: fullName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compte crée. Connexion en cours...')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _SignupBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: _submitting ? null : widget.onBack,
                                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                                label: const Text('Retour'),
                                style: TextButton.styleFrom(
                                  foregroundColor: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                          ThemeModeMenuButton(iconColor: cs.onSurface),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: AppColors.primary.withValues(
                              alpha: 0.18,
                            ),
                            child: const Icon(
                              Icons.badge_outlined,
                              color: AppColors.primary,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  BrandingScope.of(context).appName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 17,
                                    color: cs.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Espace contribuable',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Créer mon compte',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Le système crée automatiquement votre identifiant personnel de contribuable. Vous pourrez ensuite payer vous-même vos taxes.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                              height: 1.4,
                            ),
                      ),
                      const SizedBox(height: 28),
                      Card(
                        elevation: 0,
                        color: cs.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: cs.outline.withValues(
                              alpha:
                                  Theme.of(context).brightness == Brightness.dark
                                      ? 0.35
                                      : 0.2,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _FieldLabel(label: 'Nom complet', color: cs.onSurface),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _nameController,
                                textCapitalization: TextCapitalization.words,
                                decoration: _inputDecoration(
                                  cs,
                                  hintText: 'Prénom et nom',
                                  icon: Icons.person_outline_rounded,
                                ),
                              ),
                              const SizedBox(height: 18),
                              _FieldLabel(
                                label: 'Adresse e-mail',
                                color: cs.onSurface,
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: _inputDecoration(
                                  cs,
                                  hintText: 'vous@exemple.cd',
                                  icon: Icons.mail_outline_rounded,
                                ),
                              ),
                              const SizedBox(height: 18),
                              _FieldLabel(label: 'Mot de passe', color: cs.onSurface),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _passwordController,
                                obscureText: true,
                                decoration: _inputDecoration(
                                  cs,
                                  hintText: 'Au moins 6 caractères',
                                  icon: Icons.lock_outline_rounded,
                                ),
                              ),
                              const SizedBox(height: 18),
                              _FieldLabel(
                                label: 'Confirmer le mot de passe',
                                color: cs.onSurface,
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _confirmController,
                                obscureText: true,
                                onSubmitted: (_) => _submit(),
                                decoration: _inputDecoration(
                                  cs,
                                  hintText: 'Retapez le mot de passe',
                                  icon: Icons.verified_user_outlined,
                                ),
                              ),
                              const SizedBox(height: 18),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: AppColors.primary.withValues(alpha: 0.14),
                                  ),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                    'Après création, un ID contribuable unique sera rattaché à votre compte et visible dans votre espace.',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _submitting ? null : _submit,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: _submitting
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Créer mon compte',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _submitting ? null : widget.onOpenLogin,
                                child: const Text('J\'ai déjà un compte'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(
    ColorScheme cs, {
    required String hintText,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hintText,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: cs.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.35)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.35)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: AppColors.primary,
          width: 1.5,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

class _SignupBackground extends StatelessWidget {
  const _SignupBackground();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF07111A), Color(0xFF0D1B2A), Color(0xFF0B1220)]
              : const [Color(0xFFF7FBFF), Color(0xFFE8F4FF), Color(0xFFF3F8FB)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            left: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: isDark ? 0.16 : 0.08),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            right: -20,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0FC2A5).withValues(
                  alpha: isDark ? 0.16 : 0.08,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
