import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const int _minPasswordDigits = 8;

bool _isValidPassword(String value) {
  final trimmed = value.trim();
  return trimmed.length >= _minPasswordDigits &&
      RegExp(r'^\d+$').hasMatch(trimmed);
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _newPass = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _newPass.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    final np = _newPass.text.trim();
    if (!_isValidPassword(np)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Новый пароль минимум 6 символов')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final client = Supabase.instance.client;

      // ✅ смена пароля в Supabase
      await client.auth.updateUser(
        UserAttributes(password: np),
      );

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пароль изменён')),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Изменить пароль')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _newPass,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Новый пароль (мин. 6)',
              ),
              onSubmitted: (_) => _saving ? null : _change(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _change,
                child: Text(_saving ? 'Сохраняем…' : 'Сменить пароль'),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Если Supabase попросит повторный вход — просто выйди и войди снова.',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
