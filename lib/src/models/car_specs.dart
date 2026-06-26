class CarSpecs {
  final String brand; // марка
  final String model; // модель
  final String generation; // поколение/серия (например: Camry XV70)
  final int year; // год
  final int mileageKm; // пробег
  final String bodyType; // кузов
  final String fuel; // топливо
  final double engineVolume; // объем, л
  final int powerHp; // л.с.
  final String transmission; // коробка
  final String drive; // привод
  final String condition; // состояние
  final String color; // цвет

  final bool? isCleared; // растаможен (опц.)
  final int? owners; // кол-во владельцев (опц.)
  final String? vin; // VIN (опц.)
  final String? note; // доп. инфо (опц.)

  const CarSpecs({
    required this.brand,
    required this.model,
    required this.generation,
    required this.year,
    required this.mileageKm,
    required this.bodyType,
    required this.fuel,
    required this.engineVolume,
    required this.powerHp,
    required this.transmission,
    required this.drive,
    required this.condition,
    required this.color,
    this.isCleared,
    this.owners,
    this.vin,
    this.note,
  });

  Map<String, dynamic> toMap() => {
        'brand': brand,
        'model': model,
        'generation': generation,
        'year': year,
        'mileageKm': mileageKm,
        'bodyType': bodyType,
        'fuel': fuel,
        'engineVolume': engineVolume,
        'powerHp': powerHp,
        'transmission': transmission,
        'drive': drive,
        'condition': condition,
        'color': color,
        if (isCleared != null) 'isCleared': isCleared,
        if (owners != null) 'owners': owners,
        if (vin != null && vin!.trim().isNotEmpty) 'vin': vin!.trim(),
        if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
      };

  static CarSpecs? fromAny(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);

    double parseDouble(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0.0;
    }

    int parseInt(dynamic v) {
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    return CarSpecs(
      brand: (m['brand'] ?? '').toString(),
      model: (m['model'] ?? '').toString(),
      generation: (m['generation'] ?? '').toString(),
      year: parseInt(m['year']),
      mileageKm: parseInt(m['mileageKm']),
      bodyType: (m['bodyType'] ?? '').toString(),
      fuel: (m['fuel'] ?? '').toString(),
      engineVolume: parseDouble(m['engineVolume']),
      powerHp: parseInt(m['powerHp']),
      transmission: (m['transmission'] ?? '').toString(),
      drive: (m['drive'] ?? '').toString(),
      condition: (m['condition'] ?? '').toString(),
      color: (m['color'] ?? '').toString(),
      isCleared: m['isCleared'] is bool ? m['isCleared'] : null,
      owners: (m['owners'] is num)
          ? (m['owners'] as num).toInt()
          : int.tryParse('${m['owners']}'),
      vin: m['vin']?.toString(),
      note: m['note']?.toString(),
    );
  }
}
