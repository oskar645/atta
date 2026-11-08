import 'package:atta/src/data/auto_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

const _requiredPopularRaw = <String>[
  'LADA',
  'Toyota',
  'Kia',
  'Hyundai',
  'Nissan',
  'Volkswagen',
  'Mercedes-Benz',
  'BMW',
  'Audi',
  'Renault',
  'Chevrolet',
  'Ford',
  'Honda',
  'Mazda',
  'Mitsubishi',
  'Skoda',
  'Opel',
  'Peugeot',
  'Lexus',
  'Chery',
  'Haval',
  'Geely',
  'Changan',
  'Exeed',
  'OMODA',
  'JAECOO',
  'Tank',
  'Jetour',
  'GAC',
  'FAW',
  'Hongqi',
  'BAIC',
  'JAC',
  'DongFeng',
  'GWM',
  'BYD',
  'Zeekr',
  'LiXiang',
  'Voyah',
  'Solaris',
  'Москвич',
  'УАЗ',
  'ГАЗ',
  'Bestune',
  'Belgee',
  'Rox',
];

const _requiredTailRaw = <String>[
  'AC',
  'Acura',
  'Adler',
  'Alfa Romeo',
  'Alpina',
  'Alpine',
  'AM General',
  'AMC',
  'Apal',
  'Ariel',
  'Aro',
  'Asia',
  'Aston Martin',
  'Aurus',
  'Austin',
  'Austin Healey',
  'Autobianchi',
  'BAIC',
  'Bajaj',
  'Baltijas Dzips',
  'Belgee',
  'Bentley',
  'Bertone',
  'Bestune',
  'Bilenkin',
  'Bio auto',
  'Bitter',
  'Borgward',
  'Brabus',
  'Brilliance',
  'Bristol',
  'Bufori',
  'Bugatti',
  'Buick',
  'BYD',
  'Byvin',
  'Cadillac',
  'Callaway',
  'Carbodies',
  'Caterham',
  'Chana',
  'ChangFeng',
  'Changhe',
  'Changan',
  'Chevrolet',
  'Chery',
  'Chrysler',
  'Citroen',
  'Cizeta',
  'Coggiola',
  'Cord',
  'Dacia',
  'Dadi',
  'Daewoo',
  'Daihatsu',
  'Daimler',
  'Dallara',
  'Datsun',
  'De Tomaso',
  'Deco Rides',
  'Delage',
  'DeLorean',
  'Derways',
  'DeSoto',
  'DKW',
  'Dodge',
  'DongFeng',
  'Doninvest',
  'Donkervoort',
  'DS',
  'DW Hower',
  'E-Car',
  'Eagle',
  'Eagle Cars',
  'Excalibur',
  'Exeed',
  'FAW',
  'Ferrari',
  'Fiat',
  'Fisker',
  'Flanker',
  'Forthing',
  'Foton',
  'FSO',
  'Fuqi',
  'GAC',
  'Geely',
  'Genesis',
  'Geo',
  'GMC',
  'Gonow',
  'Gordon',
  'GP',
  'Great Wall',
  'GWM',
  'Hafei',
  'Haima',
  'Hanomag',
  'Haval',
  'Hawtai',
  'Heinkel',
  'Hindustan',
  'Hispano-Suiza',
  'Holden',
  'Honda',
  'Hongqi',
  'Horch',
  'HuangHai',
  'Hudson',
  'Hummer',
  'Hyundai',
  'Infiniti',
  'Innocenti',
  'International',
  'Invicta',
  'Iran Khodro',
  'Isdera',
  'Isuzu',
  'IVECO',
  'JAC',
  'JAECOO',
  'Jaguar',
  'Jeep',
  'Jensen',
  'Jetour',
  'Jinbei',
  'Jishi',
  'JMC',
  'Kaiyi',
  'KGM',
  'Kia',
  'Koenigsegg',
  'KTM AG',
  'LADA',
  'Lamborghini',
  'Lancia',
  'Land Rover',
  'Landwind',
  'Lexus',
  'Liebao Motor',
  'Lifan',
  'Ligier',
  'Lincoln',
  'LiXiang',
  'Livan',
  'Logem',
  'Lotus',
  'LTI',
  'Lucid',
  'Luxgen',
  'Lynk & Co',
  'Mahindra',
  'Marcos',
  'Marlin',
  'Marussia',
  'Maruti',
  'Maserati',
  'Mazda',
  'Mercedes-Benz',
  'Mitsubishi',
  'NIO',
  'Nissan',
  'Noble',
  'Oldsmobile',
  'OMODA',
  'Opel',
  'ORA',
  'Osca',
  'Packard',
  'Pagani',
  'Panoz',
  'Perodua',
  'Peugeot',
  'PGO',
  'Piaggio',
  'Plymouth',
  'Pontiac',
  'Porsche',
  'Premier',
  'Proton',
  'PUCH',
  'Puma',
  'Qoros',
  'Qvale',
  'RAM',
  'Rambler',
  'Ravon',
  'Reliant',
  'Renaissance',
  'Rox',
  'Renault',
  'Renault Samsung',
  'Rezvani',
  'Rimac',
  'Rinspeed',
  'Roewe',
  'Rolls-Royce',
  'Ronart',
  'Rover',
  'Saab',
  'Saipa',
  'Saleen',
  'Santana',
  'Saturn',
  'Scion',
  'Sears',
  'SEAT',
  'Shanghai Maple',
  'ShuangHuan',
  'Simca',
  'Skoda',
  'Skywell',
  'Smart',
  'Solaris',
  'Soueast',
  'Spectre',
  'Spyker',
  'SsangYong',
  'Steyr',
  'Studebaker',
  'Subaru',
  'Suzuki',
  'SWM',
  'Talbot',
  'Tank',
  'TATA',
  'Tatra',
  'Tazzari',
  'Tesla',
  'Think',
  'Tianma',
  'Tianye',
  'Tofas',
  'Toyota',
  'Trabant',
  'Tramontana',
  'Triumph',
  'TVR',
  'Ultima',
  'Vauxhall',
  'Vector',
  'Venturi',
  'Volkswagen',
  'Volvo',
  'Vortex',
  'Voyah',
  'W Motors',
  'Wanderer',
  'Wartburg',
  'Westfield',
  'Wey',
  'Wiesmann',
  'Willys',
  'Xin Kai',
  'Xpeng',
  'Yulon',
  'Zastava',
  'Zenos',
  'Zenvo',
  'Zeekr',
  'Zibar',
  'Zotye',
  'ZX',
  'Автокам',
  'ВАЗ',
  'ГАЗ',
  'Гоночный болид',
  'ЗАЗ',
  'ЗИЛ',
  'ЗиС',
  'ИЖ',
  'Канонир',
  'Комбат',
  'ЛуАЗ',
  'Москвич',
  'СМЗ',
  'ТагАЗ',
  'УАЗ',
  'Ё-мобиль',
];

