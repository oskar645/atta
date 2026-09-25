import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/utils/ru_phone.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'passwordless_controller.dart';
import 'registration_consents.dart';
import 'account_recovery_screen.dart';
import 'public_support_screen.dart';

class PasswordlessScreen extends StatefulWidget {
  const PasswordlessScreen({super.key, this.returnToPreviousAfterAuth = false});

  final bool returnToPreviousAfterAuth;

  @override
  State<PasswordlessScreen> createState() => _PasswordlessScreenState();
}

class _PasswordlessScreenState extends State<PasswordlessScreen> {
  final _phone = TextEditingController();
  final _name = TextEditingController();
  late final PasswordlessController _flow;
  bool _acceptedLegal = false;
  bool _acceptedPersonalData = false;
  bool _openingDialer = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _flow = PasswordlessController(context.read<AuthService>());
    _flow.addListener(_onChanged);
    _flow.restore();
  }

  void _onChanged() {
    if (!mounted) return;
    if (_flow.step == PasswordlessStep.signedIn && !_finished) {
      FocusScope.of(context).unfocus();
      _finished = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.returnToPreviousAfterAuth) {
          Navigator.of(context).pop(true);
        } else {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      });
    }
    setState(() {});
  }

  @override
  void dispose() {
    _flow.removeListener(_onChanged);
    _flow.dispose();
    _phone.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _call() async {
    if (_openingDialer) return;
    setState(() => _openingDialer = true);
    final digits = _flow.callToPhone.replaceAll(RegExp(r'\D'), '');
    try {
      if (digits.isNotEmpty) {
        final uri = Uri(scheme: 'tel', path: '+$digits');
        final opened = await launchUrl(uri);
        if (!opened) await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // Desktop browsers may not have a tel: handler. The displayed number
      // and independent polling still allow a call from another device.
    } finally {
      if (mounted) setState(() => _openingDialer = false);
    }
  }

  void _start() {
    FocusScope.of(context).unfocus();
    _flow.start(_phone.text);
  }

  void _changePhone() {
    FocusScope.of(context).unfocus();
    _acceptedLegal = false;
    _acceptedPersonalData = false;
    _flow.changePhone();
  }

  @override
  Widget build(BuildContext context) {
    final step = _flow.step;
    final title = switch (step) {
      PasswordlessStep.phone => 'Войдите по номеру телефона',
      PasswordlessStep.name => 'Как вас зовут?',
      PasswordlessStep.expired => 'Время подтверждения истекло',
      PasswordlessStep.blocked => 'Доступ для этого номера ограничен',
      _ => 'Подтвердите номер',
    };
    return PopScope(
      canPop: step == PasswordlessStep.phone || _finished,
      onPopInvokedWithResult: (didPop, result) {
        if (!_finished) _changePhone();
      },
      child: Scaffold(
        appBar: AppBar(),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(24),
                children: [
                  Image.asset('assets/branding/atta_logo.png',
                      height: 56, semanticLabel: 'ATTA'),
                  const SizedBox(height: 32),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 24),
                  if (step == PasswordlessStep.phone) ...[
                    TextField(
                      key: const ValueKey('passwordless-phone'),
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      autofillHints: const [
                        AutofillHints.telephoneNumberNational
                      ],
                      inputFormatters: const [RuPhoneInputFormatter()],
                      decoration: const InputDecoration(
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          prefix: Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Text('+7')),
                          labelText: 'Номер телефона'),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _start(),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _flow.canSubmit &&
                              normalizeRuPhoneForApi(_phone.text).isNotEmpty
                          ? _start
                          : null,
                      child: const Text('Продолжить'),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      runAlignment: WrapAlignment.center,
                      spacing: 12,
                      children: [
                        TextButton(
                          key: const ValueKey('account-recovery-link'),
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                  builder: (_) =>
                                      const AccountRecoveryScreen())),
                          child: const Text('Нет доступа к номеру?',
                              style: TextStyle(fontSize: 13)),
                        ),
                        TextButton(
                          key: const ValueKey('public-support-link'),
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                  builder: (_) => const PublicSupportScreen())),
                          child: const Text('Нужна помощь?',
                              style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ],
                  if (step == PasswordlessStep.call) ...[
                    Text(
                        'Позвоните с номера ${formatRussianPhone(_flow.phone)} на:',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    SelectableText(formatRussianPhone(_flow.callToPhone),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    Text(
                        '${_flow.secondsLeft ~/ 60}:${(_flow.secondsLeft % 60).toString().padLeft(2, '0')}',
                        key: const ValueKey('passwordless-countdown'),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    FilledButton(
                        onPressed: _openingDialer ? null : _call,
                        child: const Text('Позвонить')),
                  ],
                  if (step == PasswordlessStep.name) ...[
                    TextField(
                        controller: _name,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(100)
                        ],
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.givenName],
                        decoration:
                            const InputDecoration(labelText: 'Ваше имя'),
                        onChanged: (_) => setState(() {})),
                    const SizedBox(height: 20),
                    RegistrationConsents(
                      acceptedLegal: _acceptedLegal,
                      acceptedPersonalData: _acceptedPersonalData,
                      loading: _flow.busy,
                      onLegalChanged: (value) =>
                          setState(() => _acceptedLegal = value),
                      onPersonalDataChanged: (value) =>
                          setState(() => _acceptedPersonalData = value),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _flow.canSubmit &&
                              _name.text.trim().isNotEmpty &&
                              _acceptedLegal &&
                              _acceptedPersonalData
                          ? () {
                              FocusScope.of(context).unfocus();
                              _flow.complete(
                                  displayName: _name.text,
                                  acceptedLegal: _acceptedLegal,
                                  acceptedPersonalData: _acceptedPersonalData);
                            }
                          : null,
                      child: const Text('Готово'),
                    ),
                  ],
                  if (step == PasswordlessStep.expired)
                    FilledButton(
                        onPressed: _flow.canSubmit ? _start : null,
                        child: const Text('Попробовать снова')),
                  if (step != PasswordlessStep.phone &&
                      step != PasswordlessStep.signedIn)
                    TextButton(
                        onPressed: _changePhone,
                        child: const Text('Изменить номер')),
                  if (_flow.message != null && _flow.message != title) ...[
                    const SizedBox(height: 12),
                    Text(_flow.message!,
                        textAlign: TextAlign.center,
                        semanticsLabel: _flow.message),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
