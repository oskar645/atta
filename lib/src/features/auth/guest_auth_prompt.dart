import 'package:atta/src/features/auth/email_passwordless_screen.dart';
import 'package:atta/src/features/auth/legal_document_screen.dart';
import 'package:atta/src/features/auth/passwordless_screen.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum GuestAuthChoice { phone, email }

Future<bool> promptGuestAuth(BuildContext context) async {
  final mediaQuery = MediaQuery.of(context);
  final desktopWeb = kIsWeb && mediaQuery.size.width >= 720;
  final GuestAuthChoice? choice;
  if (desktopWeb) {
    choice = await showDialog<GuestAuthChoice>(
      context: context,
      builder: (_) => const Dialog(
        insetPadding: EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        child: GuestAuthSheet(inDialog: true),
      ),
    );
  } else {
    choice = await showModalBottomSheet<GuestAuthChoice>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      showDragHandle: false,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      constraints: BoxConstraints(
        minWidth: mediaQuery.size.width,
        maxWidth: mediaQuery.size.width,
        maxHeight: mediaQuery.size.height - mediaQuery.padding.top - 36,
      ),
      builder: (_) => const GuestAuthSheet(),
    );
  }

  if (!context.mounted || choice == null) return false;
  final screen = switch (choice) {
    GuestAuthChoice.phone =>
      const PasswordlessScreen(returnToPreviousAfterAuth: true),
    GuestAuthChoice.email =>
      const EmailPasswordlessScreen(returnToPreviousAfterAuth: true),
  };
  await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      settings: RouteSettings(name: 'guest-auth-${choice.name}'),
      builder: (_) => screen,
    ),
  );

  if (!context.mounted) return false;
  return context.read<AuthService>().isAuthenticated;
}

@Deprecated('Use promptGuestAuth instead.')
Future<bool> promptWebGuestAuth(BuildContext context) =>
    promptGuestAuth(context);

class GuestAuthSheet extends StatelessWidget {
  const GuestAuthSheet({super.key, this.inDialog = false});

  final bool inDialog;

  void _choose(BuildContext context, GuestAuthChoice choice) {
    Navigator.of(context).pop(choice);
  }

  Future<void> _openLegal(
    BuildContext context,
    LegalDocumentKind kind,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentScreen(kind: kind),
      ),
    );
  }

  ButtonStyle _compactLinkStyle() => TextButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final calculatedMaxHeight = mediaQuery.size.height -
        mediaQuery.padding.top -
        mediaQuery.padding.bottom -
        mediaQuery.viewInsets.bottom -
        36;
    final maxContentHeight =
        calculatedMaxHeight > 0 ? calculatedMaxHeight : mediaQuery.size.height;
    final content = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 440,
        maxHeight: maxContentHeight,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, inDialog ? 8 : 0, 20, 20),
        child: Column(
          key: const ValueKey('guest_auth_sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Закрыть',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
            Image.asset(
              'assets/branding/atta_logo.png',
              height: 48,
              fit: BoxFit.contain,
              semanticLabel: 'ATTA',
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
            Text(
              'Войдите, чтобы пользоваться всеми возможностями ATTA',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            _AuthChoiceTile(
              key: const ValueKey('guest-auth-phone'),
              icon: Icons.phone_outlined,
              title: 'Войти по звонку',
              subtitle: 'Бесплатный звонок вместо SMS',
              onTap: () => _choose(context, GuestAuthChoice.phone),
            ),
            const SizedBox(height: 10),
            _AuthChoiceTile(
              key: const ValueKey('guest-auth-email'),
              icon: Icons.mail_outline_rounded,
              title: 'Войти по почте',
              subtitle: 'Пришлём код на электронную почту',
              onTap: () => _choose(context, GuestAuthChoice.email),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    key: const ValueKey('guest-auth-account-recovery'),
                    style: _compactLinkStyle(),
                    onPressed: () => openAccountRecoveryScreen(context),
                    child: const Text(
                      'Нет доступа к номеру?',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton(
                    key: const ValueKey('guest-auth-public-support'),
                    style: _compactLinkStyle(),
                    onPressed: () => openPublicSupportScreen(context),
                    child: const Text(
                      'Нужна помощь?',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _LegalNotice(
              onTerms: () => _openLegal(context, LegalDocumentKind.terms),
              onPrivacy: () => _openLegal(context, LegalDocumentKind.privacy),
            ),
          ],
        ),
      ),
    );
    if (inDialog) {
      return SafeArea(child: content);
    }
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: content,
      ),
    );
  }
}

class _LegalNotice extends StatefulWidget {
  const _LegalNotice({
    required this.onTerms,
    required this.onPrivacy,
  });

  final VoidCallback onTerms;
  final VoidCallback onPrivacy;

  @override
  State<_LegalNotice> createState() => _LegalNoticeState();
}

class _LegalNoticeState extends State<_LegalNotice> {
  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()..onTap = () => widget.onTerms();
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => widget.onPrivacy();
  }

  @override
  void dispose() {
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontSize: 11,
      height: 1.35,
    );
    final linkStyle = baseStyle?.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary,
    );
    return RichText(
      key: const ValueKey('guest-auth-legal-notice'),
      textAlign: TextAlign.center,
      softWrap: true,
      textWidthBasis: TextWidthBasis.parent,
      text: TextSpan(
        style: baseStyle,
        children: [
          const TextSpan(
            text: 'Авторизуясь на сайте, Вы принимаете условия ',
          ),
          TextSpan(
            text: 'пользовательского соглашения',
            style: linkStyle,
            recognizer: _termsRecognizer,
          ),
          const TextSpan(text: ' и '),
          TextSpan(
            text: 'политики конфиденциальности',
            style: linkStyle,
            recognizer: _privacyRecognizer,
          ),
        ],
      ),
    );
  }
}

class _AuthChoiceTile extends StatelessWidget {
  const _AuthChoiceTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blue = theme.colorScheme.primary;
    return Material(
      color: blue.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: blue.withValues(alpha: 0.22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: blue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: theme.colorScheme.onPrimary),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: blue),
            ],
          ),
        ),
      ),
    );
  }
}
