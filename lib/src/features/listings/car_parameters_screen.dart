import 'package:atta/src/utils/vehicle_specs.dart';
import 'package:flutter/material.dart';

class CarParametersScreen extends StatefulWidget {
  const CarParametersScreen({
    super.key,
    required this.mileageController,
    required this.engineController,
    required this.powerController,
    required this.ownersController,
    required this.vinController,
    required this.bodyTypes,
    required this.fuelTypes,
    required this.transmissions,
    required this.drives,
    required this.conditions,
    required this.colors,
    required this.ptsTypes,
    required this.body,
    required this.fuel,
    required this.transmission,
    required this.drive,
    required this.condition,
    required this.color,
    required this.pts,
    required this.cleared,
    required this.onBodyChanged,
    required this.onFuelChanged,
    required this.onTransmissionChanged,
    required this.onDriveChanged,
    required this.onConditionChanged,
    required this.onColorChanged,
    required this.onPtsChanged,
    required this.onClearedChanged,
    this.engineVolumes = const <String>[],
    this.powerValues = const <String>[],
  });

  final TextEditingController mileageController;
  final TextEditingController engineController;
  final TextEditingController powerController;
  final TextEditingController ownersController;
  final TextEditingController vinController;
  final List<String> bodyTypes;
  final List<String> fuelTypes;
  final List<String> transmissions;
  final List<String> drives;
  final List<String> conditions;
  final List<String> colors;
  final List<String> ptsTypes;
  final List<String> engineVolumes;
  final List<String> powerValues;
  final String? body;
  final String? fuel;
  final String? transmission;
  final String? drive;
  final String? condition;
  final String? color;
  final String? pts;
  final bool? cleared;
  final ValueChanged<String?> onBodyChanged;
  final ValueChanged<String?> onFuelChanged;
  final ValueChanged<String?> onTransmissionChanged;
  final ValueChanged<String?> onDriveChanged;
  final ValueChanged<String?> onConditionChanged;
  final ValueChanged<String?> onColorChanged;
  final ValueChanged<String?> onPtsChanged;
  final ValueChanged<bool?> onClearedChanged;

  @override
  State<CarParametersScreen> createState() => _CarParametersScreenState();
}

