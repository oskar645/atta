import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/top_banner.dart';
import '../../services/top_banners_service.dart';
import '../../widgets/media_preview_box.dart';

const double topBannerAspectRatio = 390 / 80;
const String topBannerRecommendedSize = '1170 × 240 px';

class AdminTopBannersTab extends StatefulWidget {
  const AdminTopBannersTab({super.key, this.pickImage});

  final Future<XFile?> Function()? pickImage;
  @override
  State<AdminTopBannersTab> createState() => _State();
}

class _State extends State<AdminTopBannersTab> {
  late Future<List<TopBanner>> future = load();
  Future<List<TopBanner>> load() => context.read<TopBannersService>().list();
  Future<void> reload() async {
    final items = await load();
    if (!mounted) return;
    setState(() {
      future = Future.value(items);
    });
  }

  Future<void> action(Future<void> Function() fn) async {
    try {
      await fn();
      await reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<TopBanner>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data ?? [];
        return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(12), children: [
              Row(children: [
                const Expanded(
                    child: Text(
                        'До 3 активных баннеров. Ротация — только при cold start.',
                        style: TextStyle(fontSize: 13))),
                FilledButton.icon(
                    onPressed: () => edit(),
                    icon: const Icon(Icons.add),
                    label: const Text('Создать'))
              ]),
              const SizedBox(height: 8),
              const Text(
                  'Рекомендуемый размер: $topBannerRecommendedSize · 4.88:1',
                  style: TextStyle(color: Colors.grey)),
              if (items.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: Text('Верхних баннеров пока нет'))),
              ...items.map(card),
            ]));
      });
  Widget card(TopBanner b) => Card(
      child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                    aspectRatio: topBannerAspectRatio,
                    child: b.imageUrl.isEmpty
                        ? const ColoredBox(
                            color: Color(0xffeeeeee),
                            child:
                                Center(child: Text('Изображение не загружено')))
                        : MediaPreviewBox(
                            imageUrl: b.imageUrl,
                            categoryHint: 'feed-ads',
                            borderRadius: 0,
                          ))),
            const SizedBox(height: 8),
            Text(b.title.isEmpty ? 'Без названия' : b.title,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${label(b.status)} · до ${fmt(b.endAt)}'),
            Text(
                'Показы: ${b.impressions}   Клики: ${b.clicks}   CTR: ${b.ctr.toStringAsFixed(1)}%'),
            Wrap(spacing: 6, children: [
              if (b.enabled)
                OutlinedButton(
                    onPressed: () => action(
                        () => context.read<TopBannersService>().stop(b.id)),
                    child: const Text('Остановить'))
              else
                FilledButton(
                    onPressed: () => action(
                        () => context.read<TopBannersService>().start(b.id)),
                    child: const Text('Запустить')),
              TextButton(
                  onPressed: () => edit(b), child: const Text('Изменить')),
              PopupMenuButton<int>(
                  tooltip: 'Продлить',
                  onSelected: (d) => action(() =>
                      context.read<TopBannersService>().extend(b.id, days: d)),
                  itemBuilder: (_) => [1, 3, 7, 30]
                      .map((d) => PopupMenuItem(
                          value: d, child: Text('Продлить на $d дн.')))
                      .toList()),
              TextButton(
                  onPressed: () => showStats(b),
                  child: const Text('Статистика')),
              IconButton(
                  tooltip: 'Удалить',
                  onPressed: () => action(
                      () => context.read<TopBannersService>().delete(b.id)),
                  icon: const Icon(Icons.delete_outline))
            ]),
          ])));
  String label(String s) =>
      {
        'active': 'Активен',
        'scheduled': 'Запланирован',
        'completed': 'Завершён',
        'paused': 'Приостановлен'
      }[s] ??
      'Черновик';
  String fmt(DateTime d) =>
      '${d.toLocal().day.toString().padLeft(2, '0')}.${d.toLocal().month.toString().padLeft(2, '0')}.${d.toLocal().year} ${d.toLocal().hour.toString().padLeft(2, '0')}:${d.toLocal().minute.toString().padLeft(2, '0')}';
  Future<void> edit([TopBanner? b]) async {
    final changed = await showDialog<bool>(
        context: context,
        builder: (_) => _Editor(
              existing: b,
              pickImage: widget.pickImage,
            ));
    if (changed == true && mounted) await reload();
  }

  Future<void> showStats(TopBanner banner) async {
    final stats = await context.read<TopBannersService>().stats(banner.id);
    if (!mounted) return;
    String row(String key, String title) {
      final value = Map<String, dynamic>.from(stats[key] as Map? ?? {});
      final impressions = value['impressions'] ?? 0;
      final clicks = value['clicks'] ?? 0;
      final ctr = ((value['ctr'] as num?) ?? 0).toStringAsFixed(1);
      return '$title: $impressions показов · $clicks кликов · CTR $ctr%';
    }

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Статистика · ${banner.title}'),
        content: Text([
          row('total', 'Всего'),
          row('today', 'Сегодня'),
          row('last_7_days', 'Последние 7 дней'),
          row('last_30_days', 'Последние 30 дней'),
        ].join('\n\n')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть'))
        ],
      ),
    );
  }
}

