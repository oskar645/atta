import 'package:atta/src/features/auth/legal_document_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('О приложении')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'ATTA',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          const Text(
            'ATTA — это простой и удобный сервис для размещения объявлений. '
            'Здесь можно продавать и покупать автомобили, вещи для дома, технику, одежду и многое другое рядом с вами.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Мы стараемся сделать приложение понятным и честным:',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text('• без лишних сложностей'),
          const Text('• с быстрым поиском по городам и районам'),
          const Text('• с удобным чатом между покупателем и продавцом'),
          const SizedBox(height: 16),
          const Text(
            'Правила',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text('• Запрещены мошеннические и фейковые объявления.'),
          const Text('• Запрещены запрещенные законом товары и услуги.'),
          const Text(
              '• Спам, дубли и оскорбительный контент удаляются модерацией.'),
          const Text(
              '• При нарушениях объявление может быть удалено, а пользователь уведомлен.'),
          const SizedBox(height: 24),
          const Text(
            'Правовая информация',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          ..._legalDocuments.map(
            (document) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                document.title,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  settings: kIsWeb && document.kind == LegalDocumentKind.privacy
                      ? const RouteSettings(name: '/privacy')
                      : null,
                  builder: (_) => LegalDocumentScreen(kind: document.kind),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Версия: 1.0.0',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

const _legalDocuments = <({String title, LegalDocumentKind kind})>[
  (title: 'Пользовательское соглашение', kind: LegalDocumentKind.terms),
  (title: 'Политика конфиденциальности', kind: LegalDocumentKind.privacy),
  (
    title: 'Согласие на обработку персональных данных',
    kind: LegalDocumentKind.personalDataConsent,
  ),
  (title: 'Маркетинговое согласие', kind: LegalDocumentKind.marketingConsent),
  (
    title: 'Согласие на распространение персональных данных',
    kind: LegalDocumentKind.publicDataConsent,
  ),
];
