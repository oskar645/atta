import 'dart:async';
import 'dart:io';

import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/widgets/standard_search_surface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/moscow_calendar.dart';

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
  final TextEditingController _searchController = TextEditingController();
  final List<Map<String, dynamic>> _participants = [];
  final List<Map<String, dynamic>> _tickets = [];
  final List<String?> _ticketHistory = [];

  DateTime? startDate;
  DateTime? endDate;
  Map<String, dynamic>? summary;
  String? _participantCursor;
  String? _ticketPageCursor;
  String? _ticketNextCursor;
  String? _snapshotId;
  String _view = 'participants';
  String? error;
  bool loading = false;
  bool _ticketsLoading = false;
  bool exporting = false;
  int generation = 0;
  int _ticketRequest = 0;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    startDate = widget.initialRange?.start;
    endDate = widget.initialRange?.end;
    if (widget.initialRange == null) unawaited(_restoreParameters());
  }

  Future<void> _restoreParameters() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    final start =
        DateTime.tryParse(preferences.getString('admin.raffle.start') ?? '');
    final end =
        DateTime.tryParse(preferences.getString('admin.raffle.end') ?? '');
    final price = preferences.getString('admin.raffle.price');
    setState(() {
      startDate = start;
      endDate = end;
      if (price != null && RegExp(r'^[1-9][0-9]*$').hasMatch(price)) {
        _priceController.text = price;
      }
    });
  }

  Future<void> _saveParameters() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
        'admin.raffle.price', _priceController.text.trim());
    if (startDate != null) {
      await preferences.setString(
          'admin.raffle.start', startDate!.toIso8601String());
    }
    if (endDate != null) {
      await preferences.setString(
          'admin.raffle.end', endDate!.toIso8601String());
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _priceController.dispose();
    _searchController.dispose();
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

  bool get _canQuery =>
      startDate != null && endDate != null && _validTicketPrice != null;

  void _resetCalculated() {
    generation += 1;
    summary = null;
    _participants.clear();
    _tickets.clear();
    _participantCursor = null;
    _ticketPageCursor = null;
    _ticketNextCursor = null;
    _ticketHistory.clear();
    _snapshotId = null;
    _ticketRequest += 1;
    loading = false;
    _ticketsLoading = false;
    error = null;
  }

  void _priceChanged(String _) {
    setState(_resetCalculated);
    unawaited(_saveParameters());
  }

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';

  String _dateTime(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    return parsed == null ? '—' : _date(parsed);
  }

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
      if (start) {
        startDate = selected;
        if (endDate != null && endDate!.isBefore(selected)) endDate = null;
      } else {
        endDate = selected;
      }
      _resetCalculated();
    });
    unawaited(_saveParameters());
  }

  ({String from, String to}) _period() => (
        from: moscowDateStartUtc(startDate!).toIso8601String(),
        to: moscowDateEndUtc(endDate!).toIso8601String(),
      );

  Future<void> _load({bool reset = false}) async {
    final ticketPrice = _validTicketPrice;
    if (!_canQuery ||
        ticketPrice == null ||
        loading ||
        (!reset && _participantCursor == null)) {
      return;
    }
    final currentGeneration = reset ? ++generation : generation;
    final retainedSummary = _snapshotId != null ? summary : null;
    setState(() {
      loading = true;
      error = null;
      if (reset) {
        _participants.clear();
        _tickets.clear();
        summary = null;
        _participantCursor = null;
        _ticketPageCursor = null;
        _ticketNextCursor = null;
        _ticketHistory.clear();
      }
    });
    final period = _period();
    try {
      final admin = context.read<AdminService>();
      final nextSummary = reset && _snapshotId == null
          ? await admin.raffleSummary(
              from: period.from, to: period.to, ticketPrice: ticketPrice)
          : (retainedSummary ?? summary);
      final page = _snapshotId == null
          ? await admin.raffleParticipants(
              from: period.from,
              to: period.to,
              ticketPrice: ticketPrice,
              cursor: reset ? null : _participantCursor)
          : await admin.raffleSnapshotParticipants(
              snapshotId: _snapshotId!,
              cursor: reset ? null : _participantCursor);
      if (!mounted || currentGeneration != generation) return;
      setState(() {
        summary = nextSummary;
        _participants.addAll((page['items'] as List)
            .map((value) => Map<String, dynamic>.from(value as Map)));
        _participantCursor = page['nextCursor'] as String?;
        loading = false;
      });
      if (_view == 'tickets' && mounted) {
        await _loadTicketPage(resetHistory: true);
      }
    } catch (exception) {
      if (!mounted || currentGeneration != generation) return;
      setState(() {
        error = exception.toString();
        loading = false;
      });
    }
  }

  Future<void> _loadTicketPage({
    String? cursor,
    bool resetHistory = false,
  }) async {
    final ticketPrice = _validTicketPrice;
    if (summary == null || ticketPrice == null) return;
    final currentGeneration = generation;
    final request = ++_ticketRequest;
    setState(() {
      _ticketsLoading = true;
      error = null;
      if (resetHistory) _ticketHistory.clear();
    });
    final period = _period();
    try {
      final search = _searchController.text;
      final admin = context.read<AdminService>();
      final page = _snapshotId == null
          ? await admin.raffleTickets(
              from: period.from,
              to: period.to,
              ticketPrice: ticketPrice,
              cursor: cursor,
              search: search)
          : await admin.raffleSnapshotTickets(
              snapshotId: _snapshotId!, cursor: cursor, search: search);
      if (!mounted ||
          currentGeneration != generation ||
          request != _ticketRequest) {
        return;
      }
      setState(() {
        _tickets
          ..clear()
          ..addAll((page['items'] as List)
              .map((value) => Map<String, dynamic>.from(value as Map)));
        _ticketPageCursor = cursor;
        _ticketNextCursor = page['nextCursor'] as String?;
        _ticketsLoading = false;
      });
    } catch (exception) {
      if (!mounted ||
          currentGeneration != generation ||
          request != _ticketRequest) {
        return;
      }
      setState(() {
        error = exception.toString();
        _ticketsLoading = false;
      });
    }
  }

  Future<void> _freeze() async {
    if (!_canQuery || loading || exporting) return;
    final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Зафиксировать розыгрыш?'),
              content: const Text(
                  'Цена, период, участники и номера билетов станут неизменяемым снимком.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Отмена')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Зафиксировать')),
              ],
            ));
    if (approved != true || !mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final period = _period();
      final fixed = await context.read<AdminService>().freezeRaffle(
          from: period.from, to: period.to, ticketPrice: _validTicketPrice!);
      if (!mounted) return;
      setState(() {
        _snapshotId = fixed['snapshotId'] as String;
        summary = fixed;
        loading = false;
        _participants.clear();
        _participantCursor = null;
      });
      await _load(reset: true);
    } catch (exception) {
      if (mounted) {
        setState(() {
          error = exception.toString();
          loading = false;
        });
      }
    }
  }

  void _searchChanged(String _) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted && summary != null) {
        _loadTicketPage(resetHistory: true);
      }
    });
  }

  Future<void> _nextTicketPage() async {
    final next = _ticketNextCursor;
    if (next == null) return;
    _ticketHistory.add(_ticketPageCursor);
    await _loadTicketPage(cursor: next);
  }

  Future<void> _previousTicketPage() async {
    if (_ticketHistory.isEmpty) return;
    final previous = _ticketHistory.removeLast();
    await _loadTicketPage(cursor: previous);
  }

  Future<void> _exportCsv(String format) async {
    final ticketPrice = _validTicketPrice;
    if (_snapshotId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Сначала зафиксируйте розыгрыш для стабильной выгрузки'),
      ));
      return;
    }
    if (!_canQuery || ticketPrice == null || exporting) return;
    setState(() => exporting = true);
    String? temporaryPath;
    try {
      final period = _period();
      final admin = context.read<AdminService>();
      final fileName = format == 'tickets'
          ? 'raffle-tickets.csv'
          : 'raffle-participants.csv';
      if (kIsWeb) {
        final bytes = _snapshotId == null
            ? await admin.raffleExport(
                from: period.from,
                to: period.to,
                ticketPrice: ticketPrice,
                format: format,
              )
            : await admin.raffleSnapshotExport(
                snapshotId: _snapshotId!, format: format);
        csv_download.downloadRaffleCsv(bytes, fileName);
      } else {
        temporaryPath = _snapshotId == null
            ? await admin.raffleExportToFile(
                from: period.from,
                to: period.to,
                ticketPrice: ticketPrice,
                format: format,
              )
            : await admin.raffleSnapshotExportToFile(
                snapshotId: _snapshotId!, format: format);
        await SharePlus.instance.share(ShareParams(files: [
          XFile(temporaryPath, mimeType: 'text/csv', name: fileName),
        ]));
      }
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка выгрузки: $exception')),
        );
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

  Future<void> _printPdf() async {
    final ticketPrice = _validTicketPrice;
    if (_snapshotId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Сначала зафиксируйте розыгрыш для печати'),
      ));
      return;
    }
    if (!_canQuery || ticketPrice == null || exporting) return;
    setState(() => exporting = true);
    String? temporaryPath;
    try {
      final period = _period();
      final admin = context.read<AdminService>();
      final total = int.tryParse('${summary?['tickets']}') ?? 0;
      String? rangeFrom;
      String? rangeTo;
      if (total > 10000) {
        final fromController = TextEditingController(text: '1');
        final toController = TextEditingController(text: '10000');
        final range = await showDialog<(String, String)>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Диапазон для PDF'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('В одном файле не более 10 000 билетов. Всего: $total.'),
              TextField(
                  controller: fromController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'С билета')),
              TextField(
                  controller: toController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'По билет')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Отмена')),
              FilledButton(
                  onPressed: () => Navigator.pop(context,
                      (fromController.text.trim(), toController.text.trim())),
                  child: const Text('Подготовить PDF')),
            ],
          ),
        );
        fromController.dispose();
        toController.dispose();
        if (range == null || !mounted) return;
        rangeFrom = range.$1;
        rangeTo = range.$2;
      }
      if (kIsWeb) {
        final bytes = rangeFrom != null
            ? await admin.rafflePrintPdfRange(
                from: period.from,
                to: period.to,
                ticketPrice: ticketPrice,
                fromTicket: rangeFrom,
                toTicket: rangeTo!,
                snapshotId: _snapshotId)
            : _snapshotId == null
                ? await admin.rafflePrintPdf(
                    from: period.from,
                    to: period.to,
                    ticketPrice: ticketPrice,
                  )
                : await admin.raffleSnapshotPrintPdf(snapshotId: _snapshotId!);
        csv_download.downloadRaffleCsv(
          bytes,
          'raffle-tickets.pdf',
          mimeType: 'application/pdf',
        );
      } else {
        temporaryPath = rangeFrom != null
            ? await admin.rafflePrintPdfRangeToFile(
                from: period.from,
                to: period.to,
                ticketPrice: ticketPrice,
                fromTicket: rangeFrom,
                toTicket: rangeTo!,
                snapshotId: _snapshotId)
            : _snapshotId == null
                ? await admin.rafflePrintPdfToFile(
                    from: period.from,
                    to: period.to,
                    ticketPrice: ticketPrice,
                  )
                : await admin.raffleSnapshotPrintPdfToFile(
                    snapshotId: _snapshotId!);
        await SharePlus.instance.share(ShareParams(files: [
          XFile(temporaryPath,
              mimeType: 'application/pdf', name: 'raffle-tickets.pdf'),
        ]));
      }
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка PDF: $exception')),
        );
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

  Future<void> _copyVisible() async {
    final lines = _view == 'tickets'
        ? _tickets.map((item) =>
            'Билет №${item['ticketNumber']} — ${item['name']} — ${item['phone']}')
        : _participants.map((item) =>
            '${item['name']} — ${item['phone']} — ${item['tickets']} билетов');
    final value = lines.join('\n');
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Текущий список скопирован')),
      );
    }
  }

  Future<void> _copyTicketRange() async {
    if (summary == null) return;
    final range = await showDialog<(int, int)>(
        context: context,
        builder: (context) => _TicketRangeDialog(
              maximumTicket: int.tryParse('${summary?['tickets']}') ?? 0,
            ));
    if (range == null || !mounted) return;
    setState(() => exporting = true);
    try {
      final period = _period();
      final admin = context.read<AdminService>();
      var cursor = '${range.$1 - 1}';
      final seenCursors = <String>{};
      final lines = <String>[];
      while (seenCursors.add(cursor)) {
        final page = _snapshotId == null
            ? await admin.raffleTickets(
                from: period.from,
                to: period.to,
                ticketPrice: _validTicketPrice!,
                limit: 100,
                cursor: cursor)
            : await admin.raffleSnapshotTickets(
                snapshotId: _snapshotId!, limit: 100, cursor: cursor);
        final items = (page['items'] as List).cast<Map>();
        for (final item in items) {
          final number = int.parse('${item['ticketNumber']}');
          if (number > range.$2) break;
          lines.add('Билет №$number — ${item['name']} — ${item['phone']}');
        }
        final next = page['nextCursor'] as String?;
        if (next == null || int.parse(next) >= range.$2) break;
        cursor = next;
      }
      if (lines.length != range.$2 - range.$1 + 1) {
        throw StateError('Не удалось получить весь выбранный диапазон');
      }
      await Clipboard.setData(ClipboardData(text: lines.join('\n')));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Скопировано билетов: ${lines.length}')),
        );
      }
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка копирования: $exception')),
        );
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final s = summary;
    return Scaffold(
      appBar: AppBar(title: const Text('Участники розыгрыша')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Параметры розыгрыша',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                const SizedBox(height: 14),
                TextField(
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  readOnly: exporting,
                  onChanged: _priceChanged,
                  decoration: InputDecoration(
                    labelText: 'Цена одного билета, ₽',
                    prefixIcon: const Icon(Icons.confirmation_number_outlined),
                    border: const OutlineInputBorder(),
                    errorText: _priceError,
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: _DateButton(
                      label: 'Дата начала',
                      value: startDate == null ? 'Выбрать' : _date(startDate!),
                      icon: Icons.calendar_today_outlined,
                      onPressed: () => _pickDate(start: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DateButton(
                      label: 'Дата окончания',
                      value: endDate == null ? 'Выбрать' : _date(endDate!),
                      icon: Icons.event_outlined,
                      onPressed: () => _pickDate(start: false),
                    ),
                  ),
                ]),
                if (_validTicketPrice != null) ...[
                  const SizedBox(height: 10),
                  Text('1 билет = $_validTicketPrice ₽',
                      style: TextStyle(color: colors.onSurfaceVariant)),
                ],
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed:
                      !_canQuery || loading ? null : () => _load(reset: true),
                  icon: const Icon(Icons.calculate_outlined),
                  label: const Text('Показать участников'),
                ),
              ],
            ),
          ),
          if (loading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: TextStyle(color: colors.error)),
          ],
          if (s != null) ...[
            const SizedBox(height: 14),
            LayoutBuilder(builder: (context, constraints) {
              final width = (constraints.maxWidth - 16) / 3;
              return Wrap(spacing: 8, runSpacing: 8, children: [
                _StatCard(
                    width: width,
                    label: 'Участники',
                    value: '${s['participants']}',
                    icon: Icons.people_alt_outlined),
                _StatCard(
                    width: width,
                    label: 'Всего билетов',
                    value: '${s['tickets']}',
                    icon: Icons.confirmation_number_outlined),
                _StatCard(
                    width: width,
                    label: 'Сумма',
                    value: '${s['amountRub']} ₽',
                    icon: Icons.payments_outlined),
              ]);
            }),
            const SizedBox(height: 12),
            _PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Выгрузка и печать',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          )),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (_snapshotId == null)
                      FilledButton.icon(
                        onPressed: loading || exporting ? null : _freeze,
                        icon: const Icon(Icons.lock_outline),
                        label: const Text('Зафиксировать'),
                      )
                    else
                      const Chip(
                        avatar: Icon(Icons.verified_outlined, size: 18),
                        label: Text('Розыгрыш зафиксирован'),
                      ),
                    OutlinedButton.icon(
                      onPressed: exporting ? null : () => _exportCsv('tickets'),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Скачать список'),
                    ),
                    OutlinedButton.icon(
                      onPressed: exporting ? null : _printPdf,
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Печать PDF'),
                    ),
                    OutlinedButton.icon(
                      onPressed: exporting ? null : _copyVisible,
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('Копировать'),
                    ),
                    OutlinedButton.icon(
                      onPressed: exporting ? null : _copyTicketRange,
                      icon: const Icon(Icons.content_copy_outlined),
                      label: const Text('Копировать диапазон'),
                    ),
                    OutlinedButton.icon(
                      onPressed: exporting ? null : () => _exportCsv('tickets'),
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Поделиться'),
                    ),
                    TextButton.icon(
                      onPressed:
                          exporting ? null : () => _exportCsv('participants'),
                      icon: const Icon(Icons.group_outlined),
                      label: const Text('Скачать участников CSV'),
                    ),
                  ]),
                  if (exporting) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'participants',
                    icon: Icon(Icons.people_outline),
                    label: Text('Участники')),
                ButtonSegment(
                    value: 'tickets',
                    icon: Icon(Icons.confirmation_number_outlined),
                    label: Text('Все билеты')),
              ],
              selected: {_view},
              onSelectionChanged: (value) {
                final selected = value.first;
                setState(() => _view = selected);
                if (selected == 'tickets' && _tickets.isEmpty) {
                  _loadTicketPage(resetHistory: true);
                }
              },
            ),
            const SizedBox(height: 12),
            if (_view == 'tickets') ...[
              StandardSearchSurface(
                child: TextField(
                  controller: _searchController,
                  onChanged: _searchChanged,
                  decoration: InputDecoration(
                    hintText: 'Поиск по имени, телефону или № билета',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Очистить',
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                              _loadTicketPage(resetHistory: true);
                            },
                            icon: const Icon(Icons.close),
                          ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (_ticketsLoading)
                const Center(child: CircularProgressIndicator())
              else if (_tickets.isEmpty)
                const _EmptyCard(text: 'Билеты не найдены')
              else
                for (final ticket in _tickets)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: 1,
                    shadowColor: colors.shadow.withAlpha(24),
                    color: colors.surfaceContainerLow,
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text('#${ticket['ticketNumber']}'),
                      ),
                      title: Text('${ticket['name']}',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${ticket['phone']}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Билет №${ticket['ticketNumber']}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          IconButton(
                            tooltip: 'Копировать билет',
                            onPressed: () => Clipboard.setData(ClipboardData(
                              text:
                                  'Билет №${ticket['ticketNumber']} — ${ticket['name']} — ${ticket['phone']}',
                            )),
                            icon: const Icon(Icons.copy_outlined),
                          ),
                        ],
                      ),
                    ),
                  ),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _ticketHistory.isEmpty || _ticketsLoading
                        ? null
                        : _previousTicketPage,
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('Назад'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _ticketNextCursor == null || _ticketsLoading
                        ? null
                        : _nextTicketPage,
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('Дальше'),
                  ),
                ),
              ]),
            ] else ...[
              if (_participants.isEmpty && !loading)
                const _EmptyCard(text: 'Участники не найдены'),
              for (var index = 0; index < _participants.length; index++)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 1,
                  shadowColor: colors.shadow.withAlpha(24),
                  color: colors.surfaceContainerLow,
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text('${_participants[index]['name']}'),
                    subtitle: Text(
                      '${_participants[index]['phone']}\n'
                      '${_participants[index]['totalRub']} ₽ · '
                      '${_participants[index]['tickets']} билетов · '
                      'остаток ${_participants[index]['remainderRub']} ₽\n'
                      '${_dateTime(_participants[index]['firstAt'])} — '
                      '${_dateTime(_participants[index]['lastAt'])}',
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: 'Копировать участника',
                      onPressed: () => Clipboard.setData(ClipboardData(
                        text:
                            '${_participants[index]['name']} — ${_participants[index]['phone']} — ${_participants[index]['tickets']} билетов',
                      )),
                      icon: const Icon(Icons.copy_outlined),
                    ),
                  ),
                ),
              if (_participantCursor != null)
                OutlinedButton(
                  onPressed: loading ? null : () => _load(),
                  child: const Text('Показать ещё'),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _TicketRangeDialog extends StatefulWidget {
  const _TicketRangeDialog({required this.maximumTicket});

  final int maximumTicket;

  @override
  State<_TicketRangeDialog> createState() => _TicketRangeDialogState();
}

class _TicketRangeDialogState extends State<_TicketRangeDialog> {
  final _fromController = TextEditingController(text: '1');
  final _toController = TextEditingController(text: '1');
  String? _error;

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  void _submit() {
    final from = int.tryParse(_fromController.text.trim());
    final to = int.tryParse(_toController.text.trim());
    if (from == null ||
        to == null ||
        from < 1 ||
        to < from ||
        to - from + 1 > 500 ||
        to > widget.maximumTicket) {
      setState(() =>
          _error = 'Укажите до 500 билетов в пределах текущего розыгрыша');
      return;
    }
    Navigator.pop(context, (from, to));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Копировать билеты'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Для буфера обмена можно выбрать до 500 билетов.'),
          TextField(
            controller: _fromController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'С билета'),
          ),
          TextField(
            controller: _toController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'По билет',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: _submit,
            child: const Text('Копировать'),
          ),
        ],
      );
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 1,
        shadowColor: Theme.of(context).colorScheme.shadow.withAlpha(24),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
              color:
                  Theme.of(context).colorScheme.outlineVariant.withAlpha(90)),
        ),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
  });

  final double width;
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Card(
        elevation: 1,
        shadowColor: colors.shadow.withAlpha(30),
        color: colors.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 20, color: colors.primary),
            const SizedBox(height: 10),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    )),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: colors.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        child: Row(children: [
          Icon(icon, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Text(text,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
}
