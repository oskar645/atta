import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/auth_service.dart';
import 'login_screen.dart';
import '../home/main_shell.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthService>();
      try {
        await auth.ensureInitialized();
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
      }
      if (!mounted) return;

      _sub = auth.onAuthStateChange.listen((state) {
        if (mounted) {
          setState(() {
            _initError = null;
          });
        }
      });

      setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
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
                    WidgetsBinding.instance.addPostFrameCallback((_) async {
                      final auth = context.read<AuthService>();
                      try {
                        await auth.ensureInitialized();
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
                      }
                      if (!mounted) return;
                      setState(() => _ready = true);
                    });
                  },
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!auth.isAuthenticated) return const LoginScreen();
    return const MainShell();
  }
}
