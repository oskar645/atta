import 'dart:async';

import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/backend_auth_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/utils/ru_phone.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  String _visibleEmail(String? value) {
    final email = (value ?? '').trim();
    return email.endsWith('@phone.atta.local') ? '' : email;
  }

  String _maskedEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2 || parts.first.isEmpty) return email;
    return '${parts.first[0]}***@${parts.last}';
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser!;
    final email = _visibleEmail(user.email);
    return Scaffold(
      appBar: AppBar(title: const Text('Безопасность')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Телефон',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          formatRussianPhone(user.phone ?? ''),
          style: const TextStyle(fontSize: 18),
        ),
        const SizedBox(height: 4),
        Text(user.phoneVerified ? 'Подтверждён ✓' : 'Не подтверждён',
            style: TextStyle(
                color: user.phoneVerified
                    ? Colors.green.shade700
                    : Theme.of(context).colorScheme.error)),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('change-phone'),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ChangePhoneScreen(),
                ),
              );
              if (mounted) setState(() {});
            },
            child: const Text('Изменить'),
          ),
        ),
        const SizedBox(height: 28),
        const Text('Резервный email',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (email.isNotEmpty) ...[
          Text(_maskedEmail(email), style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          Text(
            user.emailVerified ? 'Подтверждён ✓' : 'Не подтверждён',
            style: TextStyle(
              color: user.emailVerified
                  ? Colors.green.shade700
                  : Theme.of(context).colorScheme.error,
            ),
          ),
        ] else
          Text('Не добавлен',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 16),
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
                key: const ValueKey('add-recovery-email'),
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => const RecoveryEmailScreen()));
                  if (mounted) setState(() {});
                },
                child: Text(email.isEmpty ? 'Добавить' : 'Изменить'))),
      ]),
    );
  }
}

class ChangePhoneScreen extends StatefulWidget {
  const ChangePhoneScreen({super.key});

  @override
  State<ChangePhoneScreen> createState() => _ChangePhoneScreenState();
}

class _ChangePhoneScreenState extends State<ChangePhoneScreen> {
  final _phone = TextEditingController();
  PhoneVerificationStartResult? _verification;
  bool _busy = false;
  String? _status;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  String _friendlyError(Object error) {
    if (error is ApiException) {
      final text = '${error.code ?? ''} ${error.message}'.toLowerCase();
      if (text.contains('already') ||
          text.contains('exists') ||
          text.contains('occupied') ||
          text.contains('taken') ||
          text.contains('занят')) {
        return 'Этот номер уже привязан к другому аккаунту.';
      }
      if (error.isNetworkError || error.isTimeout) {
        return 'Не удалось подключиться к серверу. Проверьте интернет.';
      }
      if (error.message.trim().isNotEmpty) return error.message.trim();
    }
    return context.read<AuthService>().userMessageForError(error);
  }

