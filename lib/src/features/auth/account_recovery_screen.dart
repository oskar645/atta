import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/utils/ru_phone.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

enum _RecoveryStep { email, code, phone, call, done }

class AccountRecoveryScreen extends StatefulWidget {
  const AccountRecoveryScreen({super.key});
  @override
  State<AccountRecoveryScreen> createState() => _AccountRecoveryScreenState();
}

class _AccountRecoveryScreenState extends State<AccountRecoveryScreen> {
  final email = TextEditingController();
  final code = TextEditingController();
  final phone = TextEditingController();
  _RecoveryStep step = _RecoveryStep.email;
  String challengeId = '';
  String grant = '';
  String checkId = '';
  String callToPhone = '';
  String? error;
  bool busy = false;

  @override
  void dispose() {
    email.dispose();
    code.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> startEmail() => run(() async {
        final result =
            await context.read<AuthService>().startAccountRecovery(email.text);
        challengeId = result['challengeId']?.toString() ?? '';
        if (mounted) setState(() => step = _RecoveryStep.code);
      });

  Future<void> verifyEmail() => run(() async {
        final result = await context
            .read<AuthService>()
            .verifyAccountRecoveryEmail(challengeId, code.text);
        grant = result['recoveryToken']?.toString() ?? '';
        if (mounted) setState(() => step = _RecoveryStep.phone);
      });

  Future<void> startPhone() => run(() async {
        final normalized = normalizeRuPhoneForApi(phone.text);
        final result = await context
            .read<AuthService>()
            .startRecoveryPhone(grant, normalized);
        checkId = (result['verificationCheckId'] ??
                    result['checkId'] ??
                    result['verificationId'])
                ?.toString() ??
            '';
        callToPhone = (result['callToPhonePretty'] ?? result['callToPhone'])
                ?.toString() ??
            '';
        if (mounted) setState(() => step = _RecoveryStep.call);
      });

  Future<void> checkPhone() => run(() async {
        final result = await context.read<AuthService>().completeRecoveryPhone(
            grant, normalizeRuPhoneForApi(phone.text), checkId);
        if (result['auth'] is Map && mounted) {
          setState(() => step = _RecoveryStep.done);
        }
      });

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Восстановление доступа')),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(24),
                    children: [
                      if (step == _RecoveryStep.email) ...[
                        const Text(
                            'Введите резервный email, который вы ранее подтвердили в ATTA.',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 20),
                        TextField(
                            key: const ValueKey('account-recovery-email'),
                            controller: email,
                            keyboardType: TextInputType.emailAddress,
                            decoration:
                                const InputDecoration(labelText: 'Email')),
                        const SizedBox(height: 20),
                        FilledButton(
                            onPressed: busy ? null : startEmail,
                            child: const Text('Продолжить')),
                      ],
                      if (step == _RecoveryStep.code) ...[
                        const Text('Введите код из письма',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 20),
                        TextField(
                            controller: code,
                            onChanged: (_) => setState(() {}),
                            maxLength: 6,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            decoration:
                                const InputDecoration(labelText: 'Код')),
                        FilledButton(
                            onPressed: busy || code.text.length != 6
                                ? null
                                : verifyEmail,
                            child: const Text('Подтвердить')),
                      ],
                      if (step == _RecoveryStep.phone) ...[
                        const Text('Новый номер телефона',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 20),
                        TextField(
                            controller: phone,
                            keyboardType: TextInputType.phone,
                            inputFormatters: const [RuPhoneInputFormatter()],
                            decoration: const InputDecoration(
                                prefixText: '+7 ',
                                labelText: 'Номер телефона')),
                        const SizedBox(height: 20),
                        FilledButton(
                            onPressed: busy ? null : startPhone,
                            child: const Text('Продолжить')),
                      ],
                      if (step == _RecoveryStep.call) ...[
                        const Text(
                            'Позвоните на номер для подтверждения нового телефона',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        SelectableText(callToPhone,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 16),
                        FilledButton(
                            onPressed: () => launchUrl(
                                Uri(scheme: 'tel', path: callToPhone)),
                            child: const Text('Позвонить')),
                        TextButton(
                            onPressed: busy ? null : checkPhone,
                            child: const Text('Проверить подтверждение')),
                      ],
                      if (step == _RecoveryStep.done) ...[
                        const Icon(Icons.check_circle,
                            color: Colors.green, size: 56),
                        const SizedBox(height: 16),
                        const Text('Доступ восстановлен',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 20),
                        FilledButton(
                            onPressed: () => Navigator.of(context)
                                .popUntil((route) => route.isFirst),
                            child: const Text('Готово')),
                      ],
                      if (error != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(error!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error))),
                    ]))),
      );
}
