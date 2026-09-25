import 'package:atta/src/features/notifications/notifications_screen.dart';
import 'package:atta/src/features/profile/about_app_screen.dart';
import 'package:atta/src/features/profile/security_screen.dart';
import 'package:atta/src/features/support/support_screen.dart';
import 'package:atta/src/services/auth_service.dart';
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
  String _savedName = '';
  bool _nameChanged = false;
  bool _saving = false;
  bool _deletingAccount = false;
  bool _loadingMarketingConsent = true;
  bool _marketingConsent = false;

  @override
  void initState() {
    super.initState();
    final currentUser = context.read<AuthService>().currentUser;
    if (currentUser != null) {
      _nameCtrl.text = (currentUser.displayName ?? '').trim();
    }
    _savedName = _nameCtrl.text.trim();
    _nameCtrl.addListener(_handleNameChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthService>();
      final profile = context.read<ProfileService>();
      final uid = auth.currentUser!.uid;
      final data = await profile.getProfile(uid);
      final loadedName =
          (data['display_name'] ?? data['displayName'] ?? data['name'] ?? '')
              .toString()
              .trim();
      final resolvedName = loadedName.isNotEmpty ? loadedName : _nameCtrl.text;
      _savedName = resolvedName.trim();
      _nameCtrl.text = resolvedName;
      if (mounted) {
        setState(() => _nameChanged = false);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthService>();
      try {
        final accepted = await auth.getMarketingConsent();
        if (!mounted) return;
        setState(() {
          _marketingConsent = accepted;
          _loadingMarketingConsent = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _loadingMarketingConsent = false);
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_handleNameChanged);
    _nameCtrl.dispose();
    super.dispose();
  }

  void _handleNameChanged() {
    final changed = _nameCtrl.text.trim() != _savedName;
    if (changed == _nameChanged || !mounted) return;
    setState(() => _nameChanged = changed);
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

    if (name.isEmpty) {
      showAppSnack(context, 'Введите имя', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await auth.updateAuthMetadata(displayName: name);

      await profile.updateProfile(uid, {
        'display_name': name,
        'name': name,
      });

      if (!mounted) return;
      setState(() {
        _savedName = name;
        _nameChanged = false;
      });
      showAppSnack(context, 'Сохранено');
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Ошибка: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteAccount() async {
    if (_deletingAccount) return;
    final auth = context.read<AuthService>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить аккаунт'),
        content: const Text(
          'Вы уверены, что хотите удалить аккаунт? Это действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _deletingAccount = true);
    try {
      await auth.deleteAccount();
      if (!mounted) return;
      showAppSnack(context, 'Ваш аккаунт удалён.');
    } catch (e) {
      if (!mounted) return;
      final message = auth.userMessageForError(e);
      showAppSnack(context, message, isError: true);
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  Future<void> _setMarketingConsent(bool accepted) async {
    final previous = _marketingConsent;
    setState(() {
      _marketingConsent = accepted;
      _loadingMarketingConsent = true;
    });

    try {
      final saved = await context.read<AuthService>().updateMarketingConsent(
            accepted: accepted,
          );
      if (!mounted) return;
      setState(() {
        _marketingConsent = saved;
        _loadingMarketingConsent = false;
      });
      showAppSnack(
        context,
        saved
            ? 'Маркетинговые сообщения включены'
            : 'Маркетинговые сообщения выключены',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _marketingConsent = previous;
        _loadingMarketingConsent = false;
      });
      showAppSnack(
        context,
        'Не удалось обновить согласие. Попробуйте позже.',
        isError: true,
      );
    }
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
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
    Color? titleColor,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          leading: Icon(icon, color: iconColor),
          title: Text(title, style: TextStyle(color: titleColor)),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: trailing ?? const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final border = _fieldBorder(context);
    final user = context.watch<AuthService>().currentUser!;
    final recoveryEmail = (user.email ?? '').trim();
    final hasRecoveryEmail = recoveryEmail.isNotEmpty &&
        !recoveryEmail.endsWith('@phone.atta.local');
    final securityComplete = user.phoneVerified && user.emailVerified;
    final securityColor = securityComplete
        ? Colors.green.shade700
        : Theme.of(context).colorScheme.error;

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
            child: TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: 'Имя',
                border: border,
                enabledBorder: border,
                focusedBorder: border,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                height: 42,
                child: FilledButton(
                  key: const ValueKey('save-name'),
                  onPressed: _nameChanged && !_saving ? _save : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  child: Text(_saving ? 'Сохраняем...' : 'Сохранить'),
                ),
              ),
            ),
          ),
          _sectionTitle('Аккаунт'),
          _tile(
            icon: Icons.shield_outlined,
            iconColor: securityColor,
            title: 'Безопасность',
            titleColor: securityColor,
            subtitle: !hasRecoveryEmail
                ? 'Добавьте email для восстановления доступа'
                : user.emailVerified
                    ? 'Email для восстановления доступа подключён'
                    : 'Подтвердите email для восстановления доступа',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: securityColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SecurityScreen(),
                ),
              );
              if (mounted) setState(() {});
            },
          ),
          _tile(
            icon: Icons.delete_outline,
            iconColor: Theme.of(context).colorScheme.error,
            title: _deletingAccount ? 'Удаляем аккаунт...' : 'Удалить аккаунт',
            subtitle: 'Удаление профиля и снятие объявлений с публикации',
            onTap: _deletingAccount ? null : _deleteAccount,
          ),
          _sectionTitle('Приложение'),
          SwitchListTile(
            secondary: const Icon(Icons.campaign_outlined),
            title: const Text('Рекламные уведомления'),
            subtitle: const Text(
              'Акции, новости и предложения ATTA',
            ),
            value: _marketingConsent,
            onChanged: _loadingMarketingConsent ? null : _setMarketingConsent,
          ),
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
