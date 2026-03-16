// lib/src/models/listing.dart
import 'car_specs.dart';

/// Структурированная локация (как Avito), но совместима со старым city String.
class ListingLocation {
/// Регион/субъект РФ (Чеченская Республика)
final String region;

/// Район/округ (Гудермесский район)
final String district;

/// Город/нас.пункт (Гудермес / Шуани)
final String locality;

/// Село/посёлок/микрорайон и т.п. (если locality = город, то тут может быть район/улица)
final String subLocality;

/// Любая “сырая” строка (если пришла из старого city)
final String raw;

const ListingLocation({
this.region = '',
this.district = '',
this.locality = '',
this.subLocality = '',
this.raw = '',
});

bool get isEmpty =>
region.trim().isEmpty &&
district.trim().isEmpty &&
locality.trim().isEmpty &&
subLocality.trim().isEmpty &&
raw.trim().isEmpty;

/// Для карточки: только последний “уровень”
/// Пример: "Чеченская..., Гудермесский..., село Шуани" -> "Шуани"
String toShortLabel() {
// приоритет: subLocality -> locality -> district -> region -> raw
final candidates = <String>[
subLocality,
locality,
district,
region,
raw,
].map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

if (candidates.isEmpty) return '';

// если raw = "A, B, C" — возьмём последнюю часть
final last = candidates.first;
return _lastToken(last);
}

/// Для деталки: полная строка (регион, район, город/село...)
String toFullLabel() {
final parts = <String>[
region,
district,
locality,
subLocality,
].map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

if (parts.isNotEmpty) return parts.join(', ');

// fallback на raw
return raw.trim();
}

Map<String, dynamic> toMap() => {
'region': region.trim(),
'district': district.trim(),
'locality': locality.trim(),
'sub_locality': subLocality.trim(),
'raw': raw.trim(),
};

static ListingLocation fromAny(dynamic v, {String fallbackCity = ''}) {
// 1) если в базе уже есть json location
if (v is Map) {
String pick(String key) => (v[key] ?? '').toString().trim();

return ListingLocation(
region: pick('region'),
district: pick('district'),
locality: pick('locality'),
subLocality: pick('sub_locality'),
raw: pick('raw'),
);
}

// 2) fallback: разбираем старый city string
final raw = fallbackCity.trim();
if (raw.isEmpty) return const ListingLocation();

// ожидаем строки типа: "Регион, Район, Город, Село ..."
final parts = raw
.split(',')
.map((e) => e.trim())
.where((e) => e.isNotEmpty)
.toList();

if (parts.isEmpty) return ListingLocation(raw: raw);

// Очень безопасная логика, чтобы не ломалось:
// region = 1я часть, district = 2я, locality = 3я, subLocality = 4я+
final region = parts.isNotEmpty ? parts[0] : '';
final district = parts.length >= 2 ? parts[1] : '';
final locality = parts.length >= 3 ? parts[2] : '';
final subLocality = parts.length >= 4 ? parts.sublist(3).join(', ') : '';

return ListingLocation(
region: region,
district: district,
locality: locality,
subLocality: subLocality,
raw: raw,
);
}

static String _lastToken(String s) {
var t = s.trim();
if (t.isEmpty) return t;

// если строка "село Шуани" -> "Шуани"
final prefixes = <String>[
'село ',
'посёлок ',
'поселок ',
'пгт ',
'деревня ',
'г. ',
'город ',
'аул ',
'ст. ',
'станица ',
'мкр ',
'микрорайон ',
'р-н ',
'район ',
];

final low = t.toLowerCase();
for (final p in prefixes) {
if (low.startsWith(p)) {
t = t.substring(p.length).trim();
break;
}
}

// если там ещё остались запятые — берём последнюю часть
if (t.contains(',')) {
final ps = t.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
if (ps.isNotEmpty) t = ps.last;
}

return t;
}
}

