import 'package:atta/src/services/admin_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AdminRepeatedMessagesScreen extends StatefulWidget {
  const AdminRepeatedMessagesScreen({super.key});

  @override
  State<AdminRepeatedMessagesScreen> createState() =>
      _AdminRepeatedMessagesScreenState();
}

class _AdminRepeatedMessagesScreenState
    extends State<AdminRepeatedMessagesScreen> {
  late Future<Map<String, dynamic>> _result;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _result = context.read<AdminService>().repeatedMessages();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Одинаковые сообщения')),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _result,
          builder: (context, snapshot) {
            if (!snapshot.hasData && !snapshot.hasError) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                  child: TextButton(
                onPressed: () => setState(_reload),
                child: const Text('Не удалось загрузить. Повторить'),
              ));
            }
            final items = (snapshot.data?['items'] as List? ?? const [])
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
            if (items.isEmpty) {
              return const Center(
                  child: Text('За последние 24 часа совпадений нет.'));
            }
            return RefreshIndicator(
              onRefresh: () async {
                setState(_reload);
                await _result;
              },
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final name = '${item['display_name'] ?? ''}'.trim();
                  final phone = '${item['phone'] ?? ''}'.trim();
                  return Card(
                      child: ListTile(
                    title: Text(
                        name.isEmpty ? 'Аккаунт ${item['sender_id']}' : name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (phone.isNotEmpty) Text(phone),
                        SelectableText('ID: ${item['sender_id']}'),
                        Text(
                            'Получателей: ${item['recipients']} · Сообщений: ${item['messages']}'),
                        const SizedBox(height: 6),
                        Text('${item['sample_text'] ?? ''}'),
                      ],
                    ),
                  ));
                },
              ),
            );
          },
        ),
      );
}
