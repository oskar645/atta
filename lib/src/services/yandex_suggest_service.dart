import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:chestore2/src/secrets/yandex_suggest_key.dart';

class YandexAddressSuggestion {
  final String value;
  final String title;
  final String subtitle;

  const YandexAddressSuggestion({
    required this.value,
    required this.title,
    this.subtitle = '',
  });
}

class YandexSuggestService {
  static const String _baseUrl = 'https://suggest-maps.yandex.ru/v1/suggest';

  Future<List<YandexAddressSuggestion>> suggest(String text) async {
    final query = text.trim();
    if (query.length < 2) return const <YandexAddressSuggestion>[];

    final uri = Uri.parse(_baseUrl).replace(queryParameters: <String, String>{
      'apikey': kYandexSuggestApiKey,
      'text': query,
      'lang': 'ru_RU',
      'print_address': '1',
      'results': '10',
    });

    try {
      final resp = await http.get(uri);
      if (resp.statusCode != 200) {
        return const <YandexAddressSuggestion>[];
      }

      final data = json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final results = (data['results'] as List?) ?? const <dynamic>[];
      final out = <YandexAddressSuggestion>[];
      final seen = <String>{};

      for (final item in results) {
        if (item is! Map<String, dynamic>) continue;

        final suggestion = _buildSuggestion(item);
        if (suggestion == null) continue;

        final normalized = suggestion.value.toLowerCase();
        if (seen.add(normalized)) {
          out.add(suggestion);
        }
      }

      return out;
    } catch (_) {
      return const <YandexAddressSuggestion>[];
    }
  }

  YandexAddressSuggestion? _buildSuggestion(Map<String, dynamic> item) {
    final title = _readNestedText(item, 'title');
    final subtitle = _readNestedText(item, 'subtitle');
    final formattedAddress = _readFormattedAddress(item);
    final components = _readAddressComponents(item);

    final displayTitle = _buildDisplayTitle(
      title: title,
      subtitle: subtitle,
      formattedAddress: formattedAddress,
      components: components,
    );
    final displaySubtitle = _buildDisplaySubtitle(
      title: displayTitle,
      subtitle: subtitle,
      formattedAddress: formattedAddress,
      components: components,
    );
    final value = formattedAddress.isNotEmpty
        ? formattedAddress
        : <String>[
            if (displayTitle.isNotEmpty) displayTitle,
            if (displaySubtitle.isNotEmpty) displaySubtitle,
          ].join(', ').trim();

    if (value.isEmpty) return null;

    return YandexAddressSuggestion(
      value: value,
      title: displayTitle.isNotEmpty ? displayTitle : value,
      subtitle: displaySubtitle,
    );
  }

  String _readNestedText(Map<String, dynamic> item, String key) {
    final block = item[key];
    if (block is Map && block['text'] != null) {
      return block['text'].toString().trim();
    }
    return '';
  }

  String _readFormattedAddress(Map<String, dynamic> item) {
    final address = item['address'];
    if (address is Map && address['formatted_address'] != null) {
      return address['formatted_address'].toString().trim();
    }
    return '';
  }

  List<_AddressComponent> _readAddressComponents(Map<String, dynamic> item) {
    final address = item['address'];
    if (address is! Map) return const <_AddressComponent>[];

    final raw = address['component'];
    if (raw is! List) return const <_AddressComponent>[];

    final out = <_AddressComponent>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final kind = (entry['kind'] ?? '').toString().trim();
      final name = (entry['name'] ?? '').toString().trim();
      if (kind.isEmpty || name.isEmpty) continue;
      out.add(_AddressComponent(kind: kind, name: name));
    }
    return out;
  }

  String _buildDisplayTitle({
    required String title,
    required String subtitle,
    required String formattedAddress,
    required List<_AddressComponent> components,
  }) {
    final street = _pickComponent(
      components,
      const ['street', 'route', 'house'],
    );
    final locality = _pickComponent(
      components,
      const ['locality', 'district', 'province', 'area'],
    );

    if (street.isNotEmpty && locality.isNotEmpty) {
      return '$street, $locality';
    }
    if (street.isNotEmpty) return street;
    if (title.isNotEmpty && subtitle.isNotEmpty) return '$title, $subtitle';
    if (title.isNotEmpty) return title;
    if (locality.isNotEmpty) return locality;
    return formattedAddress;
  }

  String _buildDisplaySubtitle({
    required String title,
    required String subtitle,
    required String formattedAddress,
    required List<_AddressComponent> components,
  }) {
    final details = <String>[
      _pickComponent(components, const ['province']),
      _pickComponent(components, const ['area']),
      _pickComponent(components, const ['district']),
      _pickComponent(components, const ['locality']),
      _pickComponent(components, const ['street']),
      _pickComponent(components, const ['house']),
    ];

    final clean = <String>[];
    final seen = <String>{};
    for (final part in details) {
      final value = part.trim();
      if (value.isEmpty) continue;
      final key = value.toLowerCase();
      if (seen.add(key) && value.toLowerCase() != title.toLowerCase()) {
        clean.add(value);
      }
    }

    if (clean.isNotEmpty) {
      return clean.join(', ');
    }

    if (subtitle.isNotEmpty && subtitle.toLowerCase() != title.toLowerCase()) {
      return subtitle;
    }

    if (formattedAddress.isNotEmpty && formattedAddress.toLowerCase() != title.toLowerCase()) {
      return formattedAddress;
    }

    return '';
  }

  String _pickComponent(List<_AddressComponent> components, List<String> kinds) {
    for (final kind in kinds) {
      for (final component in components) {
        if (component.kind == kind) return component.name;
      }
    }
    return '';
  }
}

class _AddressComponent {
  final String kind;
  final String name;

  const _AddressComponent({
    required this.kind,
    required this.name,
  });
}