List<String> _canonicalize(Iterable<String> values) {
  final result = <String>[];
  for (final value in values) {
    final canonical = canonicalAutoBrand(value);
    if (canonical.isEmpty || result.contains(canonical)) {
      continue;
    }
    result.add(canonical);
  }
  return result;
}

void main() {
  test('critical transport brands remain available in picker', () {
    expect(kAutoBrandsPopular, contains('Changan'));
    expect(kAutoBrandsPopular, contains('Jaecoo'));
    expect(kAutoBrandsPopular, contains('Voyah'));
    expect(kAutoBrandsPopular, contains('Solaris'));
    expect(kAutoBrandsPopular, contains('Москвич'));
    expect(kAutoBrandsPopular, contains('УАЗ'));
    expect(kAutoBrandsPopular, contains('ГАЗ'));
    expect(kAutoBrandsPopular, contains('Lynk & Co'));
    expect(kAutoBrandsPopular, contains('Avatr'));
    expect(kAutoBrandsPopular, contains('Deepal'));
  });

  test('vehicle brand list contains all required brands', () {
    final required = _canonicalize(<String>[
      ..._requiredPopularRaw,
      ..._requiredTailRaw,
    ]);
    expect(kAutoBrandsPopular, containsAll(required));
  });

  test('popular transport brands stay at the top before alphabetical tail', () {
    final expectedPopular = _canonicalize(_requiredPopularRaw);
    expect(
      kAutoBrandsPopular.take(expectedPopular.length).toList(),
      expectedPopular,
    );

    final tail = kAutoBrandsPopular
        .skip(expectedPopular.length)
        .where((brand) => brand != kAutoCustomBrandLabel)
        .toList();
    final sortedTail = [...tail]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    expect(tail, sortedTail);
  });

  test('brand aliases resolve to canonical transport brands', () {
    expect(canonicalAutoBrand('OMODA'), 'Omoda');
    expect(canonicalAutoBrand('JAECOO'), 'Jaecoo');
    expect(canonicalAutoBrand('LiXiang'), 'Li Auto');
    expect(canonicalAutoBrand('DongFeng'), 'Dongfeng');
    expect(canonicalAutoBrand('ВАЗ'), 'LADA (ВАЗ)');
  });

  test('existing brands models and generations remain intact', () {
    expect(kAutoBrandsPopular, contains('Toyota'));
    expect(kAutoBrandsPopular, contains('LADA (ВАЗ)'));
    expect(autoModelsForBrand('Toyota'), contains('Camry'));
    expect(autoModelsForBrand('LADA'), contains('Granta'));
    expect(autoGenerationsForBrandModel('Toyota', 'Camry'), contains('XV70'));
    expect(
      autoGenerationsForBrandModel('Volkswagen', 'Tiguan'),
      contains('2 поколение'),
    );
  });

  test('popular brands contain expanded main models', () {
    expect(
        autoModelsForBrand('Toyota'),
        containsAll(<String>[
          'Corolla Cross',
          'C-HR',
          'Fortuner',
          'Harrier',
        ]));
    expect(
        autoModelsForBrand('Volkswagen'),
        containsAll(<String>[
          'Multivan',
          'Caravelle',
        ]));
    expect(
        autoModelsForBrand('LADA'),
        containsAll(<String>[
          'Priora',
          'Aura',
          'Iskra',
        ]));
  });

  test('first catalog brand LADA exposes complete legacy and current families',
      () {
    final models = autoModelsForBrand('LADA');
    expect(kAutoBrandsPopular.first, 'LADA (ВАЗ)');
    expect(
        models,
        containsAll(<String>[
          '1111 Ока',
          '2102',
          '2103',
          '2104',
          '2105',
          '2108',
          '21099',
          '2111',
          '2113',
          '2114',
          '2115',
          '2120 Надежда',
          '2121 (4x4)',
          '2131 (4x4)',
          '2329',
          'EL LADA',
          'e-Largus',
          'XRAY Cross',
          'X-Cross 5',
          'Azimut',
        ]));
    expect(models.toSet(), hasLength(models.length));
    expect(models.last, kAutoCustomModelLabel);
    expect(autoGenerationsForBrandModel('ВАЗ', 'Kalina'), <String>['I', 'II']);
    expect(autoGenerationsForBrandModel('LADA', '2120 Надежда'),
        <String>['I', 'I рестайлинг']);
  });

  test('mandatory vehicle brands are available without canonical duplicates',
      () {
    const mandatoryBrands = <String>[
      'Audi',
      'BMW',
      'Changan',
      'Chery',
      'Chevrolet',
      'Dodge',
      'Ford',
      'GAC',
      'Geely',
      'Hongqi',
      'Hyundai',
      'Jeep',
      'Kia',
      'Lexus',
      'Li Auto',
      'Mazda',
      'Mercedes-Benz',
      'Mitsubishi',
      'Nissan',
      'Opel',
      'Toyota',
      'Volkswagen',
      'Volvo',
      'Zeekr',
      'LADA (ВАЗ)',
      'ВИС',
      'ГАЗ',
      'УАЗ',
    ];

    expect(kAutoBrandsPopular, containsAll(mandatoryBrands));
    expect(kAutoBrandsPopular.toSet(), hasLength(kAutoBrandsPopular.length));
    expect(canonicalAutoBrand('LiXiang'), 'Li Auto');
    expect(canonicalAutoBrand('ВАЗ'), 'LADA (ВАЗ)');
  });

  test('Toyota catalog keeps manual fallback and generations for every model',
      () {
    final models = autoModelsForBrand('Toyota');
    expect(
        models,
        containsAll(<String>[
          'Aqua',
          'Avalon',
          'Caldina',
          'Celica',
          'Corolla Fielder',
          'Crown Majesta',
          'Hilux Surf',
          'Land Cruiser Cygnus',
          'MR2',
          'Prius PHV',
          'Sequoia',
          'Sienna',
          'Sprinter Trueno',
          'Wish',
          'Yaris Cross',
          'bZ4X',
          '4Runner',
          '2000GT',
          'Mirai',
          'SD',
          'SF',
          'Supra',
          'Tacoma',
          'Tundra',
          'Vellfire',
        ]));
    expect(models.toSet(), hasLength(models.length));
    expect(models.last, kAutoCustomModelLabel);
    expect(models, contains('Camry Solara'));
    expect(models, isNot(contains('Solara')),
        reason: 'Solara must not duplicate existing Camry Solara');
    for (final model in models.where((item) => item != kAutoCustomModelLabel)) {
      expect(
        autoGenerationsForBrandModel('Toyota', model),
        isNotEmpty,
        reason: 'Toyota $model must expose at least one generation',
      );
    }
  });

  test(
      'VIS catalog exposes confirmed families without treating bodies as models',
      () {
    final models = autoModelsForBrand('ВИС');
    expect(models, containsAll(<String>['1705', '2345', '2346', '2349']));
    expect(models.toSet(), hasLength(models.length));
    expect(models.last, kAutoCustomModelLabel);
    expect(autoGenerationsForBrandModel('ВИС', '2346'),
        <String>['I', 'I рестайлинг']);
  });

  test('broad catalog pass exposes confirmed popular model families', () {
    final expected = <String, List<String>>{
      'Audi': ['A1', 'Q4 e-tron', 'R8'],
      'BMW': ['8 Series', 'i3', 'iX3'],
      'Chevrolet': ['Corvette', 'Spark', 'Traverse'],
      'Ford': ['Bronco', 'EcoSport', 'Tourneo Custom'],
      'Honda': ['Integra', 'Legend', 'Prelude'],
      'Hyundai': ['Getz', 'Ioniq 5', 'Kona'],
      'Kia': ['EV6', 'Niro', 'Stinger'],
      'Mazda': ['Demio', 'RX-7', 'CX-60'],
      'Nissan': ['GT-R', 'Skyline', 'Terrano'],
      'Opel': ['Kadett', 'Omega', 'Vivaro'],
      'Volkswagen': ['Amarok', 'ID.4', 'Touran'],
      'Volvo': ['C30', 'EX30', 'XC70'],
      'ГАЗ': ['21 Волга', '3110 Волга', 'Volga Siber'],
      'УАЗ': ['3151', '3162 Simbir', '469'],
    };

    for (final entry in expected.entries) {
      final models = autoModelsForBrand(entry.key);
      expect(models, containsAll(entry.value), reason: entry.key);
      expect(models.toSet(), hasLength(models.length), reason: entry.key);
      expect(models.last, kAutoCustomModelLabel, reason: entry.key);
    }
  });

  test(
      'previously generation-empty brands now expose generations for all models',
      () {
    const auditedBrands = <String>[
      'Audi',
      'BMW',
      'Changan',
      'Chery',
      'Chevrolet',
      'Citroen',
      'Dodge',
      'Exeed',
      'Ford',
      'GAC',
      'Geely',
      'Haval',
      'Honda',
      'Hongqi',
      'Hyundai',
      'Infiniti',
      'Jeep',
      'Jetour',
      'Kia',
      'Lexus',
      'Li Auto',
      'Mazda',
      'Mercedes-Benz',
      'Mitsubishi',
      'Nissan',
      'Omoda',
      'Opel',
      'Peugeot',
      'Porsche',
      'Renault',
      'Skoda',
      'Subaru',
      'Suzuki',
      'Tank',
      'Volkswagen',
      'Volvo',
      'Zeekr',
      'ГАЗ',
      'УАЗ',
    ];

    for (final brand in auditedBrands) {
      final models = autoModelsForBrand(brand)
          .where((model) => model != kAutoCustomModelLabel);
      for (final model in models) {
        expect(
          autoGenerationsForBrandModel(brand, model),
          isNotEmpty,
          reason: '$brand $model must expose at least one generation',
        );
      }
    }
  });

  test('expanded transport catalog exposes critical models and generations',
      () {
    expect(autoModelsForBrand('Changan'), contains('UNI-Z'));
    expect(autoModelsForBrand('Changan'), contains('Raeton Plus'));
    expect(autoModelsForBrand('LiXiang'), contains('L9'));
    expect(autoModelsForBrand('OMODA'), contains('C5'));
    expect(autoModelsForBrand('Москвич'), contains('3'));

    expect(autoGenerationsForBrandModel('Changan', 'UNI-Z'), contains('I'));
    expect(autoGenerationsForBrandModel('Li Auto', 'L9'), contains('I'));
    expect(autoGenerationsForBrandModel('Voyah', 'Free'), contains('I'));
  });

  test('changan contains required current crossover and sedan lineup', () {
    expect(
        autoModelsForBrand('Changan'),
        containsAll(<String>[
          'UNI-Z',
          'CS35 Plus',
          'CS55 Plus',
          'CS75 Plus',
          'CS95',
          'Lamore',
        ]));
  });

  test('chery haval and geely contain актуальные модели', () {
    expect(
        autoModelsForBrand('Chery'),
        containsAll(<String>[
          'Tiggo 7',
          'Tiggo 4 Pro',
          'Tiggo 7L',
          'Tiggo 8 Pro Max',
          'Tiggo 9',
          'Arrizo 8',
        ]));
    expect(
        autoModelsForBrand('Haval'),
        containsAll(<String>[
          'Jolion',
          'Dargo',
          'Dargo X',
          'H3',
          'H5',
          'H7',
        ]));
    expect(
        autoModelsForBrand('Geely'),
        containsAll(<String>[
          'Monjaro',
          'Cityray',
          'Tugella',
          'EX5',
          'EX5 EM-i',
        ]));
  });

  test('canonical chinese brands are present once without bad duplicates', () {
    expect(kAutoBrandsPopular.where((brand) => brand == 'Omoda'), hasLength(1));
    expect(
      kAutoBrandsPopular.where((brand) => brand == 'Jaecoo'),
      hasLength(1),
    );
    expect(
      kAutoBrandsPopular.where((brand) => brand == 'Dongfeng'),
      hasLength(1),
    );
  });

  test('requested market brands expose canonical models', () {
    expect(autoModelsForBrand('Mercedes-Benz'), contains('GLB'));
    expect(autoModelsForBrand('BMW'), contains('XM'));
    expect(autoModelsForBrand('GWM'), containsAll(<String>['Poer', 'Ora 03']));
    expect(autoModelsForBrand('Bestune'), contains('T90'));
    expect(autoModelsForBrand('Belgee'), contains('X50'));
    expect(autoModelsForBrand('Rox'), contains('01'));

    expect(autoGenerationsForBrandModel('BMW', 'XM'), contains('G09'));
    expect(autoGenerationsForBrandModel('Rox', '01'), contains('I'));
  });
}
