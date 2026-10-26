import 'package:flutter/material.dart';

class PickOptionScreen extends StatefulWidget {
  final String title;
  final List<String> items;

  const PickOptionScreen({
    super.key,
    required this.title,
    required this.items,
  });

  @override
  State<PickOptionScreen> createState() => _PickOptionScreenState();
}

class _PickOptionScreenState extends State<PickOptionScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final items = q.isEmpty
        ? widget.items
        : widget.items.where((x) => x.toLowerCase().contains(q)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: false,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Поиск',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final item = items[i];
                return ListTile(
                  title: Text(item),
                  onTap: () => Navigator.pop(context, item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