class _CarParametersScreenState extends State<CarParametersScreen> {
  late String? _body = widget.body;
  late String? _fuel = widget.fuel;
  late String? _transmission = widget.transmission;
  late String? _drive = widget.drive;
  late String? _condition = widget.condition;
  late String? _color = widget.color;
  late String? _pts = widget.pts;
  late bool? _cleared = widget.cleared;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Параметры авто')),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          TextField(
            controller: widget.mileageController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              label: _fieldLabel('Пробег (необязательно)'),
            ),
          ),
          const SizedBox(height: 12),
          _drop(
            label: 'Кузов (необязательно)',
            value: _body,
            items: widget.bodyTypes,
            onChanged: (v) {
              setState(() => _body = v);
              widget.onBodyChanged(v);
            },
          ),
          const SizedBox(height: 12),
          _drop(
            label: 'Топливо (необязательно)',
            value: _fuel,
            items: widget.fuelTypes,
            onChanged: (v) {
              setState(() => _fuel = v);
              widget.onFuelChanged(v);
            },
          ),
          const SizedBox(height: 12),
          widget.engineVolumes.isEmpty
              ? TextField(
                  controller: widget.engineController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    label: _fieldLabel('Объём двигателя (необязательно)'),
                    helperText: 'Например: 2.2 или 300 куб. см',
                  ),
                )
              : _selectTile(
                  title: 'Объём двигателя (необязательно)',
                  value: widget.engineController.text.trim().isEmpty
                      ? ''
                      : formatEngineVolume(
                          parseEngineVolumeInput(widget.engineController.text),
                        ),
                  onTap: () => _openValuePickerSheet(
                    title: 'Объём двигателя',
                    items: _itemsWithCurrentValue(
                      widget.engineVolumes,
                      widget.engineController.text,
                    ),
                    currentValue: widget.engineController.text
                        .trim()
                        .replaceAll(',', '.'),
                    labelBuilder: (value) =>
                        formatEngineVolume(parseEngineVolumeInput(value)),
                    manualHint: 'Например: 2.2 или 300 куб. см',
                    onSelected: (value) => setState(
                      () => widget.engineController.text = value,
                    ),
                  ),
                ),
          const SizedBox(height: 12),
          widget.powerValues.isEmpty
              ? TextField(
                  controller: widget.powerController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    label: _fieldLabel('Мощность (необязательно)'),
                    helperText: 'Например: 193 л.с.',
                  ),
                )
              : _selectTile(
                  title: 'Мощность (необязательно)',
                  value: widget.powerController.text.trim().isEmpty
                      ? ''
                      : '${widget.powerController.text.trim()} л.с.',
                  onTap: () => _openValuePickerSheet(
                    title: 'Мощность',
                    items: _itemsWithCurrentValue(
                      widget.powerValues,
                      widget.powerController.text,
                    ),
                    currentValue: widget.powerController.text.trim(),
                    labelBuilder: (value) => '$value л.с.',
                    manualHint: 'Например: 193 л.с.',
                    onSelected: (value) => setState(
                      () => widget.powerController.text = value,
                    ),
                  ),
                ),
          const SizedBox(height: 12),
          _drop(
            label: 'Коробка передач (необязательно)',
            value: _transmission,
            items: widget.transmissions,
            onChanged: (v) {
              setState(() => _transmission = v);
              widget.onTransmissionChanged(v);
            },
          ),
          const SizedBox(height: 12),
          _drop(
            label: 'Привод (необязательно)',
            value: _drive,
            items: widget.drives,
            onChanged: (v) {
              setState(() => _drive = v);
              widget.onDriveChanged(v);
            },
          ),
          const SizedBox(height: 12),
          _drop(
            label: 'Состояние (необязательно)',
            value: _condition,
            items: widget.conditions,
            onChanged: (v) {
              setState(() => _condition = v);
              widget.onConditionChanged(v);
            },
          ),
          const SizedBox(height: 12),
          _drop(
            label: 'Цвет (необязательно)',
            value: _color,
            items: widget.colors,
            onChanged: (v) {
              setState(() => _color = v);
              widget.onColorChanged(v);
            },
          ),
          const SizedBox(height: 12),
          _drop(
            label: 'ПТС (необязательно)',
            value: _pts,
            items: widget.ptsTypes,
            onChanged: (v) {
              setState(() => _pts = v);
              widget.onPtsChanged(v);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue:
                _cleared == null ? 'Не указано' : (_cleared! ? 'Да' : 'Нет'),
            items: const [
              DropdownMenuItem(
                value: 'Не указано',
                child: Text('Растаможен: не указано'),
              ),
              DropdownMenuItem(value: 'Да', child: Text('Растаможен: да')),
              DropdownMenuItem(value: 'Нет', child: Text('Растаможен: нет')),
            ],
            onChanged: (v) {
              final next = switch (v) {
                'Да' => true,
                'Нет' => false,
                _ => null,
              };
              setState(() => _cleared = next);
              widget.onClearedChanged(next);
            },
            decoration: InputDecoration(
              label: _fieldLabel('Растаможен (необязательно)'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: widget.ownersController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              label: _fieldLabel('Количество владельцев (необязательно)'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: widget.vinController,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              label: _fieldLabel('VIN (необязательно)'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectTile({
    required String title,
    required String value,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: _fieldText(
                value.isEmpty ? title : value,
                TextStyle(
                  color: value.isEmpty
                      ? Theme.of(context).colorScheme.outline
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  Widget _drop({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      items:
          items.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
      onChanged: onChanged,
      decoration: InputDecoration(label: _fieldLabel(label)),
    );
  }

  List<String> _itemsWithCurrentValue(List<String> items, String current) {
    final normalized = current.trim().replaceAll(',', '.');
    if (normalized.isEmpty || items.contains(normalized)) return items;
    return [normalized, ...items];
  }

  Future<void> _openValuePickerSheet({
    required String title,
    required List<String> items,
    required String currentValue,
    required ValueChanged<String> onSelected,
    String Function(String value)? labelBuilder,
    String? manualHint,
  }) async {
    var selected = currentValue.trim();

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setModal) => SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.52,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 12, 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                        tooltip: 'Назад',
                      ),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final value = items[i];
                      final isSelected = value == selected;
                      final text = labelBuilder?.call(value) ?? value;
                      return ListTile(
                        title: Text(text),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: Colors.blue)
                            : null,
                        onTap: () => setModal(() => selected = value),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final custom = await _askText(
                              title: '$title вручную',
                              hint: manualHint ?? 'Введите значение',
                            );
                            if (custom == null || !mounted) return;
                            onSelected(custom);
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                          child: const Text('Другое / вручную'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            if (selected.isEmpty && items.isNotEmpty) {
                              selected = items.first;
                            }
                            onSelected(selected);
                            Navigator.pop(ctx);
                          },
                          child: const Text('Выбрать'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<String?> _askText({
    required String title,
    required String hint,
  }) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Готово'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result?.trim();
  }

  Widget _fieldLabel(String label) => _fieldText(label, null);

  Widget _fieldText(String text, TextStyle? style) {
    const suffix = ' (необязательно)';
    if (!text.endsWith(suffix)) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final name = text.substring(0, text.length - suffix.length);
    return Text.rich(
      TextSpan(
        text: '$name ',
        style: style,
        children: const [
          TextSpan(
            text: '(необязательно)',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
