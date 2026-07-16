import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _newPass = TextEditingController();
  final bool _saving = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _newPass.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Смена пароля внутри профиля временно недоступна. Используйте восстановление по номеру телефона.',
        ),
      ),
    );
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
              enabled: false,
              obscureText: _obscurePassword,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Новый пароль',
                helperText: 'Минимум 8 символов',
                suffixIcon: IconButton(
                  tooltip:
                      _obscurePassword ? 'Показать пароль' : 'Скрыть пароль',
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              onSubmitted: (_) => _saving ? null : _change(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _change,
                child: Text(
                  _saving
                      ? 'Сохраняем…'
                      : 'Используйте восстановление по телефону',
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'В режиме Timeweb пароль меняется через сценарий восстановления по номеру телефона.',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
