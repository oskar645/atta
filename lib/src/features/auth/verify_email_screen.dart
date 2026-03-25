import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:atta/src/services/profile_service.dart';

class VerifyEmailScreen extends StatefulWidget {
  final String email;
  final String password;
  final String? name;
  final String? phone;

  const VerifyEmailScreen({
    super.key,
    required this.email,
    required this.password,
    this.name,
    this.phone,
  });

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _codeCtrl = TextEditingController();

  bool _sending = false;
  bool _verifying = false;

  SupabaseClient get _sb => Supabase.instance.client;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _resend() async {
    setState(() => _sending = true);
    try {
      // Отправит письмо повторно (и код тоже, если шаблон содержит {{ .Token }})
      await _sb.auth.resend(type: OtpType.signup, email: widget.email);
      _snack('Письмо отправлено ещё раз');
    } on AuthException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verifyCodeAndLogin() async {
    final code = _codeCtrl.text.trim();

    if (code.isEmpty) {
      _snack('Введите код из письма');
      return;
    }
    if (code.length != 6) {
      _snack('Код должен содержать 6 цифр');
      return;
    }

    setState(() => _verifying = true);

    try {
      // 1) Подтверждаем signup кодом
      final verifyRes = await _sb.auth.verifyOTP(
        type: OtpType.signup,
        email: widget.email,
        token: code,
      );

      // Иногда session может прийти сразу, иногда нет — подстрахуемся входом
      final session = verifyRes.session ?? _sb.auth.currentSession;
      User? user = verifyRes.user ?? _sb.auth.currentUser;

      if (session == null || user == null) {
        // 2) Если сессии нет — пробуем обычный вход паролем
        final authRes = await _sb.auth.signInWithPassword(
          email: widget.email,
          password: widget.password,
        );

        if (authRes.session == null || authRes.user == null) {
          throw const AuthException('Не удалось войти после подтверждения');
        }

        user = authRes.user!;
      }

      final userId = user.id;

      // ✅ НЕ ТРОГАЕМ твою структуру: сохраняем name/phone в public.users
      if (widget.name != null || widget.phone != null) {
        final profile = ProfileService();
        await profile.updateProfile(userId, {
          if (widget.name != null) 'display_name': widget.name,
          if (widget.name != null) 'name': widget.name,
          if (widget.phone != null) 'phone': widget.phone,
          // если у тебя в users есть email-колонка, можно сохранять и её:
          // 'email': widget.email,
        });
      }

      if (!mounted) return;

      // AuthGate увидит session и пустит в MainShell
      Navigator.of(context).pop();
    } on AuthException catch (e) {
      _snack('Код неверный или устарел: ${e.message}');
    } catch (e) {
      _snack('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Подтвердите email')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Мы отправили письмо с кодом на:\n${widget.email}'),
            const SizedBox(height: 12),
            const Text('Открой письмо, скопируй 6-значный код и введи его ниже.'),
            const SizedBox(height: 16),

            TextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Код из письма',
                hintText: 'Например: 123456',
              ),
              onSubmitted: (_) => _verifying ? null : _verifyCodeAndLogin(),
            ),

            const SizedBox(height: 16),

            FilledButton(
              onPressed: _verifying ? null : _verifyCodeAndLogin,
              child: Text(_verifying ? 'Проверяем...' : 'Подтвердить'),
            ),

            const SizedBox(height: 12),

            FilledButton.tonal(
              onPressed: _sending ? null : _resend,
              child: Text(_sending ? 'Отправляем...' : 'Отправить код ещё раз'),
            ),
          ],
        ),
      ),
    );
  }
}
