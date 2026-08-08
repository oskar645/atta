import 'dart:async';

import 'package:atta/src/services/api/api_config.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/main_shell_controller.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:atta/src/utils/ru_phone.dart';

import 'privacy_screen.dart';
import 'terms_screen.dart';

enum _AuthMethod { phone, email }

const int _minPhonePasswordLength = 8;
const String _passwordTooShortMessage =
    'Пароль должен быть не короче 8 символов';
const String _emailAuthDisabledMessage =
    'Вход по email временно недоступен. Используйте номер телефона.';

void _selectHomeAfterAuthentication(BuildContext context) {
  context.read<MainShellController>().selectTab(0);
}

String _maskPhone(String input) {
  final digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 4) return '***';
  return '***${digits.substring(digits.length - 4)}';
}

bool _isPhonePasswordLongEnough(String value) {
  final trimmed = value.trim();
  return trimmed.length >= _minPhonePasswordLength;
}

String _phonePasswordErrorText(String value) {
  if (value.trim().isEmpty) {
    return 'Введите пароль';
  }
  return _passwordTooShortMessage;
}

class _PasswordTextField extends StatefulWidget {
  const _PasswordTextField({
    required this.controller,
    this.labelText = 'Пароль',
    this.helperText,
    this.errorText,
    this.textInputAction,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String labelText;
  final String? helperText;
  final String? errorText;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_PasswordTextField> createState() => _PasswordTextFieldState();
}

class _PasswordTextFieldState extends State<_PasswordTextField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscureText,
      textInputAction: widget.textInputAction,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.labelText,
        helperText: widget.helperText,
        errorText: widget.errorText,
        suffixIcon: IconButton(
          tooltip: _obscureText ? 'Показать пароль' : 'Скрыть пароль',
          onPressed: () {
            setState(() {
              _obscureText = !_obscureText;
            });
          },
          icon: Icon(
            _obscureText
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
        ),
      ),
    );
  }
}

class _PhoneRegistrationDraft {
  final String displayName;
  final String password;
  final String phone;
  final bool acceptedOffer;
  final bool phoneVerified;
  final String verificationCheckId;

  const _PhoneRegistrationDraft({
    required this.displayName,
    required this.password,
    required this.phone,
    required this.acceptedOffer,
    this.phoneVerified = false,
    this.verificationCheckId = '',
  });

