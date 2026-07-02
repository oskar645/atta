String formatEngineVolume(double? value) {
  if (value == null) return '';
  if (value >= 20) {
    final cc = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
    return '$cc куб. см';
  }
  return '${value.toStringAsFixed(1)} л';
}

double? parseEngineVolumeInput(String raw) {
  final normalized = raw.trim().toLowerCase().replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  final matched = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(normalized);
  if (matched == null) return null;
  final number = double.tryParse(matched.group(1)!);
  if (number == null) return null;
  return number;
}

int? parsePowerHpInput(String raw) {
  final normalized = raw.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  final matched = RegExp(r'(\d+)').firstMatch(normalized);
  if (matched == null) return null;
  return int.tryParse(matched.group(1)!);
}