  Future<void> _start() async {
    final phone = normalizeRuPhoneForApi(_phone.text);
    if (phone.isEmpty) {
      setState(() => _error = 'Введите номер телефона полностью');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final result = await context.read<AuthService>().startPhoneVerification(
            phone: phone,
            purpose: 'change_phone',
          );
      if (!mounted) return;
      if (result.verificationId.isEmpty || !result.hasCallToPhone) {
        throw const ApiException(
          'Подтверждение телефона временно недоступно.',
        );
      }
      setState(() => _verification = result);
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _call() async {
    final number = (_verification?.callToPhone ?? '').replaceAll(
      RegExp(r'[^\d+]'),
      '',
    );
    if (number.isEmpty) return;
    final opened = await launchUrl(
      Uri.parse('tel:$number'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      setState(() =>
          _error = 'Не удалось открыть звонилку. Наберите номер вручную.');
    }
  }

  Future<void> _check() async {
    final verification = _verification;
    final phone = normalizeRuPhoneForApi(_phone.text);
    if (verification == null || phone.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Проверяем звонок...';
    });
    try {
      final check = await context.read<AuthService>().checkPhoneVerification(
            phone: phone,
            verificationId: verification.verificationId,
            purpose: 'change_phone',
          );
      if (!mounted) return;
      if (check.isPending) {
        setState(
            () => _status = 'Звонок ещё не подтверждён. Попробуйте ещё раз.');
        return;
      }
      if (!check.isConfirmed) {
        setState(() {
          _status = null;
          _error = check.isExpired
              ? 'Время подтверждения истекло. Запустите проверку заново.'
              : 'Не удалось подтвердить звонок. Попробуйте ещё раз.';
          if (check.isExpired) _verification = null;
        });
        return;
      }

      final auth = context.read<AuthService>();
      final profile = context.read<ProfileService>();
      final user = auth.currentUser!;
      final updated = await profile.updateProfile(user.uid, {
        'phone': phone,
        'verificationCheckId': verification.verificationId,
      });
      await auth.syncCurrentUserFromProfile(user.uid, updated);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = null;
          _error = _friendlyError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final verification = _verification;
    return Scaffold(
      appBar: AppBar(title: const Text('Изменить телефон')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (verification == null) ...[
            TextField(
              key: const ValueKey('new-phone'),
              controller: _phone,
              enabled: !_busy,
              autofocus: true,
              keyboardType: TextInputType.phone,
              inputFormatters: const [RuPhoneInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Новый номер',
                prefixText: '+7 ',
                hintText: '999 123-45-67',
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const ValueKey('start-phone-change'),
              onPressed: _busy ? null : _start,
              child: Text(_busy ? 'Запускаем...' : 'Подтвердить номер'),
            ),
          ] else ...[
            const Text(
              'Позвоните с нового номера на указанный ниже. Звонок будет сброшен автоматически.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              verification.callToPhonePretty.isNotEmpty
                  ? verification.callToPhonePretty
                  : verification.callToPhone,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              key: const ValueKey('call-check-phone'),
              onPressed: _busy ? null : _call,
              icon: const Icon(Icons.phone_outlined),
              label: const Text('Позвонить'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('check-phone-change'),
              onPressed: _busy ? null : _check,
              child: Text(_busy ? 'Проверяем...' : 'Я подтвердил звонок'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _verification = null;
                        _status = null;
                        _error = null;
                      }),
              child: const Text('Изменить номер'),
            ),
          ],
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_status!, textAlign: TextAlign.center),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

class RecoveryEmailScreen extends StatefulWidget {
  const RecoveryEmailScreen({super.key});
  @override
  State<RecoveryEmailScreen> createState() => _RecoveryEmailScreenState();
}

class _RecoveryEmailScreenState extends State<RecoveryEmailScreen> {
  final email = TextEditingController();
  final code = TextEditingController();
  String? challengeId;
  String? masked;
  String? error;
  bool busy = false;
  int cooldown = 0;
  Timer? timer;

  @override
  void dispose() {
    timer?.cancel();
    email.dispose();
    code.dispose();
    super.dispose();
  }

  void startCooldown(int value) {
    timer?.cancel();
    setState(() => cooldown = value);
    timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || cooldown <= 1) {
        timer.cancel();
        if (mounted) setState(() => cooldown = 0);
      } else {
        setState(() => cooldown--);
      }
    });
  }

  Future<void> send() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result =
          await context.read<AuthService>().startRecoveryEmail(email.text);
      if (!mounted) return;
      setState(() {
        challengeId = result['challengeId']?.toString();
        masked = result['maskedEmail']?.toString();
      });
      startCooldown((result['resendAfter'] as num?)?.toInt() ?? 60);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> verify() async {
    if (busy || challengeId == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await context
          .read<AuthService>()
          .verifyRecoveryEmail(challengeId!, code.text);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Резервный email')),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          if (challengeId == null) ...[
            TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                    labelText: 'Email', hintText: 'example@gmail.com')),
            const SizedBox(height: 20),
            FilledButton(
                onPressed: busy ? null : send,
                child: const Text('Получить код')),
          ] else ...[
            Text('Мы отправили код на ${masked ?? ''}',
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            TextField(
                key: const ValueKey('recovery-email-code'),
                controller: code,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Код из письма')),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: busy || code.text.length != 6 ? null : verify,
                child: const Text('Подтвердить')),
            TextButton(
                onPressed: busy || cooldown > 0 ? null : send,
                child: Text(cooldown > 0
                    ? 'Отправить снова через $cooldown сек.'
                    : 'Отправить код ещё раз')),
          ],
          if (error != null)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(error!,
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
        ]),
      );
}
