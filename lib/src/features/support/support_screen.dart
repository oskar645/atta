import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/services/support_service.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _text = TextEditingController();
  String? _ticketId;
  bool _sending = false;
  bool _loadingTicket = true;

  @override
  void initState() {
    super.initState();
    _loadMyTicket();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _loadMyTicket() async {
    final auth = context.read<AuthService>();
    final support = context.read<SupportService>();
    final uid = auth.currentUser!.uid;

    try {
      final existing = await support.getOrCreateMyTicketId(uid: uid);
      if (!mounted) return;
      setState(() {
        _ticketId = existing;
        _loadingTicket = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingTicket = false);
    }
  }

  Future<String> _getMyName() async {
    final auth = context.read<AuthService>();
    final profile = context.read<ProfileService>();
    final u = auth.currentUser!;

    final data = await profile.getProfile(u.uid);
    final dn = (data['displayName'] ?? data['name'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;

    final ad = (u.displayName ?? '').trim();
    if (ad.isNotEmpty) return ad;
    return u.email ?? 'Пользователь';
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;

    final auth = context.read<AuthService>();
    final support = context.read<SupportService>();

    setState(() => _sending = true);
    try {
      if (_ticketId == null) {
        final name = await _getMyName();
        _ticketId = await support.createTicketAndSendFirstMessage(
          uid: auth.currentUser!.uid,
          name: name,
          text: t,
        );
      } else {
        await support.sendMessage(ticketId: _ticketId!, text: t);
      }

      _text.clear();
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Ошибка: $e', isError: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final support = context.read<SupportService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Поддержка')),
      body: Column(
        children: [
          Expanded(
            child: _loadingTicket
                ? const Center(child: CircularProgressIndicator())
                : (_ticketId == null
                    ? const Center(
                        child: Text(
                          'Напишите сообщение, и тикет поддержки будет создан',
                        ),
                      )
                    : StreamBuilder<List<Map<String, dynamic>>>(
                        stream: support.streamMessages(_ticketId!),
                        builder: (context, snap) {
                          if (!snap.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final items = snap.data!;
                          if (items.isEmpty) {
                            return const Center(child: Text('Сообщений пока нет'));
                          }

                          return ListView.builder(
                            reverse: true,
                            padding: const EdgeInsets.all(12),
                            itemCount: items.length,
                            itemBuilder: (_, i) {
                              final m = items[i];
                              final sender = (m['sender'] ?? '').toString();
                              final text = (m['text'] ?? '').toString();
                              final mine = sender == 'user';

                              return Align(
                                alignment: mine
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  padding: const EdgeInsets.all(10),
                                  constraints: const BoxConstraints(maxWidth: 280),
                                  decoration: BoxDecoration(
                                    color: mine
                                        ? Theme.of(context).colorScheme.primaryContainer
                                        : Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(text),
                                ),
                              );
                            },
                          );
                        },
                      )),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      decoration: const InputDecoration(
                        hintText: 'Напишите в поддержку...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _sending ? null : _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
