class CarSpecs {
  final String brand; // марка
  final String model; // модель
  final String generation; // поколение/серия (например: Camry XV70)
  final int? year; // год
  final int? mileageKm; // пробег
  final String? bodyType; // кузов
  final String? fuel; // топливо
  final double? engineVolume; // объем, л
  final int? powerHp; // л.с.
  final String? transmission; // коробка
  final String? drive; // привод
  final String? condition; // состояние
  final String? color; // цвет

  final bool? isCleared; // растаможен (опц.)
  final String? pts; // ПТС (опц.)
  final int? owners; // кол-во владельцев (опц.)
  final String? vin; // VIN (опц.)
  final String? note; // доп. инфо (опц.)

  const CarSpecs({
    required this.brand,
    required this.model,
    required this.generation,
    this.year,
    this.mileageKm,
    this.bodyType,
    this.fuel,
    this.engineVolume,
    this.powerHp,
    this.transmission,
    this.drive,
    this.condition,
    this.color,
    this.isCleared,
    this.pts,
    this.owners,
    this.vin,
    this.note,
  });

  Map<String, dynamic> toMap() => {
        'brand': brand,
        'model': model,
        'generation': generation,
        if (year != null) 'year': year,
        if (mileageKm != null) 'mileageKm': mileageKm,
        if (bodyType != null && bodyType!.trim().isNotEmpty)
          'bodyType': bodyType!.trim(),
        if (fuel != null && fuel!.trim().isNotEmpty) 'fuel': fuel!.trim(),
        if (engineVolume != null) 'engineVolume': engineVolume,
        if (powerHp != null) 'powerHp': powerHp,
        if (transmission != null && transmission!.trim().isNotEmpty)
          'transmission': transmission!.trim(),
        if (drive != null && drive!.trim().isNotEmpty) 'drive': drive!.trim(),
        if (condition != null && condition!.trim().isNotEmpty)
          'condition': condition!.trim(),
        if (color != null && color!.trim().isNotEmpty) 'color': color!.trim(),
        if (isCleared != null) 'isCleared': isCleared,
        if (pts != null && pts!.trim().isNotEmpty) 'pts': pts!.trim(),
        if (owners != null) 'owners': owners,
        if (vin != null && vin!.trim().isNotEmpty) 'vin': vin!.trim(),
        if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
      };

  static CarSpecs? fromAny(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);

    double? parseDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return CarSpecs(
      brand: (m['brand'] ?? '').toString(),
      model: (m['model'] ?? '').toString(),
      generation: (m['generation'] ?? '').toString(),
      year: parseInt(m['year']),
      mileageKm: parseInt(m['mileageKm']),
      bodyType: m['bodyType']?.toString(),
      fuel: m['fuel']?.toString(),
      engineVolume: parseDouble(m['engineVolume']),
      powerHp: parseInt(m['powerHp']),
      transmission: m['transmission']?.toString(),
      drive: m['drive']?.toString(),
      condition: m['condition']?.toString(),
      color: m['color']?.toString(),
      isCleared: m['isCleared'] is bool ? m['isCleared'] : null,
      pts: m['pts']?.toString(),
      owners: (m['owners'] is num)
          ? (m['owners'] as num).toInt()
          : int.tryParse('${m['owners']}'),
      vin: m['vin']?.toString(),
      note: m['note']?.toString(),
    );
  }
}
