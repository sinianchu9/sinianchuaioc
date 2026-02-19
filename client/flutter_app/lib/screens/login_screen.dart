import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_localizations.dart';
import '../core/theme.dart';
import '../core/api_service.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController(text: 'admin@aioc.internal');
  final _passwordController = TextEditingController(text: '123456');
  final _serverController = TextEditingController(text: ApiService.baseUrl);
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  bool _showServerConfig = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final l10n = context.l10n;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F0F23), Color(0xFF1A1A3E), Color(0xFF0F0F23)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AIOCTheme.primary, AIOCTheme.accent],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AIOCTheme.primary.withOpacity(0.4),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.auto_awesome,
                          size: 40,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Title
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [AIOCTheme.primary, AIOCTheme.accent],
                        ).createShader(bounds),
                        child: const Text(
                          'AIOC',
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.t('appTitle'),
                        style: TextStyle(
                          fontSize: 14,
                          color: AIOCTheme.textSecondary,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 48),

                      // Login Card
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AIOCTheme.surfaceCard.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AIOCTheme.primary.withOpacity(0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Email field
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              style: const TextStyle(
                                color: AIOCTheme.textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText: l10n.t('email'),
                                prefixIcon: const Icon(
                                  Icons.email_outlined,
                                  color: AIOCTheme.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Password field
                            TextField(
                              controller: _passwordController,
                              obscureText: true,
                              style: const TextStyle(
                                color: AIOCTheme.textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText: l10n.t('password'),
                                prefixIcon: const Icon(
                                  Icons.lock_outline,
                                  color: AIOCTheme.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Error message
                            if (authState.error != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AIOCTheme.error.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    authState.error!,
                                    style: const TextStyle(
                                      color: AIOCTheme.error,
                                      fontSize: 13,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),

                            // Login button
                            SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: authState.isLoading
                                    ? null
                                    : () {
                                        ref
                                            .read(authProvider.notifier)
                                            .login(
                                              _emailController.text.trim(),
                                              _passwordController.text,
                                            );
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AIOCTheme.primary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: authState.isLoading
                                    ? const SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        l10n.t('signIn'),
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Server config toggle
                      TextButton.icon(
                        onPressed: () => setState(
                          () => _showServerConfig = !_showServerConfig,
                        ),
                        icon: Icon(
                          _showServerConfig
                              ? Icons.keyboard_arrow_up
                              : Icons.settings,
                          size: 18,
                          color: AIOCTheme.textSecondary,
                        ),
                        label: Text(
                          l10n.t('serverConfiguration'),
                          style: TextStyle(
                            color: AIOCTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),

                      if (_showServerConfig) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: _serverController,
                          style: const TextStyle(
                            color: AIOCTheme.textPrimary,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            hintText: l10n.t('serverUrl'),
                            prefixIcon: const Icon(
                              Icons.dns_outlined,
                              color: AIOCTheme.textSecondary,
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(
                                Icons.check,
                                color: AIOCTheme.success,
                              ),
                              onPressed: () {
                                ref
                                    .read(authProvider.notifier)
                                    .updateServerUrl(
                                      _serverController.text.trim(),
                                    );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(l10n.t('serverUpdated')),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
