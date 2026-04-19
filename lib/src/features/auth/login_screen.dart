import 'dart:async';

import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/services/callcheck_service.dart';
import 'package:atta/src/services/phone_auth_backend_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'privacy_screen.dart';
import 'terms_screen.dart';
import 'verify_email_screen.dart';

enum _AuthMethod { phone, email }

const int _minPhonePasswordDigits = 8;

bool _isPhonePasswordValid(String value) {
  final trimmed = value.trim();
  return trimmed.length >= _minPhonePasswordDigits &&
      RegExp(r'^\d+$').hasMatch(trimmed);
}

String _phonePasswordErrorText(String value) {
  if (value.trim().isEmpty) {
    return 'Введите пароль';
  }
  return 'Введите не менее 8 цифр';
}

class _PhoneRegistrationDraft {
  final String displayName;
  final String password;
  final String phone;
  final bool acceptedOffer;
  final bool phoneVerified;

  const _PhoneRegistrationDraft({
    required this.displayName,
    required this.password,
    required this.phone,
    required this.acceptedOffer,
    this.phoneVerified = false,
  });

  _PhoneRegistrationDraft copyWith({
    String? displayName,
    String? password,
    String? phone,
    bool? acceptedOffer,
    bool? phoneVerified,
  }) {
    return _PhoneRegistrationDraft(
      displayName: displayName ?? this.displayName,
      password: password ?? this.password,
      phone: phone ?? this.phone,
      acceptedOffer: acceptedOffer ?? this.acceptedOffer,
      phoneVerified: phoneVerified ?? this.phoneVerified,
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _loginCtrl = TextEditingController();
  final _phoneDigitsCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _isLogin = true;
  bool _loading = false;
  bool _hasAcceptedLegal = false;
  _AuthMethod _authMethod = _AuthMethod.phone;

  SupabaseClient get _sb => Supabase.instance.client;
  final PhoneAuthBackendService _phoneAuth = PhoneAuthBackendService();
  bool get _canContinuePhoneRegistrationFromTab =>
      !_loading &&
      _nameCtrl.text.trim().isNotEmpty &&
      _isPhonePasswordValid(_passCtrl.text) &&
      _hasAcceptedLegal;

  @override
  void dispose() {
    _loginCtrl.dispose();
    _phoneDigitsCtrl.dispose();
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _normalizeRuPhone(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';

    String localDigits = digits;
    if (localDigits.length == 11 &&
        (localDigits.startsWith('7') || localDigits.startsWith('8'))) {
      localDigits = localDigits.substring(1);
    }

    if (localDigits.length != 10) return '';
    return '+7$localDigits';
  }

  bool _isValidRuPhone(String input) => _normalizeRuPhone(input).isNotEmpty;

  bool _looksLikePhone(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return false;
    return RegExp(r'^[\d+\s()\-]+$').hasMatch(trimmed);
  }

  String _niceAuthError(AuthException e, {bool? isPhoneContext}) {
    final msg = e.message.toLowerCase();
    final phoneContext = isPhoneContext ?? (_authMethod == _AuthMethod.phone);

    if (msg.contains('email rate limit exceeded')) {
      return 'Слишком часто отправляли письма. Подождите немного и попробуйте снова.';
    }
    if (msg.contains('phone rate limit exceeded')) {
      return 'Слишком много попыток подтверждения телефона. Подождите немного и попробуйте снова.';
    }
    if (msg.contains('invalid login credentials')) {
      return phoneContext
          ? 'Неверный номер телефона или пароль.'
          : 'Неверный email или пароль.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Email не подтвержден. Откройте письмо и подтвердите адрес.';
    }
    if (msg.contains('phone not confirmed')) {
      return 'Телефон еще не подтвержден. Завершите подтверждение и попробуйте снова.';
    }
    if (msg.contains('user already registered')) {
      return phoneContext
          ? 'Этот номер уже зарегистрирован. Попробуйте войти.'
          : 'Этот email уже зарегистрирован. Попробуйте войти.';
    }
    if (msg.contains('sms provider is not configured') ||
        msg.contains('twilio')) {
      return 'Телефонный сценарий уже подготовлен, но сервис подтверждения телефона пока не подключен.';
    }
    if (msg.contains('phone signups are disabled')) {
      return 'Телефонная регистрация теперь идёт через backend. Проверьте, что функция phone-auth загружена в Supabase.';
    }
    return e.message;
  }

  Future<void> _resetPassword() async {
    final loginValue = _loginCtrl.text.trim();

    if (loginValue.isEmpty) {
      _snack('Введите телефон или email для восстановления пароля');
      return;
    }

    if (_looksLikePhone(loginValue)) {
      final phone = _normalizeRuPhone(loginValue);
      if (phone.isEmpty) {
        _snack('Введите корректный номер телефона');
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _PhoneVerificationScreen(
            phone: phone,
            callcheckService: CallcheckService(),
            onConfirmed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _PhonePasswordResetScreen(
                    phone: phone,
                    phoneAuth: _phoneAuth,
                  ),
                ),
              );
            },
          ),
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await _sb.auth.resetPasswordForEmail(
        loginValue,
        redirectTo: kIsWeb ? null : 'io.supabase.flutter://reset-callback/',
      );
      _snack('Письмо для смены пароля отправлено на почту');
    } on AuthException catch (e) {
      _snack(_niceAuthError(e, isPhoneContext: false));
    } catch (e) {
      _snack('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitLogin() async {
    final loginValue = _loginCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    if (loginValue.isEmpty || pass.isEmpty) {
      _snack('Введите телефон или email и пароль');
      return;
    }

    final isPhoneLogin = _looksLikePhone(loginValue);
    if (isPhoneLogin && !_isValidRuPhone(loginValue)) {
      _snack('Введите корректный номер телефона');
      return;
    }

    setState(() => _loading = true);
    try {
      AuthResponse? emailAuthResponse;
      if (!isPhoneLogin) {
        emailAuthResponse = await _sb.auth.signInWithPassword(
          email: loginValue,
          password: pass,
        );
      }

      if (isPhoneLogin) {
        await _phoneAuth.signInWithPhone(
          phone: _normalizeRuPhone(loginValue),
          password: pass,
        );
      } else if (emailAuthResponse?.session == null) {
        throw const AuthException(
          'Не удалось войти. Подтвердите email и попробуйте снова.',
        );
      }
    } on AuthException catch (e) {
      _snack(_niceAuthError(e, isPhoneContext: isPhoneLogin));
    } catch (e) {
      _snack('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openPhoneRegistrationFlow() async {
    if (!_canContinuePhoneRegistrationFromTab) return;
    debugPrint(
      'Phone registration start: nameLen=${_nameCtrl.text.trim().length}, passLen=${_passCtrl.text.trim().length}, accepted=$_hasAcceptedLegal',
    );

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PhoneRegistrationPhoneScreen(
          draft: _PhoneRegistrationDraft(
            displayName: _nameCtrl.text.trim(),
            password: _passCtrl.text.trim(),
            phone: '',
            acceptedOffer: _hasAcceptedLegal,
          ),
          phoneAuth: _phoneAuth,
          callcheckService: CallcheckService(),
        ),
      ),
    );
  }

  Future<void> _submitEmailRegistration() async {
    final phone = _normalizeRuPhone(_phoneDigitsCtrl.text);
    final email = _emailCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    if (name.isEmpty) {
      _snack('Введите имя');
      return;
    }
    if (phone.isEmpty) {
      _snack('Введите номер телефона');
      return;
    }
    if (email.isEmpty || pass.isEmpty) {
      _snack('Введите email и пароль');
      return;
    }
    if (!_hasAcceptedLegal) {
      _snack(
          'Примите Пользовательское соглашение и Политику конфиденциальности');
      return;
    }

    setState(() => _loading = true);
    try {
      await _sb.auth.signUp(
        email: email,
        password: pass,
        data: {
          'name': name,
          'displayName': name,
          'phone': phone,
          'acceptedTerms': _hasAcceptedLegal,
          'acceptedPrivacyPolicy': _hasAcceptedLegal,
          'registrationMethod': 'email',
        },
      );

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VerifyEmailScreen(
            email: email,
            password: pass,
            name: name,
            phone: phone,
          ),
        ),
      );
    } on AuthException catch (e) {
      _snack(_niceAuthError(e, isPhoneContext: false));
    } catch (e) {
      _snack('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleMode() {
    setState(() {
      _isLogin = !_isLogin;
      _loading = false;
      _hasAcceptedLegal = false;
      _authMethod = _AuthMethod.phone;
      _passCtrl.clear();
      if (_isLogin) {
        _phoneDigitsCtrl.clear();
        _emailCtrl.clear();
        _nameCtrl.clear();
      }
    });
  }

  void _openTerms() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TermsScreen()),
    );
  }

