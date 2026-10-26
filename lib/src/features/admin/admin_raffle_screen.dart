import 'dart:io';

import 'package:atta/src/services/admin_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'raffle_csv_download_stub.dart'
    if (dart.library.html) 'raffle_csv_download_web.dart' as csv_download;

class AdminRaffleScreen extends StatefulWidget {
  const AdminRaffleScreen({super.key, this.initialRange});

  final DateTimeRange? initialRange;

  @override
  State<AdminRaffleScreen> createState() => _AdminRaffleScreenState();
}

class _AdminRaffleScreenState extends State<AdminRaffleScreen> {
  final TextEditingController _priceController =
      TextEditingController(text: '500');
  DateTime? startDate;
  DateTime? endDate;
  Map<String, dynamic>? summary;
  final List<Map<String, dynamic>> items = [];
  String? cursor;
  String? error;
  bool loading = false;
  bool exporting = false;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    startDate = widget.initialRange?.start;
    endDate = widget.initialRange?.end;
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  String? get _priceError {
    final value = _priceController.text.trim();
    if (value.isEmpty) return 'Укажите цену билета';
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(value)) {
      return 'Введите положительное целое число';
    }
    return null;
  }

  String? get _validTicketPrice =>
      _priceError == null ? _priceController.text.trim() : null;

  void _priceChanged(String _) {
    setState(() {
      generation++;
      summary = null;
      items.clear();
      cursor = null;
      loading = false;
      error = null;
    });
  }

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final first = start ? DateTime(2020) : (startDate ?? DateTime(2020));
    final last = DateTime(now.year + 30, 12, 31);
    final selected = await showDatePicker(
      context: context,
      initialDate: start ? (startDate ?? now) : (endDate ?? startDate ?? now),
      firstDate: first,
      lastDate: last,
      initialDatePickerMode: DatePickerMode.year,
      helpText: start ? 'Дата начала розыгрыша' : 'Дата окончания розыгрыша',
    );
    if (selected == null || !mounted) return;
    setState(() {
      generation++;
      if (start) {
        startDate = selected;
        if (endDate != null && endDate!.isBefore(selected)) endDate = null;
      } else {
        endDate = selected;
      }
      summary = null;
      items.clear();
      cursor = null;
      loading = false;
      error = null;
    });
  }

  ({String from, String to}) _period() {
    return (
      from: startDate!.toUtc().toIso8601String(),
      to: DateTime(endDate!.year, endDate!.month, endDate!.day + 1)
          .toUtc()
          .subtract(const Duration(milliseconds: 1))
          .toIso8601String(),
    );
  }

  Future<void> _load({bool reset = false}) async {
    final ticketPrice = _validTicketPrice;
    if (startDate == null ||
        endDate == null ||
        ticketPrice == null ||
        loading ||
        (!reset && cursor == null)) {
      return;
    }
    final currentGeneration = reset ? ++generation : generation;
    setState(() {
      loading = true;
      error = null;
      if (reset) {
        items.clear();
        summary = null;
        cursor = null;
      }
    });
    final period = _period();
    try {
      final admin = context.read<AdminService>();
      final nextSummary = reset
          ? await admin.raffleSummary(
              from: period.from, to: period.to, ticketPrice: ticketPrice)
          : summary;
      final page = await admin.raffleParticipants(
          from: period.from,
          to: period.to,
          ticketPrice: ticketPrice,
          cursor: reset ? null : cursor);
      if (!mounted || currentGeneration != generation) return;
      setState(() {
        summary = nextSummary;
        items.addAll((page['items'] as List)
            .map((value) => Map<String, dynamic>.from(value as Map)));
        cursor = page['nextCursor'] as String?;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Future<void> _export(String format) async {
    final ticketPrice = _validTicketPrice;
    if (startDate == null ||
        endDate == null ||
        ticketPrice == null ||
        exporting) {
      return;
    }
    setState(() => exporting = true);
    String? temporaryPath;
    try {
      final period = _period();
      final admin = context.read<AdminService>();
      final fileName = format == 'tickets'
          ? 'raffle-tickets.csv'
          : 'raffle-participants.csv';
      if (kIsWeb) {
        final bytes = await admin.raffleExport(
            from: period.from,
            to: period.to,
            ticketPrice: ticketPrice,
            format: format);
        csv_download.downloadRaffleCsv(bytes, fileName);
      } else {
        temporaryPath = await admin.raffleExportToFile(
            from: period.from,
            to: period.to,
            ticketPrice: ticketPrice,
            format: format);
        await SharePlus.instance.share(ShareParams(files: [
          XFile(temporaryPath, mimeType: 'text/csv', name: fileName),
        ]));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка выгрузки: $e')));
      }
    } finally {
      if (temporaryPath != null) {
        try {
          await File(temporaryPath).delete();
        } catch (_) {}
      }
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return Scaffold(
      appBar: AppBar(title: const Text('Участники розыгрыша')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _priceController,
          keyboardType: TextInputType.number,
          readOnly: exporting,
          onChanged: _priceChanged,
          decoration: InputDecoration(
            labelText: 'Цена одного билета, ₽',
            border: const OutlineInputBorder(),
            errorText: _priceError,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: Text(
                  'Дата начала: ${startDate == null ? 'выбрать' : _date(startDate!)}'),
              onPressed: () => _pickDate(start: true),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(
                  'Дата окончания: ${endDate == null ? 'выбрать' : _date(endDate!)}'),
              onPressed: () => _pickDate(start: false),
            ),
          ],
        ),
        if (_validTicketPrice != null)
          ListTile(title: Text('1 билет = $_validTicketPrice ₽')),
        FilledButton(
            onPressed: startDate == null ||
                    endDate == null ||
                    _validTicketPrice == null ||
                    loading
                ? null
                : () => _load(reset: true),
            child: const Text('Показать участников')),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(
              icon: const Icon(Icons.download),
              onPressed: startDate == null ||
                      endDate == null ||
                      _validTicketPrice == null ||
                      exporting
                  ? null
                  : () => _export('participants'),
              label: const Text('Скачать участников CSV')),
          OutlinedButton.icon(
              icon: const Icon(Icons.print),
              onPressed: startDate == null ||
                      endDate == null ||
                      _validTicketPrice == null ||
                      exporting
                  ? null
                  : () => _export('tickets'),
              label: const Text('Скачать билеты для печати CSV')),
        ]),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          Text(error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (s != null) ...[
          Wrap(spacing: 16, children: [
            Chip(label: Text('Цена билета: ${s['ticketPriceRub']} ₽')),
            Chip(label: Text('Уникальных участников: ${s['participants']}')),
            Chip(label: Text('Всего билетов: ${s['tickets']}')),
            Chip(label: Text('Пополнения участников: ${s['amountRub']} ₽')),
          ]),
          if (items.isEmpty && !loading)
            const Center(child: Text('Участники не найдены')),
          for (var i = 0; i < items.length; i++)
            Card(
                child: ListTile(
              title:
                  Text('${i + 1}. ${items[i]['name']} — ${items[i]['phone']}'),
              subtitle: Text(
                  '${items[i]['totalRub']} ₽ · ${items[i]['tickets']} билетов · остаток ${items[i]['remainderRub']} ₽\n'
                  'Первое: ${items[i]['firstAt']} · Последнее: ${items[i]['lastAt']}'),
            )),
          if (cursor != null)
            OutlinedButton(
                onPressed: loading ? null : () => _load(),
                child: const Text('Показать ещё')),
        ],
      ]),
    );
  }
}
