import 'dart:async';

import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class SecurityScreen extends StatelessWidget {
  const SecurityScreen({super.key});

  String _maskedPhone(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length != 11) return '+7 *** *** ** **';
    return '+7 *** *** ** ${digits.substring(9)}';
  }

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
        const Text('Номер телефона',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(_maskedPhone(user.phone), style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 4),
        Text(user.phoneVerified ? 'Подтверждён ✓' : 'Не подтверждён',
            style: TextStyle(
                color: user.phoneVerified
                    ? Colors.green.shade700
                    : Theme.of(context).colorScheme.error)),
        const SizedBox(height: 28),
        const Text('Резервный email',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (email.isNotEmpty && user.emailVerified) ...[
          Text(_maskedEmail(email), style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          Text('Подтверждён ✓', style: TextStyle(color: Colors.green.shade700)),
        ] else
          Text(email.isEmpty ? 'Не подключён' : 'Не подтверждён',
              style: TextStyle(
                  fontSize: 18, color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 16),
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
                key: const ValueKey('add-recovery-email'),
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const RecoveryEmailScreen())),
                child: Text(email.isEmpty ? 'Добавить' : 'Изменить'))),
      ]),
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
