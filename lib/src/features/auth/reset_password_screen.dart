import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const int _minPasswordDigits = 8;

bool _isValidPassword(String value) {
  final trimmed = value.trim();
  return trimmed.length >= _minPasswordDigits &&
      RegExp(r'^\d+$').hasMatch(trimmed);
}

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _pass1 = TextEditingController();
  final _pass2 = TextEditingController();
  bool _loading = false;

  SupabaseClient get _sb => Supabase.instance.client;

  @override
  void dispose() {
    _pass1.dispose();
    _pass2.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save() async {
    final p1 = _pass1.text.trim();
    final p2 = _pass2.text.trim();

    if (p1.isEmpty || p2.isEmpty) {
      _snack('Введите новый пароль и повторите его');
      return;
    }
    if (p1 != p2) {
      _snack('Пароли не совпадают');
      return;
    }
    if (!_isValidPassword(p1)) {
      _snack('Пароль должен быть минимум 6 символов');
      return;
    }

    setState(() => _loading = true);
    try {
      await _sb.auth.updateUser(UserAttributes(password: p1));
      _snack('Пароль обновлён. Теперь можно войти.');

      if (!mounted) return;
      Navigator.of(context).pop(); // вернёмся на логин
    } on AuthException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новый пароль')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _pass1,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Новый пароль'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass2,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Повторите пароль'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : _save,
              child: Text(_loading ? 'Сохраняем...' : 'Сохранить пароль'),
            ),
          ],
        ),
      ),
    );
  }
}