class _Editor extends StatefulWidget {
  const _Editor({this.existing, this.pickImage});
  final TopBanner? existing;
  final Future<XFile?> Function()? pickImage;
  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final title = TextEditingController(text: widget.existing?.title ?? '');
  late final url =
      TextEditingController(text: widget.existing?.targetUrl ?? '');
  late DateTime start = widget.existing?.startAt.toLocal() ?? DateTime.now();
  late DateTime end = widget.existing?.endAt.toLocal() ??
      DateTime.now().add(const Duration(days: 7));
  Uint8List? bytes;
  String name = 'banner.jpg', type = 'image/jpeg';
  bool busy = false, safe = true;
  Future<void> pick() async {
    final x = await (widget.pickImage?.call() ??
        ImagePicker().pickImage(source: ImageSource.gallery));
    if (x == null) return;
    final data = await x.readAsBytes();
    if (!mounted) return;
    if (data.length > 5 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Максимальный размер — 5 МБ')));
      }
      return;
    }
    setState(() {
      bytes = data;
      name = x.name;
      type = name.toLowerCase().endsWith('.png')
          ? 'image/png'
          : name.toLowerCase().endsWith('.webp')
              ? 'image/webp'
              : 'image/jpeg';
    });
  }

  Future<void> save() async {
    setState(() => busy = true);
    final service = context.read<TopBannersService>();
    try {
      var b = await service.save(
          existing: widget.existing,
          title: title.text,
          url: url.text,
          start: start,
          end: end,
          order: widget.existing?.sortOrder ?? 0);
      if (bytes != null) {
        await service.upload(b, bytes!, name, type);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<DateTime?> date(DateTime initial) async {
    final d = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime.now().subtract(const Duration(days: 1)),
        lastDate: DateTime.now().add(const Duration(days: 3650)));
    if (d == null) return null;
    if (!mounted) return null;
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(initial));
    return DateTime(d.year, d.month, d.day, t?.hour ?? initial.hour,
        t?.minute ?? initial.minute);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.existing == null
              ? 'Новый верхний баннер'
              : 'Изменить верхний баннер'),
          content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: title,
                    decoration:
                        const InputDecoration(labelText: 'Служебное название')),
                TextField(
                    controller: url,
                    decoration: const InputDecoration(
                        labelText: 'HTTPS-ссылка (необязательно)')),
                Row(children: [
                  Expanded(
                      child: TextButton(
                          onPressed: () async {
                            final v = await date(start);
                            if (v != null && mounted) {
                              setState(() => start = v);
                            }
                          },
                          child: Text('Начало: ${start.toLocal()}'))),
                  Expanded(
                      child: TextButton(
                          onPressed: () async {
                            final v = await date(end);
                            if (v != null && mounted) {
                              setState(() => end = v);
                            }
                          },
                          child: Text('Окончание: ${end.toLocal()}')))
                ]),
                Wrap(
                  spacing: 6,
                  children: [1, 2, 3, 7, 14, 30]
                      .map((days) => ActionChip(
                            label: Text('$days дн.'),
                            onPressed: () => setState(
                                () => end = start.add(Duration(days: days))),
                          ))
                      .toList(),
                ),
                OutlinedButton.icon(
                    onPressed: pick,
                    icon: const Icon(Icons.image),
                    label: Text(bytes == null
                        ? 'Выбрать изображение'
                        : 'Заменить изображение')),
                const Text(
                    'Рекомендуемый размер: $topBannerRecommendedSize · 4.88:1'),
                const SizedBox(height: 8),
                AspectRatio(
                    aspectRatio: topBannerAspectRatio,
                    child: Stack(fit: StackFit.expand, children: [
                      if (bytes != null)
                        Image.memory(bytes!, fit: BoxFit.cover)
                      else if (widget.existing?.imageUrl.isNotEmpty == true)
                        MediaPreviewBox(
                          imageUrl: widget.existing!.imageUrl,
                          categoryHint: 'feed-ads',
                          borderRadius: 0,
                        )
                      else
                        const ColoredBox(color: Color(0xffeeeeee)),
                      if (safe) const _TopBannerSafeZoneOverlay(),
                    ])),
                const SizedBox(height: 8),
                const Text(
                  '$topBannerRecommendedSize · Важный текст и логотипы размещайте в свободной центральной зоне. Не размещайте их под логотипом AT, камерой/Dynamic Island, статус-баром, колокольчиком и кнопкой +.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                SwitchListTile(
                    value: safe,
                    onChanged: (v) => setState(() => safe = v),
                    title: const Text('Показать safe zones'),
                    subtitle: const Text(
                        'Не размещайте важный текст и логотипы в отмеченных зонах')),
              ]))),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: busy ? null : save,
                child: Text(busy ? 'Сохранение…' : 'Сохранить'))
          ]);
}

