import 'package:flutter/material.dart';

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('О приложении')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Text(
            'ATTA',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 10),
          Text(
            'ATTA — это простой и удобный сервис для размещения объявлений. '
            'Здесь можно продавать и покупать автомобили, вещи для дома, технику, одежду и многое другое рядом с вами.',
          ),
          SizedBox(height: 16),
          Text(
            'Мы стараемся сделать приложение понятным и честным:',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 8),
          Text('• без лишних сложностей'),
          Text('• с быстрым поиском по городам и районам'),
          Text('• с удобным чатом между покупателем и продавцом'),
          SizedBox(height: 16),
          Text(
            'Правила',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 8),
          Text('• Запрещены мошеннические и фейковые объявления.'),
          Text('• Запрещены запрещенные законом товары и услуги.'),
          Text('• Спам, дубли и оскорбительный контент удаляются модерацией.'),
          Text(
              '• При нарушениях объявление может быть удалено, а пользователь уведомлен.'),
          SizedBox(height: 16),
          Text(
            'Версия: 1.0.0',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
