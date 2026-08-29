import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/auth_service.dart';
import 'blocked_account_screen.dart';
import 'login_screen.dart';
import '../home/main_shell.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    this.authenticatedBuilder,
    this.unauthenticatedBuilder,
    this.bootstrapTimeout = _defaultBootstrapTimeout,
  });

  final WidgetBuilder? authenticatedBuilder;
  final WidgetBuilder? unauthenticatedBuilder;
  final Duration bootstrapTimeout;

  static const Duration _defaultBootstrapTimeout = Duration(seconds: 10);

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthSessionEvent>? _sub;
  bool _ready = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeAuth());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _initializeAuth() async {
    final auth = context.read<AuthService>();
    _sub ??= auth.onAuthStateChange.listen((state) {
      if (mounted) {
        setState(() {
          _initError = null;
        });
      }
    });

    try {
      await auth.ensureInitialized().timeout(widget.bootstrapTimeout);
    } on TimeoutException {
      if (!mounted) return;
      if (!auth.isAuthenticated) {
        setState(() {
          _initError = 'Проверьте интернет-соединение и попробуйте снова.';
        });
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _initError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initError = 'Не удалось восстановить сессию.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _ready = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    if (auth.isAuthenticated) {
      if (auth.currentUser?.isBlocked == true) {
        return const BlockedAccountScreen();
      }
      final authenticatedBuilder = widget.authenticatedBuilder;
      return authenticatedBuilder != null
          ? authenticatedBuilder(context)
          : const MainShell();
    }

    if (!_ready) {
      return const _StartupLoadingScreen();
    }

    if (_initError != null && !auth.isAuthenticated) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _initError!,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _ready = false;
                      _initError = null;
                    });
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _initializeAuth());
                  },
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final unauthenticatedBuilder = widget.unauthenticatedBuilder;
    return unauthenticatedBuilder != null
        ? unauthenticatedBuilder(context)
        : const LoginScreen(initialIsLogin: false);
  }
}

class _StartupLoadingScreen extends StatelessWidget {
  const _StartupLoadingScreen();

  @override
  Widget build(BuildContext context) {
    final color =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.92);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                key: const ValueKey('atta_startup_logo'),
                width: 132,
                height: 56,
                child: Image.asset(
                  'assets/branding/atta_logo.png',
                  fit: BoxFit.contain,
                  semanticLabel: 'ATTA',
                  errorBuilder: (context, error, stackTrace) {
                    return Text(
                      'Atta',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: color,
                        fontSize: 34,
                        height: 1,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.6,
                        fontFamily: 'serif',
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              const SizedBox(
                key: ValueKey('atta_startup_spinner'),
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
