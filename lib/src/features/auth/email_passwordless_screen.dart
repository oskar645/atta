import 'dart:async';

import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'registration_consents.dart';

enum _EmailStep { email, code, name }

class EmailPasswordlessScreen extends StatefulWidget {
  const EmailPasswordlessScreen({
    super.key,
    this.returnToPreviousAfterAuth = false,
  });

  final bool returnToPreviousAfterAuth;

  @override
  State<EmailPasswordlessScreen> createState() =>
      _EmailPasswordlessScreenState();
}

class _EmailPasswordlessScreenState extends State<EmailPasswordlessScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  _EmailStep _step = _EmailStep.email;
  String? _challengeId;
  String? _registrationToken;
  String _maskedEmail = '';
  String? _error;
  bool _busy = false;
  bool _acceptedLegal = false;
  bool _acceptedPersonalData = false;
  int _resendSeconds = 0;
  Timer? _timer;
  bool _finished = false;

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _validEmail =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim());

  void _startTimer(int seconds) {
    _timer?.cancel();
    setState(() => _resendSeconds = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendSeconds <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _start({bool resend = false}) async {
    if (_busy || !_validEmail) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await context
          .read<AuthService>()
          .startEmailPasswordless(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _challengeId = result['challengeId']?.toString();
        _maskedEmail = result['maskedEmail']?.toString() ?? _email.text.trim();
        _step = _EmailStep.code;
        if (!resend) _code.clear();
      });
      _startTimer((result['resendAfter'] as num?)?.toInt() ?? 60);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) {
        setState(() =>
            _error = context.read<AuthService>().userMessageForError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    final challengeId = _challengeId;
    if (_busy || challengeId == null || _code.text.length != 6) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await context.read<AuthService>().checkEmailPasswordless(
            challengeId: challengeId,
            code: _code.text,
            isActive: () => mounted && !_finished,
          );
      if (!mounted) return;
      if (context.read<AuthService>().isAuthenticated) {
        _finish();
        return;
      }
      final token = result['registrationToken']?.toString() ?? '';
      if (result['status'] == 'registration_required' && token.isNotEmpty) {
        setState(() {
          _registrationToken = token;
          _step = _EmailStep.name;
        });
      } else {
        setState(
            () => _error = 'Не удалось подтвердить email. Попробуйте снова.');
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) {
        setState(() =>
            _error = context.read<AuthService>().userMessageForError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _complete() async {
    final token = _registrationToken;
    if (_busy ||
        token == null ||
        _name.text.trim().isEmpty ||
        !_acceptedLegal ||
        !_acceptedPersonalData) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().completeEmailPasswordless(
            registrationToken: token,
            displayName: _name.text,
            acceptedLegal: _acceptedLegal,
            acceptedPersonalData: _acceptedPersonalData,
            isActive: () => mounted && !_finished,
          );
      if (mounted && context.read<AuthService>().isAuthenticated) _finish();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) {
        setState(() =>
            _error = context.read<AuthService>().userMessageForError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _finish() {
    if (_finished) return;
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

  void _changeEmail() {
    if (_busy) return;
    _timer?.cancel();
    setState(() {
      _step = _EmailStep.email;
      _challengeId = null;
      _registrationToken = null;
      _code.clear();
      _error = null;
      _resendSeconds = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_step) {
      _EmailStep.email => 'Войти по почте',
      _EmailStep.code => 'Введите код из письма',
      _EmailStep.name => 'Как вас зовут?',
    };
    return PopScope(
      canPop: _step == _EmailStep.email || _finished,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_finished) _changeEmail();
      },
      child: Scaffold(
        appBar: AppBar(),
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(24),
                  children: [
                    Image.asset('assets/branding/atta_logo.png',
                        height: 56, semanticLabel: 'ATTA'),
                    const SizedBox(height: 28),
                    Text(title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall),
                    if (_step == _EmailStep.email) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Укажите адрес электронной почты, пришлём код для входа.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 20),
                    ] else
                      const SizedBox(height: 24),
                    if (_step == _EmailStep.email) ...[
                      TextField(
                        key: const ValueKey('email-passwordless-email'),
                        controller: _email,
                        autofocus: true,
                        enabled: !_busy,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.email],
                        autocorrect: false,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _start(),
                        decoration: const InputDecoration(
                          labelText: 'Электронная почта',
                          hintText: 'example@mail.ru',
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        key: const ValueKey('email-passwordless-start'),
                        onPressed: _busy || !_validEmail ? null : _start,
                        child: Text(_busy ? 'Отправляем...' : 'Получить код'),
                      ),
                    ],
                    if (_step == _EmailStep.code) ...[
                      Text('Код отправлен на $_maskedEmail',
                          textAlign: TextAlign.center),
                      const SizedBox(height: 18),
                      TextField(
                        key: const ValueKey('email-passwordless-code'),
                        controller: _code,
                        autofocus: true,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 24,
                            letterSpacing: 8,
                            fontWeight: FontWeight.w700),
                        onChanged: (value) {
                          setState(() {});
                          if (value.length == 6) _check();
                        },
                        onSubmitted: (_) => _check(),
                        decoration: const InputDecoration(
                            labelText: 'Шестизначный код', counterText: ''),
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        key: const ValueKey('email-passwordless-check'),
                        onPressed:
                            _busy || _code.text.length != 6 ? null : _check,
                        child: Text(_busy ? 'Проверяем...' : 'Продолжить'),
                      ),
                      TextButton(
                        onPressed: _busy || _resendSeconds > 0
                            ? null
                            : () => _start(resend: true),
                        child: Text(_resendSeconds > 0
                            ? 'Отправить снова через $_resendSeconds сек.'
                            : 'Отправить код ещё раз'),
                      ),
                      TextButton(
                          onPressed: _busy ? null : _changeEmail,
                          child: const Text('Изменить email')),
                    ],
                    if (_step == _EmailStep.name) ...[
                      TextField(
                        key: const ValueKey('email-passwordless-name'),
                        controller: _name,
                        autofocus: true,
                        enabled: !_busy,
                        maxLength: 100,
                        keyboardType: TextInputType.name,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.givenName],
                        onChanged: (_) => setState(() {}),
                        decoration:
                            const InputDecoration(labelText: 'Ваше имя'),
                      ),
                      const SizedBox(height: 12),
                      RegistrationConsents(
                        acceptedLegal: _acceptedLegal,
                        acceptedPersonalData: _acceptedPersonalData,
                        loading: _busy,
                        onLegalChanged: (value) =>
                            setState(() => _acceptedLegal = value),
                        onPersonalDataChanged: (value) =>
                            setState(() => _acceptedPersonalData = value),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        key: const ValueKey('email-passwordless-complete'),
                        onPressed: _busy ||
                                _name.text.trim().isEmpty ||
                                !_acceptedLegal ||
                                !_acceptedPersonalData
                            ? null
                            : _complete,
                        child: Text(_busy ? 'Создаём аккаунт...' : 'Готово'),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
