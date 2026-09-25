import 'dart:async';

import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/api/support_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PublicSupportScreen extends StatefulWidget {
  const PublicSupportScreen({super.key});
  @override
  State<PublicSupportScreen> createState() => _PublicSupportScreenState();
}

class _PublicSupportScreenState extends State<PublicSupportScreen> {
  static const storage = FlutterSecureStorage();
  static const idKey = 'atta_public_support_ticket_id';
  static const tokenKey = 'atta_public_support_ticket_token';
  final api = SupportApi(ApiClient(tokenStorage: TokenStorage()));
  final phone = TextEditingController();
  final name = TextEditingController();
  final email = TextEditingController();
  final description = TextEditingController();
  final message = TextEditingController();
  String? ticketId;
  String? token;
  String? status;
  String? error;
  bool busy = true;
  List<Map<String, dynamic>> messages = [];
  Timer? polling;

  @override
  void initState() {
    super.initState();
    restore();
  }

  @override
  void dispose() {
    polling?.cancel();
    phone.dispose();
    name.dispose();
    email.dispose();
    description.dispose();
    message.dispose();
    super.dispose();
  }

  Future<void> restore() async {
    final saved = await Future.wait(
        [storage.read(key: idKey), storage.read(key: tokenKey)]);
    ticketId = saved[0];
    token = saved[1];
    if (ticketId != null && token != null) await refresh();
    if (mounted) setState(() => busy = false);
  }

  Future<void> create() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await api.createPublicAccessTicket(
          oldPhone: phone.text,
          name: name.text,
          contactEmail: email.text,
          text: description.text);
      final ticket = Map<String, dynamic>.from(result['ticket'] as Map);
      ticketId = ticket['id']?.toString();
      token = result['publicToken']?.toString();
      await Future.wait([
        storage.write(key: idKey, value: ticketId),
        storage.write(key: tokenKey, value: token)
      ]);
      apply(result);
      startPolling();
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refresh() async {
    if (ticketId == null || token == null) return;
    try {
      apply(await api.getPublicAccessTicket(ticketId!, token!));
      startPolling();
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        await Future.wait(
            [storage.delete(key: idKey), storage.delete(key: tokenKey)]);
        ticketId = null;
        token = null;
      } else {
        error = e.message;
      }
    }
    if (mounted) setState(() {});
  }

  void apply(Map<String, dynamic> result) {
    final ticket = Map<String, dynamic>.from(result['ticket'] as Map);
    status = ticket['status']?.toString();
    messages = ((result['items'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList()
        .reversed
        .toList();
  }

  void startPolling() {
    polling ??= Timer.periodic(const Duration(seconds: 15), (_) => refresh());
  }

  Future<void> send() async {
    final text = message.text.trim();
    if (text.isEmpty || ticketId == null || token == null) return;
    setState(() => busy = true);
    try {
      await api.sendPublicAccessMessage(ticketId!, token!, text);
      message.clear();
      await refresh();
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Помощь с доступом')),
        body: busy && ticketId == null
            ? const Center(child: CircularProgressIndicator())
            : ticketId == null
                ? buildForm()
                : buildConversation(),
      );

  Widget buildForm() => ListView(padding: const EdgeInsets.all(24), children: [
        TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            maxLength: 32,
            decoration:
                const InputDecoration(labelText: 'Старый номер телефона')),
        TextField(
            controller: name,
            maxLength: 120,
            decoration: const InputDecoration(
                labelText: 'Имя профиля (необязательно)')),
        TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            maxLength: 254,
            decoration: const InputDecoration(
                labelText: 'Email для связи (необязательно)')),
        TextField(
            controller: description,
            maxLength: 2000,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(labelText: 'Опишите проблему')),
        const SizedBox(height: 12),
        FilledButton(
            onPressed: busy ? null : create,
            child: const Text('Отправить обращение')),
        if (error != null)
          Text(error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ]);

  Widget buildConversation() => Column(children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: refresh,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (_, index) {
                final item = messages[index];
                final mine = item['sender'] == 'user';
                return Align(
                  alignment:
                      mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(maxWidth: 320),
                    decoration: BoxDecoration(
                      color: mine
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(item['text']?.toString() ?? ''),
                  ),
                );
              },
            ),
          ),
        ),
        if (status != 'closed')
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: message,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      hintText: 'Сообщение',
                      counterText: '',
                    ),
                  ),
                ),
                IconButton(
                  onPressed: busy ? null : send,
                  icon: const Icon(Icons.send),
                ),
              ]),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Обращение закрыто'),
          ),
      ]);
}