  _PhoneRegistrationDraft copyWith({
    String? displayName,
    String? password,
    String? phone,
    bool? acceptedOffer,
    bool? phoneVerified,
    String? verificationCheckId,
  }) {
    return _PhoneRegistrationDraft(
      displayName: displayName ?? this.displayName,
      password: password ?? this.password,
      phone: phone ?? this.phone,
      acceptedOffer: acceptedOffer ?? this.acceptedOffer,
      phoneVerified: phoneVerified ?? this.phoneVerified,
      verificationCheckId: verificationCheckId ?? this.verificationCheckId,
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
  final _loginPhoneFocusNode = FocusNode();
  final _registrationNameFocusNode = FocusNode();
  final _registrationPhoneFocusNode = FocusNode();

  bool _isLogin = true;
  bool _loading = false;
  bool _hasAcceptedLegal = false;
  _AuthMethod _authMethod = _AuthMethod.phone;

  AuthService get _auth => context.read<AuthService>();
  bool get _showPhoneAuth => ApiConfig.enablePhoneAuth;
  bool get _showEmailLogin => ApiConfig.enableEmailLogin;
  bool get _showEmailSignup => ApiConfig.enableEmailSignup;
  bool get _canContinuePhoneRegistrationFromTab =>
      !_loading &&
      _nameCtrl.text.trim().isNotEmpty &&
      _isPhonePasswordLongEnough(_passCtrl.text) &&
      _hasAcceptedLegal;
  bool get _canContinuePhoneLogin =>
      !_loading && _isValidRuPhone(_loginCtrl.text);

  @override
  void dispose() {
    _loginCtrl.dispose();
    _phoneDigitsCtrl.dispose();
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    _passCtrl.dispose();
    _loginPhoneFocusNode.dispose();
    _registrationNameFocusNode.dispose();
    _registrationPhoneFocusNode.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _normalizeRuPhone(String input) => normalizeRuPhoneForApi(input);

  bool _isValidRuPhone(String input) => _normalizeRuPhone(input).isNotEmpty;

  bool _looksLikePhone(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return false;
    return RegExp(r'^[\d+\s()\-]+$').hasMatch(trimmed);
  }

  String _niceAuthError(Object error, {bool? isPhoneContext}) {
    final rawMessage = error.toString().replaceFirst('Exception: ', '').trim();
    final msg = rawMessage.toLowerCase();
    final phoneContext = isPhoneContext ?? (_authMethod == _AuthMethod.phone);

    if (msg.contains('email rate limit exceeded')) {
      return 'Слишком часто отправляли письма. Подождите немного и попробуйте снова.';
    }
    if (msg.contains('phone rate limit exceeded')) {
      return 'Слишком много попыток подтверждения телефона. Подождите немного и попробуйте снова.';
    }
    if (msg.contains('invalid login credentials')) {
      return phoneContext
          ? 'Номер или пароль указаны неверно'
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
      return 'Телефонная регистрация временно недоступна.';
    }
    return rawMessage;
  }

  Future<void> _resetPassword() async {
    final loginValue = _loginCtrl.text.trim();

    if (loginValue.isEmpty) {
      _snack('Введите номер телефона для восстановления пароля');
      return;
    }

    final phone = _normalizeRuPhone(loginValue);
    if (phone.isEmpty) {
      _snack('Введите номер телефона полностью');
      return;
    }

    setState(() => _loading = true);
    try {
      final exists = await _auth.isPhoneRegistered(phone: phone);
      if (!exists) {
        _snack('Аккаунт с таким номером не найден.');
        return;
      }
    } catch (e) {
      _snack(_auth.userMessageForError(e));
      return;
    } finally {
      if (mounted) setState(() => _loading = false);
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PhoneVerificationScreen(
          phone: phone,
          authService: _auth,
          purpose: 'reset_password',
          onConfirmed: (verificationCheckId) async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _PhonePasswordResetScreen(
                  phone: phone,
                  authService: _auth,
                  verificationCheckId: verificationCheckId,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _continuePhoneLogin() async {
    final loginValue = _loginCtrl.text.trim();
    if (loginValue.isEmpty) {
      _snack('Введите номер телефона');
      return;
    }
    if (!_looksLikePhone(loginValue) || !_isValidRuPhone(loginValue)) {
      _snack('Введите номер телефона полностью');
      return;
    }

    final phone = _normalizeRuPhone(loginValue);
    setState(() => _loading = true);
    try {
      final exists = await _auth.isPhoneRegistered(phone: phone);
      if (!exists) {
        _snack('На этом номере аккаунта нет');
        return;
      }

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _PhonePasswordLoginScreen(
            phone: phone,
            authService: _auth,
          ),
        ),
      );
    } catch (e) {
      _snack(_niceAuthError(e, isPhoneContext: true));
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
          authService: _auth,
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
    if (!_isPhonePasswordLongEnough(pass)) {
      _snack(_passwordTooShortMessage);
      return;
    }
    if (!_hasAcceptedLegal) {
      _snack(
          'Примите Пользовательское соглашение и Политику конфиденциальности');
      return;
    }

    setState(() => _loading = true);
    try {
      await _auth.signUp(
        email: email,
        password: pass,
        displayName: name,
        phone: phone,
      );
      if (!mounted) return;
      _selectHomeAfterAuthentication(context);
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      _snack(_niceAuthError(e, isPhoneContext: false));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleMode() {
    FocusScope.of(context).unfocus();
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
                ? 'Войдите по номеру телефона.'
                : 'Регистрация по телефону в 3 шага: профиль, номер и подтверждение звонком.',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
          const SizedBox(height: 8),
          Text(
            ApiConfig.emailAuthDisabledMessage,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodSwitch(ThemeData theme) {
    if (!_showEmailSignup) {
      return const SizedBox.shrink();
    }
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
    return _buildPhoneField(
      key: const ValueKey('registration-email-phone-field'),
      focusNode: _registrationPhoneFocusNode,
      controller: _phoneDigitsCtrl,
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildPhoneField({
    Key? key,
    FocusNode? focusNode,
    required TextEditingController controller,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
    String labelText = 'Номер телефона',
    String hintText = '928 123-45-67',
    String? errorText,
  }) {
    return TextField(
      key: key,
      focusNode: focusNode,
      controller: controller,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      inputFormatters: const [
        RuPhoneInputFormatter(),
      ],
      decoration: InputDecoration(
        prefixText: '+7 ',
        labelText: labelText,
        hintText: hintText,
        errorText: errorText,
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
          if (!_isLogin && _showEmailSignup) ...[
            _buildMethodSwitch(theme),
            const SizedBox(height: 16),
          ],
          if (_isLogin) ...[
            _buildPhoneField(
              key: const ValueKey('login-phone-field'),
              focusNode: _loginPhoneFocusNode,
              controller: _loginCtrl,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (_canContinuePhoneLogin) {
                  _continuePhoneLogin();
                }
              },
              labelText: 'Номер телефона',
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _loading ? null : _resetPassword,
                child: const Text('Забыли пароль?'),
              ),
            ),
            if (!_showEmailLogin) ...[
              const SizedBox(height: 4),
              Text(
                _emailAuthDisabledMessage,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _canContinuePhoneLogin ? _continuePhoneLogin : null,
              child: Text(_loading ? 'Подождите...' : 'Продолжить'),
            ),
          ] else if (_showPhoneAuth &&
              (_authMethod == _AuthMethod.phone || !_showEmailSignup)) ...[
            TextField(
              key: const ValueKey('phone-registration-username-field'),
              focusNode: _registrationNameFocusNode,
              controller: _nameCtrl,
              keyboardType: TextInputType.text,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              onTap: () {
                if (!_registrationNameFocusNode.hasFocus) {
                  FocusScope.of(context).unfocus();
                  _registrationNameFocusNode.requestFocus();
                }
              },
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Имя пользователя'),
            ),
            const SizedBox(height: 12),
            _PasswordTextField(
              controller: _passCtrl,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              labelText: 'Пароль',
              helperText: 'Минимум 8 символов',
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
          ] else if (_showEmailSignup) ...[
            TextField(
              key: const ValueKey('email-registration-name-field'),
              controller: _nameCtrl,
              keyboardType: TextInputType.name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Имя'),
            ),
            const SizedBox(height: 12),
            _buildPhonePrefixField(),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('email-registration-email-field'),
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            _PasswordTextField(
              controller: _passCtrl,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              labelText: 'Пароль',
              helperText: 'Минимум 8 символов',
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
          ] else ...[
            Text(
              _emailAuthDisabledMessage,
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 10),
          TextButton(
            onPressed: _loading ? null : _toggleMode,
            child: _isLogin
                ? const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: 'Нет аккаунта? ',
                          style: TextStyle(fontSize: 15),
                        ),
                        TextSpan(
                          text: 'Создать аккаунт',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ]),
                      maxLines: 1,
                    ),
                  )
                : const Text('Уже есть аккаунт? Войти'),
          ),
        ],
      ),
    );
  }
}

class _PhoneRegistrationCredentialsScreen extends StatefulWidget {
  final AuthService authService;

  const _PhoneRegistrationCredentialsScreen({
    required this.authService,
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
  bool get _isPasswordValid => _isPhonePasswordLongEnough(_passCtrl.text);
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
          authService: widget.authService,
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
            key:
                const ValueKey('phone-registration-credentials-username-field'),
            controller: _nameCtrl,
            keyboardType: TextInputType.text,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Имя пользователя',
              errorText: nameInvalid ? 'Введите имя пользователя' : null,
            ),
          ),
          const SizedBox(height: 12),
          _PasswordTextField(
            controller: _passCtrl,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _continue(),
            onChanged: (_) => setState(() {}),
            labelText: 'Пароль',
            helperText: 'Минимум 8 символов',
            errorText:
                passInvalid ? _phonePasswordErrorText(_passCtrl.text) : null,
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
  final AuthService authService;

  const _PhoneRegistrationPhoneScreen({
    required this.draft,
    required this.authService,
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

  String _normalizeRuPhone(String input) => normalizeRuPhoneForApi(input);

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
      'Phone registration phone step: nameLen=${widget.draft.displayName.trim().length}, passLen=${widget.draft.password.trim().length}, phone=${_maskPhone(phone)}',
    );
    setState(() => _loading = true);
    try {
      final alreadyRegistered =
          await widget.authService.isPhoneRegistered(phone: phone);
      if (alreadyRegistered) {
        _snack('На этом номере уже есть аккаунт');
        return;
      }

      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _PhoneRegistrationConfirmScreen(
            draft: widget.draft.copyWith(phone: phone),
            authService: widget.authService,
          ),
        ),
      );
    } catch (e) {
      _snack(widget.authService.userMessageForError(e));
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
            inputFormatters: const [
              RuPhoneInputFormatter(),
            ],
            decoration: InputDecoration(
              prefixText: '+7 ',
              labelText: 'Номер телефона',
              hintText: '928 123-45-67',
              errorText:
                  phoneInvalid ? 'Введите номер телефона полностью' : null,
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
  final AuthService authService;

  const _PhoneRegistrationConfirmScreen({
    required this.draft,
    required this.authService,
  });

  @override
  State<_PhoneRegistrationConfirmScreen> createState() =>
      _PhoneRegistrationConfirmScreenState();
}

class _PhoneRegistrationConfirmScreenState
    extends State<_PhoneRegistrationConfirmScreen> with WidgetsBindingObserver {
  bool _starting = true;
  bool _confirming = false;
  bool _pollingActive = false;
  bool _movingForward = false;
  bool _callStarted = false;
  String? _errorText;
  String? _statusText;
  String? _verificationId;
  String? _callToPhone;
  String? _callToPhonePretty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startVerification();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollingActive = false;
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
      _startAutoPolling(showTimeoutSnack: true);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _friendlyError(Object error) {
    final message = widget.authService.userMessageForError(error);
    final technical = error.toString();
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
      'Phone registration confirm step opened: nameLen=${widget.draft.displayName.trim().length}, passLen=${widget.draft.password.trim().length}, phone=${_maskPhone(widget.draft.phone)}',
    );

    try {
      final result = await widget.authService.startPhoneVerification(
        phone: widget.draft.phone,
        purpose: 'signup',
      );
      if (!mounted) return;
      setState(() {
        _verificationId = result.verificationId;
        _callToPhone = result.callToPhone;
        _callToPhonePretty = result.callToPhonePretty;
        _errorText = result.hasCallToPhone
            ? null
            : 'Подтверждение телефона временно недоступно. Попробуйте позже.';
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
    final number = _normalizeDialablePhone((_callToPhone ?? '').trim());
    if (number.isEmpty) return false;

    final candidates = <Uri>[
      Uri.parse('tel://$number'),
      Uri.parse('tel:$number'),
    ];
    try {
      for (final uri in candidates) {
        final canOpen = await canLaunchUrl(uri);
        debugPrint('Dial canLaunchUrl($uri) => $canOpen');
        if (!canOpen) continue;
        final openedDefault = await launchUrl(uri);
        if (openedDefault) return true;
        final openedExternal = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (openedExternal) return true;
      }

      final hint = defaultTargetPlatform == TargetPlatform.iOS
          ? ' Не работает в iOS Simulator: проверьте на реальном iPhone.'
          : '';
      _snack('Не удалось открыть звонилку. Номер: $number.$hint');
      return false;
    } catch (_) {
      final hint = defaultTargetPlatform == TargetPlatform.iOS
          ? ' Не работает в iOS Simulator: проверьте на реальном iPhone.'
          : '';
      _snack('Не удалось открыть звонилку. Номер: $number.$hint');
      return false;
    }
  }

  Future<void> _startAutoPolling({required bool showTimeoutSnack}) async {
    final verificationId = _verificationId;
    if (verificationId == null ||
        verificationId.isEmpty ||
        _confirming ||
        _pollingActive) {
      return;
    }

    setState(() {
      _pollingActive = true;
      _confirming = true;
      _statusText = 'Проверяем звонок...';
    });

    try {
      for (var i = 0; i < 30; i++) {
        late final dynamic result;
        try {
          result = await widget.authService.checkPhoneVerification(
            phone: widget.draft.phone,
            verificationId: verificationId,
            purpose: 'signup',
          );
        } catch (e) {
          if (_isTransientNetworkError(e) && i < 29) {
            if (!mounted) return;
            setState(() {
              _statusText = 'Проверяем звонок...';
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

        if (result.isExpired || result.status == 'failed') {
          final text = result.isExpired
              ? 'Время подтверждения истекло. Попробуйте ещё раз позже.'
              : 'Не удалось подтвердить звонок. Попробуйте ещё раз позже.';
          setState(() => _statusText = text);
          if (showTimeoutSnack) {
            _snack(text);
          }
          return;
        }

        if (i < 29) {
          await Future<void>.delayed(const Duration(seconds: 2));
        } else {
          const text =
              'Не удалось подтвердить звонок. Попробуйте ещё раз позже.';
          setState(() => _statusText = text);
          if (showTimeoutSnack) {
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
        if (showTimeoutSnack) {
          _snack(
              'Нет соединения с сервером. Проверьте интернет и попробуйте еще раз.');
        }
        return;
      }
      _snack(_friendlyError(e));
    } finally {
      if (mounted) {
        setState(() {
          _confirming = false;
          _pollingActive = false;
        });
      }
    }
  }

  Future<void> _finishRegistration() async {
    if (_movingForward) return;
    final verificationCheckId = _verificationId;
    debugPrint(
      'Phone registration finish requested: nameLen=${widget.draft.displayName.trim().length}, passLen=${widget.draft.password.trim().length}, callStarted=$_callStarted',
    );
    if (widget.draft.password.trim().isEmpty) {
      _snack('Пароль не сохранился. Вернитесь назад и введите его снова.');
      return;
    }
    if (!_isPhonePasswordLongEnough(widget.draft.password)) {
      _snack(_passwordTooShortMessage);
      return;
    }
    if (widget.draft.displayName.trim().isEmpty) {
      _snack('Имя не сохранилось. Вернитесь назад и введите его снова.');
      return;
    }
    if (verificationCheckId == null || verificationCheckId.isEmpty) {
      _snack('Не найдено подтверждение номера. Попробуйте снова.');
      return;
    }
    setState(() {
      _movingForward = true;
      _statusText = 'Завершаем регистрацию...';
    });

    try {
      await widget.authService
          .signUpWithVerifiedPhone(
            phone: widget.draft.phone,
            password: widget.draft.password,
            displayName: widget.draft.displayName,
            acceptedLegal: widget.draft.acceptedOffer,
            verificationCheckId: verificationCheckId,
          )
          .timeout(const Duration(seconds: 25));

      if (!mounted) return;
      _selectHomeAfterAuthentication(context);
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
      'Phone registration call tapped: nameLen=${widget.draft.displayName.trim().length}, passLen=${widget.draft.password.trim().length}, phone=${_maskPhone(widget.draft.phone)}',
    );
    if (widget.draft.password.trim().isEmpty) {
      _snack('Пароль не сохранился. Вернитесь назад и введите его снова.');
      return;
    }
    if (!_isPhonePasswordLongEnough(widget.draft.password)) {
      _snack(_passwordTooShortMessage);
      return;
    }
    if (widget.draft.displayName.trim().isEmpty) {
      _snack('Имя не сохранилось. Вернитесь назад и введите его снова.');
      return;
    }
    final supportNumber = (_callToPhone ?? '').trim();
    if (supportNumber.isEmpty) {
      setState(() {
        _errorText =
            'Подтверждение телефона временно недоступно. Попробуйте позже.';
      });
      return;
    }

    setState(() => _statusText = 'Проверяем звонок...');
    final opened = await _launchCall();
    if (!mounted) return;
    if (!opened) {
      setState(() => _statusText = 'Не удалось открыть приложение звонков.');
      return;
    }
    _callStarted = true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final supportNumber = (_callToPhone ?? '').trim();
    final supportNumberPretty = (_callToPhonePretty ?? '').trim();
    final supportNumberLabel =
        supportNumberPretty.isNotEmpty ? supportNumberPretty : supportNumber;

    return Scaffold(
      appBar: AppBar(title: const Text('Подтвердите номер')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 12),
          Text(
            supportNumber.isEmpty
                ? 'Подтверждение телефона временно недоступно. Попробуйте позже.'
                : 'Позвоните на указанный номер. Звонок бесплатный, трубку брать не нужно.',
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
                  'Номер для звонка',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  supportNumber.isEmpty ? 'Недоступно' : supportNumberLabel,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Ваш номер: ${formatRuPhoneForDisplay(widget.draft.phone)}',
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
            const SizedBox(height: 12),
            TextButton(
              onPressed: _starting || _confirming || _movingForward
                  ? null
                  : () => Navigator.of(context).pop(),
              child: const Text('Назад'),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: (_starting ||
                    _confirming ||
                    _movingForward ||
                    _errorText != null ||
                    supportNumber.isEmpty)
                ? null
                : _confirm,
            child: Text(
              _starting
                  ? 'Подготавливаем...'
                  : (_confirming || _movingForward
                      ? 'Проверяем звонок...'
                      : 'Позвонить'),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _starting || _confirming || _movingForward
                ? null
                : () => Navigator.of(context).pop(),
            child: const Text('Изменить номер'),
          ),
        ],
      ),
    );
  }
}

class _PhoneVerificationScreen extends StatefulWidget {
  final String phone;
  final AuthService authService;
  final String purpose;
  final Future<void> Function(String verificationCheckId) onConfirmed;

  const _PhoneVerificationScreen({
    required this.phone,
    required this.authService,
    required this.purpose,
    required this.onConfirmed,
  });

  @override
  State<_PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends State<_PhoneVerificationScreen>
    with WidgetsBindingObserver {
  bool _callStarted = false;
  bool _pollingActive = false;
  bool _movingForward = false;
  bool _loadingStart = true;
  bool _checkingStatus = false;
  String? _statusHint;
  String? _verificationId;
  String? _callToPhone;
  String? _callToPhonePretty;
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
    _pollingActive = false;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _callStarted && !_movingForward) {
      _pollStatusAndContinue(
        attempts: 30,
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
      final result = await widget.authService.startPhoneVerification(
        phone: widget.phone,
        purpose: widget.purpose,
      );
      if (!mounted) return;
      setState(() {
        _verificationId = result.verificationId;
        _callToPhone = result.callToPhone;
        _callToPhonePretty = result.callToPhonePretty;
        _errorText = result.hasCallToPhone
            ? null
            : 'Подтверждение телефона временно недоступно. Попробуйте позже.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = widget.authService.userMessageForError(e);
      });
    } finally {
      if (mounted) {
        setState(() => _loadingStart = false);
      }
    }
  }

  Future<void> _call() async {
    final number = _normalizeDialablePhone((_callToPhone ?? '').trim());
    if (number.isEmpty) {
      return;
    }
    setState(() {
      _callStarted = true;
      _statusHint = 'Проверяем звонок...';
    });

    final candidates = <Uri>[
      Uri.parse('tel://$number'),
      Uri.parse('tel:$number'),
    ];
    try {
      var opened = false;
      for (final uri in candidates) {
        final canOpen = await canLaunchUrl(uri);
        debugPrint('Dial canLaunchUrl($uri) => $canOpen');
        if (!canOpen) continue;
        opened = await launchUrl(uri);
        if (!opened) {
          opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        if (opened) break;
      }

      if (!opened) {
        if (!mounted) return;
        final hint = defaultTargetPlatform == TargetPlatform.iOS
            ? ' Не работает в iOS Simulator: проверьте на реальном iPhone.'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Не удалось открыть звонилку. Номер: $number.$hint')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      final hint = defaultTargetPlatform == TargetPlatform.iOS
          ? ' Не работает в iOS Simulator: проверьте на реальном iPhone.'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Не удалось открыть звонилку. Номер: $number.$hint')),
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
    final verificationId = _verificationId;
    if (verificationId == null || verificationId.isEmpty || _checkingStatus) {
      return false;
    }

    setState(() {
      _checkingStatus = true;
      _statusHint = 'Проверяем подтверждение номера...';
    });
    try {
      final result = await widget.authService.checkPhoneVerification(
        phone: widget.phone,
        verificationId: verificationId,
        purpose: widget.purpose,
      );
      if (!mounted) return false;

      if (result.isConfirmed) {
        setState(() {
          _statusHint = 'Номер подтвержден';
        });
        await _openProfileSetup();
        return true;
      }

      if (result.isExpired || result.status == 'failed') {
        final text = result.isExpired
            ? 'Время подтверждения истекло. Попробуйте ещё раз позже.'
            : 'Не удалось подтвердить звонок. Попробуйте ещё раз позже.';
        setState(() {
          _statusHint = text;
        });
        if (showPendingSnack) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(text)));
        }
        return true;
      }

      const text = 'Проверяем звонок...';
      setState(() {
        _statusHint = text;
      });
      return false;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _statusHint = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.authService.userMessageForError(e)),
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
    if (_pollingActive) return;
    _pollingActive = true;
    for (var i = 0; i < attempts; i++) {
      final confirmed = await _checkStatusAndContinue(
          showPendingSnack: i == attempts - 1 && showPendingSnack);
      if (confirmed || !mounted || _movingForward) {
        _pollingActive = false;
        return;
      }
      if (i < attempts - 1) {
        await Future<void>.delayed(delay);
      }
    }
    _pollingActive = false;
    if (!mounted) return;
    const text = 'Не удалось подтвердить звонок. Попробуйте ещё раз позже.';
    setState(() {
      _statusHint = text;
    });
    if (showPendingSnack) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(text)),
      );
    }
  }

  Future<void> _openProfileSetup() async {
    if (_movingForward) return;
    final verificationCheckId = _verificationId;
    if (verificationCheckId == null || verificationCheckId.isEmpty) {
      _snack('Не удалось получить подтверждение номера.');
      return;
    }
    setState(() => _movingForward = true);
    await widget.onConfirmed(verificationCheckId);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final supportNumber = (_callToPhone ?? '').trim();
    final supportNumberPretty = (_callToPhonePretty ?? '').trim();
    final supportNumberLabel =
        supportNumberPretty.isNotEmpty ? supportNumberPretty : supportNumber;

    return Scaffold(
      appBar: AppBar(title: const Text('Подтвердите номер')),
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
                'Подтверждение номера телефона',
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
                const SizedBox(height: 16),
                TextButton(
                  onPressed:
                      _loadingStart ? null : () => Navigator.of(context).pop(),
                  child: const Text('Назад'),
                ),
              ] else ...[
                Text(
                  supportNumber.isEmpty
                      ? 'Подтверждение телефона временно недоступно. Попробуйте позже.'
                      : 'Позвоните на указанный номер. Звонок бесплатный, трубку брать не нужно.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
                if (supportNumber.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Номер для звонка',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    supportNumberLabel,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
              const SizedBox(height: 8),
              Text(
                'Ваш номер: ${formatRuPhoneForDisplay(widget.phone)}',
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
                child: Text(
                  (_checkingStatus || _pollingActive)
                      ? 'Проверяем звонок...'
                      : 'Позвонить',
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _movingForward || _loadingStart
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('Назад'),
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
  final AuthService authService;
  final String verificationCheckId;

  const _PhoneProfileSetupScreen({
    required this.phone,
    required this.hasAcceptedLegal,
    required this.authService,
    required this.verificationCheckId,
  });

  @override
  State<_PhoneProfileSetupScreen> createState() =>
      _PhoneProfileSetupScreenState();
}

class _PhoneProfileSetupScreenState extends State<_PhoneProfileSetupScreen> {
  final _nameCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;

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
    if (!_isPhonePasswordLongEnough(pass)) {
      _snack(_passwordTooShortMessage);
      return;
    }

    setState(() => _loading = true);
    try {
      await widget.authService.signUpWithVerifiedPhone(
        phone: widget.phone,
        password: pass,
        displayName: name,
        acceptedLegal: widget.hasAcceptedLegal,
        verificationCheckId: widget.verificationCheckId,
      );

      if (!mounted) return;
      if (widget.authService.isAuthenticated) {
        _selectHomeAfterAuthentication(context);
        Navigator.of(context).pop();
        return;
      }
    } catch (e) {
      _snack(widget.authService.userMessageForError(e));
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
              hintText: formatRuPhoneForDisplay(widget.phone),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            keyboardType: TextInputType.name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Имя'),
          ),
          const SizedBox(height: 12),
          _PasswordTextField(
            controller: _passCtrl,
            textInputAction: TextInputAction.done,
            labelText: 'Пароль',
            helperText: 'Минимум 8 символов',
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
  final AuthService authService;
  final String verificationCheckId;

  const _PhonePasswordResetScreen({
    required this.phone,
    required this.authService,
    required this.verificationCheckId,
  });

  @override
  State<_PhonePasswordResetScreen> createState() =>
      _PhonePasswordResetScreenState();
}

class _PhonePasswordResetScreenState extends State<_PhonePasswordResetScreen> {
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  bool _loading = false;

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
    if (!_isPhonePasswordLongEnough(pass)) {
      _snack(_passwordTooShortMessage);
      return;
    }
    if (pass != pass2) {
      _snack('Пароли не совпадают');
      return;
    }

    setState(() => _loading = true);
    try {
      await widget.authService.resetPasswordWithVerifiedPhone(
        phone: widget.phone,
        newPassword: pass,
        verificationCheckId: widget.verificationCheckId,
      );

      final currentUser = widget.authService.currentUser;
      if (currentUser != null) {
        await ProfileService().updateProfile(currentUser.uid, {
          'phone': widget.phone,
          'phone_verified': true,
        });
      }

      if (!mounted) return;
      _snack('Пароль обновлен.');
      Navigator.of(context).pop();
    } catch (e) {
      _snack(widget.authService.userMessageForError(e));
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
              hintText: formatRuPhoneForDisplay(widget.phone),
            ),
          ),
          const SizedBox(height: 12),
          _PasswordTextField(
            controller: _passCtrl,
            textInputAction: TextInputAction.next,
            labelText: 'Новый пароль',
            helperText: 'Минимум 8 символов',
          ),
          const SizedBox(height: 12),
          _PasswordTextField(
            controller: _pass2Ctrl,
            textInputAction: TextInputAction.done,
            labelText: 'Повторите пароль',
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

class _PhonePasswordLoginScreen extends StatefulWidget {
  const _PhonePasswordLoginScreen({
    required this.phone,
    required this.authService,
  });

  final String phone;
  final AuthService authService;

  @override
  State<_PhonePasswordLoginScreen> createState() =>
      _PhonePasswordLoginScreenState();
}

class _PhonePasswordLoginScreenState extends State<_PhonePasswordLoginScreen> {
  final _passwordCtrl = TextEditingController();
  StreamSubscription<AuthSessionEvent>? _authSub;
  bool _loading = false;
  bool _didCloseAfterAuth = false;

  @override
  void initState() {
    super.initState();
    _authSub = widget.authService.onAuthStateChange.listen((_) {
      _closeAfterSuccessfulAuth();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _passwordCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_loading && _isPhonePasswordLongEnough(_passwordCtrl.text);

  bool get _showPasswordError {
    final password = _passwordCtrl.text.trim();
    return password.isNotEmpty && !_isPhonePasswordLongEnough(password);
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _closeAfterSuccessfulAuth() {
    if (!mounted || _didCloseAfterAuth || !widget.authService.isAuthenticated) {
      return;
    }
    _didCloseAfterAuth = true;
    _selectHomeAfterAuthentication(context);
    Navigator.of(context).maybePop();
  }

  Future<void> _submit() async {
    if (_loading) return;
    final password = _passwordCtrl.text.trim();
    if (password.isEmpty) {
      _snack('Введите пароль');
      return;
    }
    if (!_isPhonePasswordLongEnough(password)) {
      _snack(_passwordTooShortMessage);
      return;
    }
    setState(() => _loading = true);
    try {
      await widget.authService.signInWithPhone(
        phone: widget.phone,
        password: password,
      );
      _closeAfterSuccessfulAuth();
    } catch (e) {
      _snack(widget.authService.userMessageForError(e, isSignIn: true));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вход')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Введите пароль от аккаунта',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          _PasswordTextField(
            controller: _passwordCtrl,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (_canSubmit) {
                _submit();
              }
            },
            labelText: 'Пароль',
            helperText: 'Минимум 8 символов',
            errorText: _showPasswordError ? _passwordTooShortMessage : null,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _canSubmit ? _submit : null,
            child: Text(_loading ? 'Подождите...' : 'Войти'),
          ),
        ],
      ),
    );
  }
}
