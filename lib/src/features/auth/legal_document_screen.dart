import 'package:flutter/material.dart';

import 'legal_texts.dart';

enum LegalDocumentKind {
  terms,
  privacy,
  personalDataConsent,
  marketingConsent,
  publicDataConsent,
}

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({
    super.key,
    required this.kind,
  });

  final LegalDocumentKind kind;

  String get _title {
    switch (kind) {
      case LegalDocumentKind.terms:
        return 'Пользовательское соглашение';
      case LegalDocumentKind.privacy:
        return 'Политика конфиденциальности';
      case LegalDocumentKind.personalDataConsent:
        return 'Согласие на обработку ПД';
      case LegalDocumentKind.marketingConsent:
        return 'Маркетинговое согласие';
      case LegalDocumentKind.publicDataConsent:
        return 'Публичные персональные данные';
    }
  }

  String get _text {
    switch (kind) {
      case LegalDocumentKind.terms:
        return attaTermsText;
      case LegalDocumentKind.privacy:
        return attaPrivacyText;
      case LegalDocumentKind.personalDataConsent:
        return attaPersonalDataConsentText;
      case LegalDocumentKind.marketingConsent:
        return attaMarketingConsentText;
      case LegalDocumentKind.publicDataConsent:
        return attaPublicDataConsentText;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLowest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SelectableText(
                  _text,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
