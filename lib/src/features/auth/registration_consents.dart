import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'privacy_screen.dart';
import 'terms_screen.dart';
import 'legal_document_screen.dart';

class RegistrationConsents extends StatefulWidget {
  const RegistrationConsents(
      {super.key,
      required this.acceptedLegal,
      required this.acceptedPersonalData,
      required this.onLegalChanged,
      required this.onPersonalDataChanged,
      this.loading = false});
  final bool acceptedLegal;
  final bool acceptedPersonalData;
  final bool loading;
  final ValueChanged<bool> onLegalChanged;
  final ValueChanged<bool> onPersonalDataChanged;
  @override
  State<RegistrationConsents> createState() => _RegistrationConsentsState();
}

class _RegistrationConsentsState extends State<RegistrationConsents> {
  late final _termsTap = TapGestureRecognizer()..onTap = _openTerms;
  late final _privacyTap = TapGestureRecognizer()..onTap = _openPrivacy;
  late final _personalDataTap = TapGestureRecognizer()
    ..onTap = _openPersonalDataConsent;

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    _personalDataTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        _buildLegalBlock(Theme.of(context)),
        const SizedBox(height: 8),
        _buildPersonalDataConsentBlock(Theme.of(context)),
      ]);

  void _openTerms() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TermsScreen()),
    );
  }

  void _openPrivacy() {
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: kIsWeb ? const RouteSettings(name: '/privacy') : null,
        builder: (_) => const PrivacyScreen(),
      ),
    );
  }

  void _openPersonalDataConsent() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const LegalDocumentScreen(
          kind: LegalDocumentKind.personalDataConsent,
        ),
      ),
    );
  }

  Widget _buildLegalBlock(ThemeData theme) {
    return _buildConsentBlock(
      theme,
      key: const ValueKey('registration-legal-consent-block'),
      value: widget.acceptedLegal,
      onChanged: (value) {
        widget.onLegalChanged(value ?? false);
      },
      children: [
        const TextSpan(text: 'Я принимаю '),
        TextSpan(
          text: 'Пользовательское соглашение',
          style: _legalLinkStyle(theme),
          recognizer: _termsTap,
        ),
        const TextSpan(text: ' и ознакомился(ась) с '),
        TextSpan(
          text: 'Политикой конфиденциальности',
          style: _legalLinkStyle(theme),
          recognizer: _privacyTap,
        ),
      ],
    );
  }

  Widget _buildPersonalDataConsentBlock(ThemeData theme) {
    return _buildConsentBlock(
      theme,
      key: const ValueKey('registration-personal-data-consent-block'),
      value: widget.acceptedPersonalData,
      onChanged: (value) {
        widget.onPersonalDataChanged(value ?? false);
      },
      children: [
        const TextSpan(text: 'Я даю '),
        TextSpan(
          text: 'согласие на обработку персональных данных',
          style: _legalLinkStyle(theme),
          recognizer: _personalDataTap,
        ),
      ],
    );
  }

  TextStyle _legalLinkStyle(ThemeData theme) => TextStyle(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w700,
        fontSize: _legalLinkFontSize(context),
      );

  double _legalBaseFontSize(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (kIsWeb && width >= 720) return 11.5;
    if (width < 340) return 11;
    return 11.2;
  }

  double _legalLinkFontSize(BuildContext context) =>
      _legalBaseFontSize(context) + 0.6;

  Widget _buildConsentBlock(
    ThemeData theme, {
    Key? key,
    required bool value,
    required ValueChanged<bool?> onChanged,
    required List<InlineSpan> children,
  }) {
    final baseFontSize = _legalBaseFontSize(context);
    return Container(
      key: key,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: Checkbox(
                value: value,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                onChanged: widget.loading ? null : onChanged,
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: MediaQuery.textScalerOf(context)
                        .clamp(maxScaleFactor: 1.12),
                  ),
                  child: RichText(
                    overflow: TextOverflow.visible,
                    text: TextSpan(
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontSize: baseFontSize,
                        height: 1.24,
                      ),
                      children: children,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