class Listing {
final String id;

final String ownerId;
final String ownerEmail;
final String ownerName;

final String title;
final String description;
final String category;
final String subcategory; // ✅ ДОБАВИЛИ
final int price;

final String phone;
final bool phoneHidden;

/// Старое поле (оставляем для совместимости).
/// Обычно сюда кладём полный адрес одной строкой.
final String city;

/// Новое: структурированная локация (jsonb).
/// В базе это может быть колонка `location` (jsonb).
/// Если колонки нет — просто будет вычисляться из city.
final ListingLocation location;

final Map<String, dynamic> delivery; // jsonb
final List<String> photoUrls; // text[]

final CarSpecs? car; // ✅ удобно как модель (nullable)

final String? dealType;
final String? realEstateType;
final String? clothesType;

final int viewCount;
final String status;
final String rejectionReason;

final DateTime createdAt;
final DateTime? updatedAt;

Listing({
required this.id,
required this.ownerId,
required this.ownerEmail,
required this.ownerName,
required this.title,
required this.description,
required this.category,
required this.subcategory,
required this.price,
required this.phone,
required this.phoneHidden,
required this.city,
required this.location,
required this.delivery,
required this.photoUrls,
required this.car,
required this.dealType,
required this.realEstateType,
required this.clothesType,
required this.viewCount,
required this.status,
required this.rejectionReason,
required this.createdAt,
required this.updatedAt,
});

bool get isArchivedStatus =>
status == 'sold' ||
status == 'deleted' ||
status == 'archived' ||
status == 'rejected';

bool get canOwnerEdit => status == 'approved' || status == 'rejected';

String get archiveNote {
final note = rejectionReason.trim();
if (note.isNotEmpty) return note;
switch (status) {
case 'sold':
return 'Объявление отмечено как проданное.';
case 'deleted':
return 'Объявление удалено администратором.';
case 'archived':
return 'Объявление снято с публикации.';
case 'rejected':
return 'Объявление отправлено на доработку.';
default:
return '';
}
}

/// Для карточки (как ты хотел): только “последний уровень”
/// Пример: "Чеченская..., Гудермесский..., село Шуани" -> "Шуани"
String get cityShort {
final s = location.toShortLabel().trim();
if (s.isNotEmpty) return s;

// fallback если location пустая
final raw = city.trim();
if (raw.isEmpty) return '';
final parts = raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
if (parts.isEmpty) return raw;
return ListingLocation._lastToken(parts.last);
}

/// Для деталки: полная строка
String get cityFull {
final s = location.toFullLabel().trim();
if (s.isNotEmpty) return s;
return city.trim();
}

static DateTime _parseDt(dynamic v) {
if (v == null) return DateTime.now();
if (v is DateTime) return v;
if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
return DateTime.now();
}

static List<String> _parseTextArray(dynamic v) {
if (v == null) return <String>[];
if (v is List) return v.map((e) => e.toString()).toList();
return <String>[];
}

static Map<String, dynamic> _parseJson(dynamic v) {
if (v == null) return <String, dynamic>{};
if (v is Map<String, dynamic>) return v;
if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
return <String, dynamic>{};
}

/// ✅ Supabase row -> Listing
factory Listing.fromMap(Map<String, dynamic> row) {
final delivery = _parseJson(row['delivery']);
final photos = _parseTextArray(row['photo_urls']);
final carRaw = row['car'];

final city = (row['city'] ?? '').toString();

// ✅ если есть колонка location (jsonb) — используем её.
// ✅ если нет — парсим из city.
final locationRaw = row['location']; // может быть null
final location = ListingLocation.fromAny(locationRaw, fallbackCity: city);

return Listing(
id: row['id'].toString(),
ownerId: (row['owner_id'] ?? '').toString(),
ownerEmail: (row['owner_email'] ?? '').toString(),
ownerName: (row['owner_name'] ?? '').toString(),
title: (row['title'] ?? '').toString(),
description: (row['description'] ?? '').toString(),
category: (row['category'] ?? '').toString(),
subcategory: (row['subcategory'] ?? '').toString(),
price: (row['price'] is num) ? (row['price'] as num).toInt() : 0,
phone: (row['phone'] ?? '').toString(),
phoneHidden: row['phone_hidden'] == true,
city: city,
location: location,
delivery: delivery,
photoUrls: photos,
car: CarSpecs.fromAny(carRaw),
dealType: row['deal_type']?.toString(),
realEstateType: row['real_estate_type']?.toString(),
clothesType: row['clothes_type']?.toString(),
viewCount: (row['view_count'] is num) ? (row['view_count'] as num).toInt() : 0,
status: (row['status'] ?? 'approved').toString(),
rejectionReason: (row['rejection_reason'] ?? '').toString(),
createdAt: _parseDt(row['created_at']),
updatedAt: row['updated_at'] == null ? null : _parseDt(row['updated_at']),
);
}

Map<String, dynamic> toMap() {
return {
'id': id,
'owner_id': ownerId,
'owner_email': ownerEmail,
'owner_name': ownerName,
'title': title,
'description': description,
'category': category,
'subcategory': subcategory,
'price': price,
'phone': phone,
'phone_hidden': phoneHidden,

// ✅ старое поле остаётся, туда кладём "полную строку"
'city': city,

// ✅ новое поле (если в таблице есть jsonb колонка `location`)
// Если колонки нет — Supabase просто проигнорит при insert/update
'location': location.toMap(),

'delivery': delivery,
'photo_urls': photoUrls,
'car': car?.toMap(),
'deal_type': dealType,
'real_estate_type': realEstateType,
'clothes_type': clothesType,
'view_count': viewCount,
'status': status,
'rejection_reason': rejectionReason,
'created_at': createdAt.toIso8601String(),
'updated_at': updatedAt?.toIso8601String(),
};
}
}