  void _openPrivacy() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PrivacyScreen()),
    );
  }

  Widget _buildWelcomeCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.secondaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Добро пожаловать',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isLogin
                ? 'Войдите по телефону или email.'
                : (_authMethod == _AuthMethod.phone
                    ? 'Регистрация по телефону в 3 шага: профиль, номер и подтверждение звонком.'
                    : 'Создайте аккаунт по email и сохраните телефон в профиле.'),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodSwitch(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _authMethod == _AuthMethod.phone
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                foregroundColor: _authMethod == _AuthMethod.phone
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
                elevation: 0,
              ),
              onPressed: _loading
                  ? null
                  : () => setState(() => _authMethod = _AuthMethod.phone),
              child: const Text('С телефона'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _authMethod == _AuthMethod.email
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                foregroundColor: _authMethod == _AuthMethod.email
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
                elevation: 0,
              ),
              onPressed: _loading
                  ? null
                  : () => setState(() => _authMethod = _AuthMethod.email),
              child: const Text('С email'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegalBlock(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _hasAcceptedLegal,
              onChanged: _loading
                  ? null
                  : (value) {
                      setState(() {
                        _hasAcceptedLegal = value ?? false;
                      });
                    },
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: RichText(
                  text: TextSpan(
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      height: 1.5,
                    ),
                    children: [
                      const TextSpan(text: 'Я принимаю '),
                      TextSpan(
                        text: 'Пользовательское соглашение',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                        recognizer: TapGestureRecognizer()..onTap = _openTerms,
                      ),
                      const TextSpan(text: ' и '),
                      TextSpan(
                        text: 'Политику конфиденциальности',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = _openPrivacy,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhonePrefixField() {
    return TextField(
      controller: _phoneDigitsCtrl,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      onChanged: (_) => setState(() {}),
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
      ],
      decoration: const InputDecoration(
        prefixText: '+7 ',
        labelText: 'Номер телефона',
        hintText: '9001234567',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isLogin ? 'Вход' : 'Регистрация'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildWelcomeCard(theme),
          const SizedBox(height: 16),
          if (!_isLogin) ...[
            _buildMethodSwitch(theme),
            const SizedBox(height: 16),
          ],
          if (_isLogin) ...[
            TextField(
              controller: _loginCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Телефон или email',
                hintText: '+7 9001234567 или example@mail.com',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              obscureText: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Пароль'),
              onSubmitted: (_) {
                if (!_loading) {
                  _submitLogin();
                }
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _loading ? null : _resetPassword,
                child: const Text('Забыли пароль?'),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _loading ? null : _submitLogin,
              child: Text(_loading ? 'Подождите...' : 'Войти'),
            ),
          ] else if (_authMethod == _AuthMethod.phone) ...[
            TextField(
              controller: _nameCtrl,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Имя пользователя'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Пароль',
                helperText: 'Введите не менее 8 цифр',
              ),
            ),
            const SizedBox(height: 16),
            _buildLegalBlock(theme),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _canContinuePhoneRegistrationFromTab
                  ? _openPhoneRegistrationFlow
                  : null,
              child: const Text('Продолжить'),
            ),
          ] else ...[
            TextField(
              controller: _nameCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Имя'),
            ),
            const SizedBox(height: 12),
            _buildPhonePrefixField(),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              obscureText: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Пароль'),
              onSubmitted: (_) {
                if (!_loading) {
                  _submitEmailRegistration();
                }
              },
            ),
            const SizedBox(height: 16),
            _buildLegalBlock(theme),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : _submitEmailRegistration,
              child: Text(_loading ? 'Подождите...' : 'Зарегистрироваться'),
            ),
          ],
          const SizedBox(height: 10),
          TextButton(
            onPressed: _loading ? null : _toggleMode,
            child: Text(
              _isLogin
                  ? 'Нет аккаунта? Создать аккаунт'
                  : 'Уже есть аккаунт? Войти',
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneRegistrationCredentialsScreen extends StatefulWidget {
  final PhoneAuthBackendService phoneAuth;
  final CallcheckService callcheckService;

  const _PhoneRegistrationCredentialsScreen({
    required this.phoneAuth,
    required this.callcheckService,
  });

  @override
  State<_PhoneRegistrationCredentialsScreen> createState() =>
      _PhoneRegistrationCredentialsScreenState();
}

class _PhoneRegistrationCredentialsScreenState
    extends State<_PhoneRegistrationCredentialsScreen> {
  final _nameCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _acceptedOffer = false;
  bool _submitted = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  bool get _isNameValid => _nameCtrl.text.trim().isNotEmpty;
  bool get _isPasswordValid => _isPhonePasswordValid(_passCtrl.text);
  bool get _canContinue => _isNameValid && _isPasswordValid && _acceptedOffer;

  Future<void> _continue() async {
    setState(() => _submitted = true);
    if (!_canContinue) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PhoneRegistrationPhoneScreen(
          draft: _PhoneRegistrationDraft(
            displayName: _nameCtrl.text.trim(),
            password: _passCtrl.text.trim(),
            phone: '',
            acceptedOffer: _acceptedOffer,
          ),
          phoneAuth: widget.phoneAuth,
          callcheckService: widget.callcheckService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nameInvalid = _submitted && !_isNameValid;
    final passInvalid = _submitted && !_isPasswordValid;
    final offerInvalid = _submitted && !_acceptedOffer;

    return Scaffold(
      appBar: AppBar(title: const Text('Регистрация по телефону')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Имя пользователя',
              errorText: nameInvalid ? 'Введите имя пользователя' : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            obscureText: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _continue(),
            onChanged: (_) => setState(() {}),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Пароль',
              helperText: 'Введите не менее 8 цифр',
              errorText:
                  passInvalid ? _phonePasswordErrorText(_passCtrl.text) : null,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: offerInvalid
                    ? theme.colorScheme.error
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _acceptedOffer,
                    onChanged: (value) {
                      setState(() {
                        _acceptedOffer = value ?? false;
                      });
                    },
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'Я принимаю условия оферты',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (offerInvalid) ...[
            const SizedBox(height: 8),
            Text(
              'Для продолжения подтвердите согласие с офертой',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _canContinue ? _continue : null,
            child: const Text('Продолжить'),
          ),
        ],
      ),
    );
  }
}

class _PhoneRegistrationPhoneScreen extends StatefulWidget {
  final _PhoneRegistrationDraft draft;
  final PhoneAuthBackendService phoneAuth;
  final CallcheckService callcheckService;

  const _PhoneRegistrationPhoneScreen({
    required this.draft,
    required this.phoneAuth,
    required this.callcheckService,
  });

  @override
  State<_PhoneRegistrationPhoneScreen> createState() =>
      _PhoneRegistrationPhoneScreenState();
}

class _PhoneRegistrationPhoneScreenState
    extends State<_PhoneRegistrationPhoneScreen> {
  final _phoneCtrl = TextEditingController();
  bool _loading = false;
  bool _submitted = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  String _normalizeRuPhone(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';

    String localDigits = digits;
    if (localDigits.length == 11 &&
        (localDigits.startsWith('7') || localDigits.startsWith('8'))) {
      localDigits = localDigits.substring(1);
    }

    if (localDigits.length != 10) return '';
    return '+7$localDigits';
  }

  bool get _isPhoneValid => _normalizeRuPhone(_phoneCtrl.text).isNotEmpty;

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _continue() async {
    setState(() => _submitted = true);
    if (!_isPhoneValid || _loading) return;

    final phone = _normalizeRuPhone(_phoneCtrl.text);
    debugPrint(
      'Phone registration phone step: nameLen=${widget.draft.displayName.trim().length}, passLen=${widget.draft.password.trim().length}, phone=$phone',
    );
    setState(() => _loading = true);
    try {
      final alreadyRegistered =
          await widget.phoneAuth.isPhoneRegistered(phone: phone);
      if (alreadyRegistered) {
        _snack('Этот номер уже зарегистрирован. Попробуйте войти.');
        return;
      }

      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _PhoneRegistrationConfirmScreen(
            draft: widget.draft.copyWith(phone: phone),
            phoneAuth: widget.phoneAuth,
            callcheckService: widget.callcheckService,
          ),
        ),
      );
    } catch (e) {
      _snack(widget.phoneAuth.userMessageForError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phoneInvalid = _submitted && !_isPhoneValid;

    return Scaffold(
      appBar: AppBar(title: const Text('Введите номер телефона')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _continue(),
            onChanged: (_) => setState(() {}),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(11),
            ],
            decoration: InputDecoration(
              prefixText: '+7 ',
              labelText: 'Номер телефона',
              hintText: '9001234567',
              errorText:
                  phoneInvalid ? 'Введите корректный номер телефона' : null,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: (!_loading && _isPhoneValid) ? _continue : null,
            child: Text(
              _loading ? 'Проверяем...' : 'Подтвердить номер телефона',
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneRegistrationConfirmScreen extends StatefulWidget {
  final _PhoneRegistrationDraft draft;
  final PhoneAuthBackendService phoneAuth;
  final CallcheckService callcheckService;

  const _PhoneRegistrationConfirmScreen({
    required this.draft,
    required this.phoneAuth,
    required this.callcheckService,
  });

  @override
  State<_PhoneRegistrationConfirmScreen> createState() =>
      _PhoneRegistrationConfirmScreenState();
}

class _PhoneRegistrationConfirmScreenState
    extends State<_PhoneRegistrationConfirmScreen> with WidgetsBindingObserver {
  bool _starting = true;
  bool _confirming = false;
  bool _movingForward = false;
  bool _callStarted = false;
  String? _errorText;
  String? _statusText;
  String? _checkId;
  String? _callPhone;
  String? _callPhonePretty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startVerification();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _callStarted &&
        !_movingForward &&
        !_starting &&
        !_confirming &&
        _errorText == null) {
      _pollAndFinish(showPendingSnack: false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _friendlyError(Object error) {
    final message = widget.phoneAuth.userMessageForError(error);
    final technical = error is PhoneAuthBackendException
        ? error.technicalDetails
        : error.toString();
    debugPrint('Phone registration flow error: $technical');
    return message;
  }

  bool _isTransientNetworkError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('failed host lookup') ||
        text.contains('socketexception') ||
        text.contains('clientexception');
  }

  Future<void> _startVerification() async {
    setState(() {
      _starting = true;
      _errorText = null;
      _statusText = null;
    });
    debugPrint(
      'Phone registration confirm step opened: nameLen=${widget.draft.displayName.trim().length}, passLen=${widget.draft.password.trim().length}, phone=${widget.draft.phone}',
    );

    try {
      final result = await widget.callcheckService.startVerification(
        phone: widget.draft.phone,
      );
      if (!mounted) return;
      setState(() {
        _checkId = result.checkId;
        _callPhone = result.callPhone;
        _callPhonePretty = result.callPhonePretty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = _friendlyError(e);
      });
    } finally {
      if (mounted) {
        setState(() => _starting = false);
      }
    }
  }

  String _normalizeDialablePhone(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    final hasPlus = trimmed.startsWith('+');
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    return hasPlus ? '+$digits' : digits;
  }

  Future<bool> _launchCall() async {
    final number = _normalizeDialablePhone((_callPhone ?? '').trim());
    if (number.isEmpty) return false;

    final uri = Uri.parse('tel:$number');
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        _snack('Не удалось открыть звонилку. Номер: $number');
      }
      return opened;
    } catch (_) {
      _snack('Не удалось открыть звонилку. Номер: $number');
      return false;
    }
  }

  Future<void> _pollAndFinish({bool showPendingSnack = true}) async {
    final checkId = _checkId;
    if (checkId == null || checkId.isEmpty || _confirming) return;

    setState(() {
      _confirming = true;
      _statusText = 'Ожидаем подтверждение звонка...';
    });

    try {
      for (var i = 0; i < 30; i++) {
        CallcheckStatusResult result;
        try {
          result = await widget.callcheckService.checkStatus(checkId: checkId);
        } catch (e) {
          if (_isTransientNetworkError(e) && i < 29) {
            if (!mounted) return;
            setState(() {
              _statusText = 'Проверяем соединение и подтверждение номера...';
            });
            await Future<void>.delayed(const Duration(seconds: 2));
            continue;
          }
          rethrow;
        }
        if (!mounted) return;

        if (result.isConfirmed) {
          await _finishRegistration();
          return;
        }

        if (i < 29) {
          await Future<void>.delayed(const Duration(seconds: 2));
        } else {
          final text = result.checkStatusText.trim().isEmpty
              ? 'Номер пока не подтвержден'
              : result.checkStatusText.trim();
          setState(() => _statusText = text);
          if (showPendingSnack) {
            _snack(text);
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      if (_isTransientNetworkError(e)) {
        setState(() {
          _statusText =
              'Нет соединения с сервером. Как только интернет появится, проверка продолжится.';
        });
        if (showPendingSnack) {
          _snack('Нет соединения с сервером. Проверьте интернет и попробуйте еще раз.');
        }
        return;
      }
      _snack(_friendlyError(e));
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _finishRegistration() async {
    if (_movingForward) return;
    debugPrint(
      'Phone registration finish requested: nameLen=${widget.draft.displayName.trim().length}, passLen=${widget.draft.password.trim().length}, callStarted=$_callStarted',
    );
    if (widget.draft.password.trim().isEmpty) {
      _snack('Пароль не сохранился. Вернитесь назад и введите его снова.');
      return;
    }
    if (!_isPhonePasswordValid(widget.draft.password)) {
      _snack('Введите не менее 8 цифр.');
      return;
    }
    if (widget.draft.displayName.trim().isEmpty) {
      _snack('Имя не сохранилось. Вернитесь назад и введите его снова.');
      return;
    }
    setState(() {
      _movingForward = true;
      _statusText = 'Завершаем регистрацию...';
    });

    try {
      await widget.phoneAuth.signUpWithVerifiedPhone(
        phone: widget.draft.phone,
        password: widget.draft.password,
        displayName: widget.draft.displayName,
        acceptedLegal: widget.draft.acceptedOffer,
      ).timeout(const Duration(seconds: 25));

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on TimeoutException {
      if (!mounted) return;
      _snack('Сервер отвечает слишком долго. Попробуйте еще раз.');
    } catch (e) {
      if (!mounted) return;
      _snack(_friendlyError(e));
    } finally {
      if (mounted) setState(() => _movingForward = false);
    }
  }

  Future<void> _confirm() async {
    if (_starting || _confirming || _movingForward || _errorText != null) {
      return;
    }
    debugPrint(
      'Phone registration call tapped: nameLen=${widget.draft.displayName.trim().length}, passLen=${widget.draft.password.trim().length}, phone=${widget.draft.phone}',
    );
    if (widget.draft.password.trim().isEmpty) {
      _snack('Пароль не сохранился. Вернитесь назад и введите его снова.');
      return;
    }
    if (!_isPhonePasswordValid(widget.draft.password)) {
      _snack('Введите не менее 8 цифр.');
      return;
    }
    if (widget.draft.displayName.trim().isEmpty) {
      _snack('Имя не сохранилось. Вернитесь назад и введите его снова.');
      return;
    }
    setState(() => _statusText = 'Открываем приложение звонков...');
    final opened = await _launchCall();
    if (!mounted) return;
    if (!opened) {
      setState(() => _statusText = 'Не удалось открыть приложение звонков.');
      return;
    }
    _callStarted = true;
    setState(() => _statusText = 'Проверяем подтверждение номера...');
    await _pollAndFinish(showPendingSnack: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final supportNumber = (_callPhonePretty ?? _callPhone ?? '').trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Подтверждение номера телефона')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 12),
          Text(
            'Чтобы подтвердить номер телефона, необходимо совершить звонок на указанный номер',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: theme.colorScheme.surfaceContainerLow,
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              children: [
                Text(
                  'Номер для подтверждения',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  supportNumber.isEmpty ? 'Подготавливаем...' : supportNumber,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Ваш номер: ${widget.draft.phone}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if ((_statusText ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _statusText!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if ((_errorText ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _errorText!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: (_starting ||
                    _confirming ||
                    _movingForward ||
                    _errorText != null)
                ? null
                : _confirm,
            child: Text(
              _starting
                  ? 'Подготавливаем...'
                  : (_confirming || _movingForward
                      ? 'Подтверждаем...'
                      : 'Позвонить'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneVerificationScreen extends StatefulWidget {
  final String phone;
  final CallcheckService callcheckService;
  final Future<void> Function() onConfirmed;

  const _PhoneVerificationScreen({
    required this.phone,
    required this.callcheckService,
    required this.onConfirmed,
  });

  @override
  State<_PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends State<_PhoneVerificationScreen>
    with WidgetsBindingObserver {
  bool _callStarted = false;
  bool _movingForward = false;
  bool _loadingStart = true;
  bool _checkingStatus = false;
  String? _statusHint;
  String? _checkId;
  String? _callPhone;
  String? _callPhonePretty;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startVerification();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _callStarted && !_movingForward) {
      _pollStatusAndContinue(
        attempts: 6,
        delay: const Duration(seconds: 2),
        showPendingSnack: true,
      );
    }
  }

  Future<void> _startVerification() async {
    setState(() {
      _loadingStart = true;
      _errorText = null;
    });

    try {
      final result = await widget.callcheckService.startVerification(
        phone: widget.phone,
      );
      if (!mounted) return;
      setState(() {
        _checkId = result.checkId;
        _callPhone = result.callPhone;
        _callPhonePretty = result.callPhonePretty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _loadingStart = false);
      }
    }
  }

  Future<void> _call() async {
    final number = _normalizeDialablePhone((_callPhone ?? '').trim());
    if (number.isEmpty) {
      return;
    }
    setState(() => _callStarted = true);

    final uri = Uri.parse('tel:$number');
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось открыть звонилку. Номер: $number')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть звонилку. Номер: $number')),
      );
    }
  }

  String _normalizeDialablePhone(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    final hasPlus = trimmed.startsWith('+');
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    return hasPlus ? '+$digits' : digits;
  }

  Future<bool> _checkStatusAndContinue({bool showPendingSnack = true}) async {
    final checkId = _checkId;
    if (checkId == null || checkId.isEmpty || _checkingStatus) return false;

    setState(() {
      _checkingStatus = true;
      _statusHint = 'Проверяем подтверждение номера...';
    });
    try {
      final result =
          await widget.callcheckService.checkStatus(checkId: checkId);
      if (!mounted) return false;

      if (result.isConfirmed) {
        setState(() {
          _statusHint = 'Номер подтвержден';
        });
        await _openProfileSetup();
        return true;
      }

      final text = result.checkStatusText.trim().isEmpty
          ? 'Номер пока не подтвержден'
          : result.checkStatusText.trim();
      setState(() {
        _statusHint = text;
      });
      if (showPendingSnack) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(text)));
      }
      return false;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _statusHint = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', 'Ошибка: ')),
        ),
      );
      return false;
    } finally {
      if (mounted) {
        setState(() => _checkingStatus = false);
      }
    }
  }

  Future<void> _pollStatusAndContinue({
    required int attempts,
    required Duration delay,
    required bool showPendingSnack,
  }) async {
    for (var i = 0; i < attempts; i++) {
      final confirmed = await _checkStatusAndContinue(
          showPendingSnack: i == attempts - 1 && showPendingSnack);
      if (confirmed || !mounted || _movingForward) {
        return;
      }
      if (i < attempts - 1) {
        await Future<void>.delayed(delay);
      }
    }
  }

  Future<void> _openProfileSetup() async {
    if (_movingForward) return;
    setState(() => _movingForward = true);
    await widget.onConfirmed();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final supportNumber = (_callPhonePretty ?? _callPhone ?? '').trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Подтверждение')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                Icons.verified_user_outlined,
                size: 92,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Подтверждение',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              if (_loadingStart) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 12),
                Text(
                  'Подготавливаем номер для подтверждения...',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
              ] else if (_errorText != null) ...[
                Text(
                  _errorText!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.45,
                    color: theme.colorScheme.error,
                  ),
                ),
              ] else ...[
                Text(
                  'Для автоматического подтверждения номера позвоните по бесплатному номеру: $supportNumber',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Ваш номер: ${widget.phone}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if ((_statusHint ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  _statusHint!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const Spacer(),
              FilledButton(
                onPressed: (_movingForward ||
                        _loadingStart ||
                        _errorText != null ||
                        supportNumber.isEmpty)
                    ? null
                    : _call,
                child: const Text('Позвонить'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: (_movingForward ||
                        _loadingStart ||
                        _errorText != null ||
                        _checkingStatus)
                    ? null
                    : () => _pollStatusAndContinue(
                          attempts: 6,
                          delay: const Duration(seconds: 2),
                          showPendingSnack: true,
                        ),
                child: Text(
                  _checkingStatus ? 'Проверяем...' : 'Номер уже подтвержден',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneProfileSetupScreen extends StatefulWidget {
  final String phone;
  final bool hasAcceptedLegal;
  final PhoneAuthBackendService phoneAuth;

  const _PhoneProfileSetupScreen({
    required this.phone,
    required this.hasAcceptedLegal,
    required this.phoneAuth,
  });

  @override
  State<_PhoneProfileSetupScreen> createState() =>
      _PhoneProfileSetupScreenState();
}

class _PhoneProfileSetupScreenState extends State<_PhoneProfileSetupScreen> {
  final _nameCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;

  SupabaseClient get _sb => Supabase.instance.client;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    if (name.isEmpty) {
      _snack('Введите имя');
      return;
    }
    if (pass.isEmpty) {
      _snack('Введите пароль');
      return;
    }
    if (!_isPhonePasswordValid(pass)) {
      _snack('Введите не менее 8 цифр.');
      return;
    }

    setState(() => _loading = true);
    try {
      await widget.phoneAuth.signUpWithVerifiedPhone(
        phone: widget.phone,
        password: pass,
        displayName: name,
        acceptedLegal: widget.hasAcceptedLegal,
      );

      if (!mounted) return;
      if (_sb.auth.currentSession != null) {
        Navigator.of(context).pop();
        return;
      }
    } catch (e) {
      _snack(widget.phoneAuth.userMessageForError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Создание аккаунта')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            enabled: false,
            decoration: InputDecoration(
              labelText: 'Телефон',
              hintText: widget.phone,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Имя'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            obscureText: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Пароль',
              helperText: 'Введите не менее 8 цифр',
            ),
            onSubmitted: (_) {
              if (!_loading) {
                _submit();
              }
            },
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: Text(_loading ? 'Подождите...' : 'Создать аккаунт'),
          ),
        ],
      ),
    );
  }
}

class _PhonePasswordResetScreen extends StatefulWidget {
  final String phone;
  final PhoneAuthBackendService phoneAuth;

  const _PhonePasswordResetScreen({
    required this.phone,
    required this.phoneAuth,
  });

  @override
  State<_PhonePasswordResetScreen> createState() =>
      _PhonePasswordResetScreenState();
}

class _PhonePasswordResetScreenState extends State<_PhonePasswordResetScreen> {
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  bool _loading = false;

  SupabaseClient get _sb => Supabase.instance.client;

  @override
  void dispose() {
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _submit() async {
    final pass = _passCtrl.text.trim();
    final pass2 = _pass2Ctrl.text.trim();

    if (pass.isEmpty || pass2.isEmpty) {
      _snack('Введите новый пароль и повторите его');
      return;
    }
    if (!_isPhonePasswordValid(pass)) {
      _snack('Введите не менее 8 цифр.');
      return;
    }
    if (pass != pass2) {
      _snack('Пароли не совпадают');
      return;
    }

    setState(() => _loading = true);
    try {
      await widget.phoneAuth.resetPasswordWithVerifiedPhone(
        phone: widget.phone,
        newPassword: pass,
      );

      final user = _sb.auth.currentUser;
      if (user != null) {
        await ProfileService().updateProfile(user.id, {
          'phone': widget.phone,
          'phone_verified': true,
        });
      }

      if (!mounted) return;
      _snack('Пароль обновлен. Вход выполнен автоматически.');
      Navigator.of(context).pop();
    } catch (e) {
      _snack('Ошибка: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новый пароль')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            enabled: false,
            decoration: InputDecoration(
              labelText: 'Телефон',
              hintText: widget.phone,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            obscureText: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Новый пароль',
              helperText: 'Введите не менее 8 цифр',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass2Ctrl,
            obscureText: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Повторите пароль'),
            onSubmitted: (_) {
              if (!_loading) {
                _submit();
              }
            },
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: Text(_loading ? 'Подождите...' : 'Сохранить пароль'),
          ),
        ],
      ),
    );
  }
}