class _TopBannerSafeZoneOverlay extends StatelessWidget {
  const _TopBannerSafeZoneOverlay();

  static const _shadow = <Shadow>[
    Shadow(color: Color(0x99000000), blurRadius: 2),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: 390,
            height: 80,
            child: Stack(
              children: [
                const Positioned(
                  left: 16,
                  top: 6,
                  child: Text(
                    '9:41',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      shadows: _shadow,
                    ),
                  ),
                ),
                Positioned(
                  left: 143,
                  top: 4,
                  child: Container(
                    width: 104,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xff111111),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const Positioned(
                  right: 13,
                  top: 6,
                  child: Row(
                    children: [
                      Icon(Icons.signal_cellular_alt,
                          color: Colors.white, size: 12, shadows: _shadow),
                      SizedBox(width: 2),
                      Text('LTE',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              shadows: _shadow)),
                      SizedBox(width: 2),
                      Icon(Icons.wifi,
                          color: Colors.white, size: 12, shadows: _shadow),
                      SizedBox(width: 2),
                      Icon(Icons.battery_full,
                          color: Colors.white, size: 14, shadows: _shadow),
                    ],
                  ),
                ),
                Positioned(
                  left: 14,
                  top: 34,
                  width: 58,
                  height: 36,
                  child: Image.asset(
                    'assets/branding/atta_logo.png',
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft,
                    semanticLabel: 'AT',
                  ),
                ),
                const Positioned(
                  right: 50,
                  top: 34,
                  child: CircleAvatar(
                    backgroundColor: Colors.white,
                    radius: 18,
                    child: Icon(Icons.notifications_outlined,
                        color: Colors.black87, size: 21),
                  ),
                ),
                const Positioned(
                  right: 10,
                  top: 34,
                  child: CircleAvatar(
                    backgroundColor: Colors.white,
                    radius: 18,
                    child: Icon(Icons.add, color: Colors.blue, size: 24),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
