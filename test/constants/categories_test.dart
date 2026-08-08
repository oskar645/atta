import 'package:atta/src/constants/categories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transport subcategories include tow trucks after existing items', () {
    final transport = kSubcategories['Авто'];

    expect(transport, isNotNull);
    expect(transport!.last, 'Эвакуаторы');
    expect(
      transport.take(18).toList(),
      const <String>[
        'Легковые автомобили',
        'Коммерческий транспорт',
        'Грузовики',
        'Мотоциклы',
        'Мопеды и скутеры',
        'Квадроциклы',
        'Снегоходы',
        'Спецтехника',
        'Сельхозтехника',
        'Водный транспорт',
        'Автобусы',
        'Прицепы',
        'Автодома',
        'Велосипеды',
        'Аренда авто',
        'Аренда спецтехники',
        'Аренда грузового транспорта',
        'Запчасти и аксессуары для транспорта',
      ],
    );
  });

  test('real estate kinds are consolidated into product kind list', () {
    final realEstate = kSubcategories['Недвижимость'];

    expect(realEstate, isNotNull);
    expect(
      realEstate,
      containsAll(const <String>[
        'Квартиры',
        'Комнаты',
        'Дома',
        'Части дома',
        'Таунхаусы',
        'Дачи',
        'Коттеджи',
        'Земельные участки',
        'Гаражи и машиноместа',
        'Коммерческие помещения',
        'Офисы',
        'Склады',
        'Производственные помещения',
        'Недвижимость за рубежом',
        'Квартира',
        'Дом',
        'Комната',
        'Дача',
        'Коттедж',
        'Таунхаус',
        'Земельный участок',
        'Коммерческая недвижимость',
        'Гараж',
        'Машино-место',
        'Склад',
        'Производственное помещение',
        'Офис',
        'Торговое помещение',
        'Готовый бизнес',
        'Недостроенный объект',
        'Другое',
      ]),
    );
    expect(realEstate!.toSet(), hasLength(realEstate.length));
  });

  test('real estate deal types are standard options', () {
    const dealTypes = <String>[
      'Продажа',
      'Аренда',
      'Посуточно',
      'Обмен',
    ];

    expect(dealTypes.toSet(), hasLength(dealTypes.length));
  });

  test('bees and honey is a standalone category with subcategories', () {
    expect(kCategories, contains('Пчёлы и мёд'));
    expect(kCategories.indexOf('Пчёлы и мёд'),
        isNot(kCategories.indexOf('Животные')));

    final beekeeping = kSubcategories['Пчёлы и мёд'];
    expect(beekeeping, isNotNull);
    expect(
      beekeeping,
      const <String>[
        'Пчёлы',
        'Пчелиные матки',
        'Пчелопакеты',
        'Пчелиные семьи',
        'Ульи',
        'Рамки',
        'Вощина',
        'Медогонки',
        'Инвентарь для пчеловодства',
        'Мёд',
        'Воск',
        'Продукты пчеловодства',
        'Корм и препараты для пчёл',
        'Другое для пчеловодства',
      ],
    );
  });

  test('animals category includes requested additions without duplicates', () {
    final animals = kSubcategories['Животные'];

    expect(animals, isNotNull);
    expect(
      animals,
      containsAll(const <String>[
        'Куры',
        'Другие домашние птицы',
        'Грызуны',
        'Рептилии',
        'Рыбы и аквариумистика',
        'Другие животные',
        'Товары для животных',
      ]),
    );
    expect(animals!.toSet(), hasLength(animals.length));
    expect(animals[animals.length - 2], 'Другие животные');
    expect(animals.last, 'Товары для животных');
  });

  test('categories and subcategories have no duplicate entries', () {
    expect(kCategories.toSet(), hasLength(kCategories.length));
    for (final entry in kSubcategories.entries) {
      expect(entry.value.toSet(), hasLength(entry.value.length));
    }
  });
}
