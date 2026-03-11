import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:chestore2/src/models/feed_ad.dart';
import 'package:chestore2/src/services/feed_ads_service.dart';
import 'package:chestore2/src/utils/app_snackbar.dart';
import 'package:chestore2/src/widgets/feed_ad_banner.dart';

class AdminAdsTab extends StatelessWidget {
  const AdminAdsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final ads = context.read<FeedAdsService>();

    return StreamBuilder<List<FeedAd>>(
      stream: ads.streamAllAds(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Ошибка загрузки рекламы: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final items = snap.data!;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Реклама в ленте',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _openCreateDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Показывается только одна активная реклама. Новая активная запись автоматически выключает предыдущую. После окончания срока баннер сам исчезает с главной.',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Рекламы пока нет. Можно добавить баннер вручную.'),
                ),
              ),
            for (final ad in items) ...[
              _AdCard(ad: ad),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }

  Future<void> _openCreateDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _AdEditorDialog(),
    );
  }
}

class _AdCard extends StatelessWidget {
  final FeedAd ad;

  const _AdCard({required this.ad});

  String _statusLabel() {
    if (ad.isVisibleNow) return 'Активна';
    if (ad.isExpired) return 'Срок закончился';
    if (ad.isActive && ad.expiresAt == null) return 'Активна без срока';
    return 'Выключена';
  }

  Color _statusColor(BuildContext context) {
    if (ad.isVisibleNow) return Colors.green;
    if (ad.isExpired) return Colors.orange;
    return Theme.of(context).colorScheme.outline;
  }

