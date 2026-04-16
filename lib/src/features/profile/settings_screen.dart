import 'package:atta/src/features/notifications/notifications_screen.dart';
import 'package:atta/src/features/profile/about_app_screen.dart';
import 'package:atta/src/features/profile/change_password_screen.dart';
import 'package:atta/src/features/support/support_screen.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/phone_auth_backend_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneAuth = PhoneAuthBackendService();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthService>();
      final profile = context.read<ProfileService>();
      final uid = auth.currentUser!.uid;
      final data = await profile.getProfile(uid);
      final authEmail = _visibleEmail(auth.currentUser?.email);
      final profileEmail = _visibleEmail((data['email'] ?? '').toString());

      _nameCtrl.text =
          (data['display_name'] ?? data['displayName'] ?? data['name'] ?? '')
              .toString();
      _phoneCtrl.text = (data['phone'] ?? '').toString();
      _emailCtrl.text = profileEmail.isNotEmpty ? profileEmail : authEmail;

      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  String _visibleEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return '';
    if (email.endsWith('@phone.atta.local')) return '';
    return email;
  }

  bool _looksLikeEmail(String value) {
    final text = value.trim();
    if (text.isEmpty) return true;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text);
  }

  OutlineInputBorder _fieldBorder(BuildContext context) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }

  Future<void> _save() async {
    final auth = context.read<AuthService>();
    final profile = context.read<ProfileService>();
    final currentUser = auth.currentUser!;
    final uid = currentUser.uid;

    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final email = _emailCtrl.text.trim().toLowerCase();
    final currentEmail = _visibleEmail(currentUser.email);

    if (name.isEmpty) {
      showAppSnack(context, 'Введите имя', isError: true);
      return;
    }
    if (!_looksLikeEmail(email)) {
      showAppSnack(context, 'Введите корректный email', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      if (email.isNotEmpty && email != currentEmail) {
        await _phoneAuth.linkEmailToCurrentUser(email: email);
      }

      await auth.updateAuthMetadata(displayName: name);

      await profile.updateProfile(uid, {
        'display_name': name,
        'name': name,
        'phone': phone,
        if (email.isNotEmpty) 'email': email,
      });

      if (!mounted) return;
      showAppSnack(context, 'Сохранено');
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Ошибка: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? iconColor,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          leading: Icon(icon, color: iconColor),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final border = _fieldBorder(context);
    final email = _emailCtrl.text.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
        centerTitle: false,
      ),
      body: ListView(
        children: [
          _sectionTitle('Профиль'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                TextField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Имя',
                    border: border,
                    enabledBorder: border,
                    focusedBorder: border,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Телефон',
                    border: border,
                    enabledBorder: border,
                    focusedBorder: border,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    hintText: 'name@example.com',
                    border: border,
                    enabledBorder: border,
                    focusedBorder: border,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Сохраняем...' : 'Сохранить изменения'),
            ),
          ),
          _sectionTitle('Аккаунт'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              email.isEmpty
                  ? 'Добавьте email, чтобы он был привязан к вашему аккаунту и его можно было использовать для входа.'
                  : 'Текущий email привязан к вашему аккаунту и сохраняется в профиле.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _tile(
            icon: Icons.lock_outline,
            title: 'Сменить пароль',
            subtitle: 'Изменить текущий пароль',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ChangePasswordScreen(),
                ),
              );
            },
          ),
          _sectionTitle('Приложение'),
          _tile(
            icon: Icons.notifications_none,
            title: 'Уведомления',
            subtitle: 'Общие и личные уведомления',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const NotificationsScreen(),
                ),
              );
            },
          ),
          _tile(
            icon: Icons.help_outline,
            title: 'Поддержка',
            subtitle: 'Задать вопрос',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SupportScreen(),
                ),
              );
            },
          ),
          _tile(
            icon: Icons.info_outline,
            title: 'О приложении',
            subtitle: 'Версия и правила',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AboutAppScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
