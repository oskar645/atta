import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'privacy_screen.dart';
import 'terms_screen.dart';
import 'verify_email_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _isLogin = true;
  bool _loading = false;
  bool _hasAcceptedLegal = false;

  SupabaseClient get _sb => Supabase.instance.client;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _niceAuthError(AuthException e) {
    final msg = e.message.toLowerCase();

    if (msg.contains('email rate limit exceeded')) {
      return 'Слишком часто отправляли письма. Подождите немного и попробуйте снова.';
    }
    if (msg.contains('invalid login credentials')) {
      return 'Неверный email или пароль.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Email не подтверждён. Откройте письмо и подтвердите адрес.';
    }
    if (msg.contains('user already registered')) {
      return 'Этот email уже зарегистрирован. Попробуйте войти.';
    }
    return e.message;
  }

  Future<void> _resetPassword() async {
    final email = _emailCtrl.text.trim();

    if (email.isEmpty) {
      _snack('Введите email, чтобы восстановить пароль');
      return;
    }

    setState(() => _loading = true);
    try {
      await _sb.auth.resetPasswordForEmail(
        email,
        redirectTo: kIsWeb ? null : 'io.supabase.flutter://reset-callback/',
      );
      _snack('Письмо для смены пароля отправлено на почту');
    } on AuthException catch (e) {
      _snack(_niceAuthError(e));
    } catch (e) {
      _snack('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    if (email.isEmpty || pass.isEmpty) {
      _snack('Введите email и пароль');
      return;
    }

    if (!_isLogin) {
      if (name.isEmpty) {
        _snack('Введите имя');
        return;
      }
      if (phone.isEmpty) {
        _snack('Введите номер телефона');
        return;
      }
      if (!_hasAcceptedLegal) {
        _snack('Примите Пользовательское соглашение и Политику конфиденциальности');
        return;
      }
    }

    setState(() => _loading = true);

    try {
      if (_isLogin) {
        final res = await _sb.auth.signInWithPassword(email: email, password: pass);

        if (res.session == null) {
          throw const AuthException(
            'Не удалось войти. Подтвердите email и попробуйте снова.',
          );
        }
      } else {
        await _sb.auth.signUp(
          email: email,
          password: pass,
          data: {
            'name': name,
            'displayName': name,
            'phone': phone,
            'acceptedTerms': _hasAcceptedLegal,
            'acceptedPrivacyPolicy': _hasAcceptedLegal,
          },
        );

        if (!mounted) return;

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VerifyEmailScreen(
              email: email,
              password: pass,
              name: name,
              phone: phone,
            ),
          ),
        );
      }
    } on AuthException catch (e) {
      _snack(_niceAuthError(e));
    } catch (e) {
      _snack('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openTerms() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TermsScreen()),
    );
  }

  void _openPrivacy() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PrivacyScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSubmitRegistration = !_loading && _hasAcceptedLegal;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isLogin ? 'Вход' : 'Регистрация'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_isLogin) ...[
            TextField(
              controller: _nameCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Имя'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Телефон'),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            obscureText: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'Пароль'),
            onSubmitted: (_) {
              if (_isLogin && !_loading) {
                _submit();
              } else if (!_isLogin && canSubmitRegistration) {
                _submit();
              }
            },
          ),
          if (!_isLogin) ...[
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _hasAcceptedLegal,
                      onChanged: _loading
                          ? null
                          : (value) {
                              setState(() {
                                _hasAcceptedLegal = value ?? false;
                              });
                            },
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: RichText(
                          text: TextSpan(
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface,
                              height: 1.5,
                            ),
                            children: [
                              const TextSpan(text: 'Я принимаю '),
                              TextSpan(
                                text: 'Пользовательское соглашение',
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                                recognizer: TapGestureRecognizer()..onTap = _openTerms,
                              ),
                              const TextSpan(text: ' и '),
                              TextSpan(
                                text: 'Политику конфиденциальности',
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                                recognizer: TapGestureRecognizer()..onTap = _openPrivacy,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_isLogin) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _loading ? null : _resetPassword,
                child: const Text('Забыли пароль?'),
              ),
            ),
          ],
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _isLogin
                ? (_loading ? null : _submit)
                : (canSubmitRegistration ? _submit : null),
            child: Text(
              _loading
                  ? 'Подождите...'
                  : (_isLogin ? 'Войти' : 'Зарегистрироваться'),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _loading
                ? null
                : () {
                    setState(() {
                      _isLogin = !_isLogin;
                      _passCtrl.clear();
                      if (_isLogin) {
                        _hasAcceptedLegal = false;
                      }
                    });
                  },
            child: Text(
              _isLogin ? 'Нет аккаунта? Регистрация' : 'Уже есть аккаунт? Войти',
            ),
          ),
        ],
      ),
    );
  }
}