  @override
  Widget build(BuildContext context) {
    final ads = context.read<FeedAdsService>();
    final expiresAt = ad.expiresAt?.toLocal();
    final activatedAt = ad.activatedAt?.toLocal();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FeedAdBanner(
              ad: ad,
              showBadge: true,
              onTap: ad.hasLink
                  ? () async {
                      final uri = Uri.tryParse(ad.targetUrl);
                      if (uri == null) return;
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  : null,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetaPill(
                  label: _statusLabel(),
                  color: _statusColor(context),
                ),
                _MetaPill(label: '${ad.durationDays} дн.'),
                if (activatedAt != null)
                  _MetaPill(
                    label:
                        'Старт ${activatedAt.day.toString().padLeft(2, '0')}.${activatedAt.month.toString().padLeft(2, '0')}.${activatedAt.year}',
                  ),
                if (expiresAt != null)
                  _MetaPill(
                    label:
                        'До ${expiresAt.day.toString().padLeft(2, '0')}.${expiresAt.month.toString().padLeft(2, '0')}.${expiresAt.year}',
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (ad.targetUrl.trim().isNotEmpty)
              SelectableText(
                ad.targetUrl,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () async {
                    try {
                      await ads.activateAd(ad.id);
                      if (!context.mounted) return;
                      showAppSnack(context, 'Реклама включена');
                    } catch (e) {
                      if (!context.mounted) return;
                      showAppSnack(context, 'Ошибка: $e', isError: true);
                    }
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Включить'),
                ),
                OutlinedButton.icon(
                  onPressed: ad.isActive
                      ? () async {
                          try {
                            await ads.deactivateAd(ad.id);
                            if (!context.mounted) return;
                            showAppSnack(context, 'Реклама выключена');
                          } catch (e) {
                            if (!context.mounted) return;
                            showAppSnack(context, 'Ошибка: $e', isError: true);
                          }
                        }
                      : null,
                  icon: const Icon(Icons.pause),
                  label: const Text('Выключить'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await showDialog<void>(
                      context: context,
                      builder: (_) => _AdEditorDialog(existing: ad),
                    );
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('Изменить'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final shouldDelete = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Удалить рекламу'),
                        content: const Text('Запись будет удалена полностью.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Отмена'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Удалить'),
                          ),
                        ],
                      ),
                    );
                    if (shouldDelete != true || !context.mounted) return;
                    try {
                      await ads.deleteAd(ad.id);
                      if (!context.mounted) return;
                      showAppSnack(context, 'Реклама удалена');
                    } catch (e) {
                      if (!context.mounted) return;
                      showAppSnack(context, 'Ошибка: $e', isError: true);
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Удалить'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final String label;
  final Color? color;

  const _MetaPill({
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final bg = (color ?? Theme.of(context).colorScheme.surfaceContainerHighest)
        .withValues(alpha: color == null ? 1 : 0.12);
    final fg = color ?? Theme.of(context).colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _AdEditorDialog extends StatefulWidget {
  final FeedAd? existing;

  const _AdEditorDialog({this.existing});

  @override
  State<_AdEditorDialog> createState() => _AdEditorDialogState();
}

class _AdEditorDialogState extends State<_AdEditorDialog> {
  static const List<int> _durations = [1, 2, 5, 10, 15, 20, 30];
  final ImagePicker _picker = ImagePicker();

  late final TextEditingController _titleCtrl =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _imageCtrl =
      TextEditingController(text: widget.existing?.imageUrl ?? '');
  late final TextEditingController _linkCtrl =
      TextEditingController(text: widget.existing?.targetUrl ?? '');
  late int _durationDays = widget.existing?.durationDays ?? 10;
  bool _saving = false;
  bool _uploadingImage = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _imageCtrl.dispose();
    _linkCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final imageUrl = _imageCtrl.text.trim();
    final targetUrl = _linkCtrl.text.trim();

    if (imageUrl.isEmpty) {
      showAppSnack(context, 'Укажи ссылку на картинку', isError: true);
      return;
    }

    final imageUri = Uri.tryParse(imageUrl);
    if (imageUri == null || !(imageUri.hasScheme && imageUri.hasAuthority)) {
      showAppSnack(context, 'Ссылка на картинку некорректна', isError: true);
      return;
    }

    if (targetUrl.isNotEmpty) {
      final targetUri = Uri.tryParse(targetUrl);
      if (targetUri == null || !(targetUri.hasScheme && targetUri.hasAuthority)) {
        showAppSnack(context, 'Ссылка перехода некорректна', isError: true);
        return;
      }
    }

    final ads = context.read<FeedAdsService>();
    setState(() => _saving = true);
    try {
      if (widget.existing == null) {
        await ads.createAd(
          FeedAd.createDraft(
            title: title,
            imageUrl: imageUrl,
            targetUrl: targetUrl,
            durationDays: _durationDays,
          ),
        );
      } else {
        await ads.updateAd(
          adId: widget.existing!.id,
          title: title,
          imageUrl: imageUrl,
          targetUrl: targetUrl,
          durationDays: _durationDays,
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
      showAppSnack(context, widget.existing == null ? 'Реклама добавлена' : 'Реклама обновлена');
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Ошибка: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked == null || !mounted) return;

    try {
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      final edited = await Navigator.of(context).push<_EditedAdImage>(
        MaterialPageRoute(
          builder: (_) => _AdImageEditorScreen(initialBytes: bytes),
          fullscreenDialog: true,
        ),
      );
      if (edited == null || !mounted) return;

      final ads = context.read<FeedAdsService>();
      setState(() => _uploadingImage = true);
      final url = await ads.uploadAdImage(
        bytes: edited.bytes,
        contentType: edited.contentType,
      );

      _imageCtrl.text = url;
      setState(() {});
      showAppSnack(context, 'Картинка загружена');
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Не удалось загрузить картинку: $e', isError: true);
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _showImageSourcePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Выбрать из галереи'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAndUploadImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Снять на камеру'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAndUploadImage(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = FeedAd.createDraft(
      title: _titleCtrl.text.trim(),
      imageUrl: _imageCtrl.text.trim(),
      targetUrl: _linkCtrl.text.trim(),
      durationDays: _durationDays,
    );

    return AlertDialog(
      title: Text(widget.existing == null ? 'Новая реклама' : 'Изменить рекламу'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Заголовок',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _imageCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ссылка на картинку',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        (_saving || _uploadingImage) ? null : _showImageSourcePicker,
                    icon: _uploadingImage
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(
                      _uploadingImage
                          ? 'Загружаем...'
                          : 'Выбрать фото с телефона',
                    ),
                  ),
                  if (_imageCtrl.text.trim().isNotEmpty)
                    TextButton(
                      onPressed: (_saving || _uploadingImage)
                          ? null
                          : () {
                              _imageCtrl.clear();
                              setState(() {});
                            },
                      child: const Text('Очистить'),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Можно оставить ссылку вручную или загрузить свою картинку из галереи/камеры.',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _linkCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ссылка при нажатии',
                  hintText: 'Можно оставить пустой',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _durationDays,
                items: _durations
                    .map((d) => DropdownMenuItem<int>(value: d, child: Text('$d дней')))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _durationDays = value);
                },
                decoration: const InputDecoration(
                  labelText: 'Срок показа',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Предпросмотр',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              FeedAdBanner(ad: preview, showBadge: true),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: (_saving || _uploadingImage) ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: (_saving || _uploadingImage) ? null : _save,
          child: Text(_saving ? 'Сохраняем...' : 'Сохранить'),
        ),
      ],
    );
  }
}

class _EditedAdImage {
  final Uint8List bytes;
  final String contentType;

  const _EditedAdImage({
    required this.bytes,
    required this.contentType,
  });
}

class _AdImageEditorScreen extends StatefulWidget {
  final Uint8List initialBytes;

  const _AdImageEditorScreen({
    required this.initialBytes,
  });

  @override
  State<_AdImageEditorScreen> createState() => _AdImageEditorScreenState();
}

class _AdImageEditorScreenState extends State<_AdImageEditorScreen> {
  static const double _bannerAspectRatio = 2.15;
  static const double _maxScale = 4.0;

  final TransformationController _controller = TransformationController();
  ui.Image? _image;
  Size? _viewportSize;
  Size? _baseImageSize;
  bool _busy = true;
  bool _exporting = false;
  bool _initialMatrixApplied = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    final codec = await ui.instantiateImageCodec(widget.initialBytes);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() {
      _image = frame.image;
      _busy = false;
    });
  }

  void _maybeInitMatrix(Size viewport) {
    final image = _image;
    if (image == null) return;

    final coverScale = _coverScale(
      imageSize: Size(image.width.toDouble(), image.height.toDouble()),
      viewport: viewport,
    );
    final fittedSize = Size(
      image.width * coverScale,
      image.height * coverScale,
    );

    final viewportChanged = _viewportSize != viewport || _baseImageSize != fittedSize;
    _viewportSize = viewport;
    _baseImageSize = fittedSize;

    if (_initialMatrixApplied && !viewportChanged) return;

    final dx = (viewport.width - fittedSize.width) / 2;
    final dy = (viewport.height - fittedSize.height) / 2;
    _controller.value = Matrix4.identity()..translate(dx, dy);
    _initialMatrixApplied = true;
  }

  double _coverScale({
    required Size imageSize,
    required Size viewport,
  }) {
    final scaleX = viewport.width / imageSize.width;
    final scaleY = viewport.height / imageSize.height;
    return scaleX > scaleY ? scaleX : scaleY;
  }

  void _resetImagePosition() {
    final viewport = _viewportSize;
    if (viewport == null) return;
    _initialMatrixApplied = false;
    setState(() {
      _maybeInitMatrix(viewport);
    });
  }

  Matrix4 _clampMatrix(Matrix4 next) {
    final viewport = _viewportSize;
    final child = _baseImageSize;
    if (viewport == null || child == null) return next;

    final scale = next.storage[0].clamp(1.0, _maxScale);
    final scaledWidth = child.width * scale;
    final scaledHeight = child.height * scale;

    double minX;
    double maxX;
    if (scaledWidth <= viewport.width) {
      minX = maxX = (viewport.width - scaledWidth) / 2;
    } else {
      minX = viewport.width - scaledWidth;
      maxX = 0;
    }

    double minY;
    double maxY;
    if (scaledHeight <= viewport.height) {
      minY = maxY = (viewport.height - scaledHeight) / 2;
    } else {
      minY = viewport.height - scaledHeight;
      maxY = 0;
    }

    final tx = next.storage[12].clamp(minX, maxX);
    final ty = next.storage[13].clamp(minY, maxY);

    return Matrix4.identity()
      ..translate(tx, ty)
      ..scale(scale);
  }

  Future<void> _applyCrop() async {
    final image = _image;
    final viewport = _viewportSize;
    final child = _baseImageSize;
    if (image == null || viewport == null || child == null) return;

    setState(() => _exporting = true);
    try {
      final matrix = _clampMatrix(_controller.value.clone());
      final scale = matrix.storage[0];
      final tx = matrix.storage[12];
      final ty = matrix.storage[13];

      final visibleScene = Rect.fromLTWH(
        (-tx / scale).clamp(0.0, child.width),
        (-ty / scale).clamp(0.0, child.height),
        (viewport.width / scale).clamp(0.0, child.width),
        (viewport.height / scale).clamp(0.0, child.height),
      );

      final srcRect = Rect.fromLTWH(
        visibleScene.left * image.width / child.width,
        visibleScene.top * image.height / child.height,
        visibleScene.width * image.width / child.width,
        visibleScene.height * image.height / child.height,
      );

      const outputWidth = 1600.0;
      final outputHeight = outputWidth / _bannerAspectRatio;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      canvas.drawImageRect(
        image,
        srcRect,
        Rect.fromLTWH(0, 0, outputWidth, outputHeight),
        Paint(),
      );

      final picture = recorder.endRecording();
      final rendered = await picture.toImage(
        outputWidth.round(),
        outputHeight.round(),
      );
      final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted || png == null) return;

      Navigator.pop(
        context,
        _EditedAdImage(
          bytes: png.buffer.asUint8List(),
          contentType: 'image/png',
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Подогнать фото для рекламы'),
        actions: [
          TextButton(
            onPressed: (_busy || _exporting) ? null : _resetImagePosition,
            child: const Text('Сбросить'),
          ),
        ],
      ),
      body: _busy || image == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: AspectRatio(
                          aspectRatio: _bannerAspectRatio,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final viewport = Size(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              );
                              _maybeInitMatrix(viewport);
                              final child = _baseImageSize!;

                              return ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Container(color: Colors.black),
                                    InteractiveViewer(
                                      transformationController: _controller,
                                      minScale: 1,
                                      maxScale: _maxScale,
                                      boundaryMargin: const EdgeInsets.all(100000),
                                      constrained: false,
                                      onInteractionUpdate: (_) {
                                        _controller.value = _clampMatrix(
                                          _controller.value.clone(),
                                        );
                                      },
                                      child: SizedBox(
                                        width: child.width,
                                        height: child.height,
                                        child: RawImage(
                                          image: image,
                                          fit: BoxFit.fill,
                                        ),
                                      ),
                                    ),
                                    IgnorePointer(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.white.withValues(alpha: 0.85),
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(
                      'Раздвинь пальцами, чтобы увеличить фото, и подвигай его так, как оно должно выглядеть в рекламной карточке.',
                      style: TextStyle(color: Theme.of(context).colorScheme.outline),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: (_busy || _exporting) ? null : _applyCrop,
          icon: _exporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: Text(_exporting ? 'Готовим картинку...' : 'Использовать для рекламы'),
        ),
      ),
    );
  }
}
