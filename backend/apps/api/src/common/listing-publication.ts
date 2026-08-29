import { ListingStatus, Prisma } from '@prisma/client';

export const LISTING_DRAFT_TITLE_PLACEHOLDER = 'Черновик объявления';
export const LISTING_PUBLICATION_NOT_READY = 'LISTING_PUBLICATION_NOT_READY';

const categoriesWithKnownSubcategories = new Map<string, Set<string>>([
  ['Авто', new Set([
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
    'Эвакуаторы',
    'Электромобили',
    'Микроавтобусы',
    'Погрузчики и складская техника',
    'Авто под заказ',
  ])],
  ['Запчасти', new Set([
    'Запчасти авто',
    'Авторазбор',
    'Запчасти для коммерческого транспорта',
    'Запчасти для мототехники',
    'Запчасти для спецтехники',
    'Шины',
    'Диски',
    'Колёса в сборе',
    'Аккумуляторы',
    'Масла и автохимия',
    'Аудио и мультимедиа',
    'Электроника и автоэлектрика',
    'Инструменты',
    'Тюнинг',
    'Багажники и фаркопы',
    'Аксессуары',
    'Кузовные детали',
    'Двигатель и навесное',
    'Подвеска и рулевое',
    'Тормозная система',
    'Трансмиссия',
    'Салон',
    'Оптика',
    'Расходники',
    'Автостекла',
    'Выхлопная система',
    'Система охлаждения',
    'Топливная система',
  ])],
  ['Электроника', new Set([
    'Телефоны',
    'Смартфоны',
    'Стационарные телефоны',
    'Планшеты и электронные книги',
    'Ноутбуки',
    'Компьютеры',
    'Комплектующие',
    'Оргтехника и расходники',
    'Мониторы',
    'Телевизоры',
    'Игровые приставки',
    'Игры и аксессуары',
    'Фото и видеокамеры',
    'Аудиотехника',
    'Наушники и аксессуары',
    'Умные часы и браслеты',
    'Товары для стриминга',
    'Сетевое оборудование',
    'Проекторы',
    'Техника для дома',
    'Кабели, зарядки, адаптеры',
    'Кнопочные телефоны',
    'Принтеры и МФУ',
    'Компьютерная периферия',
    'Клавиатуры',
    'Мыши',
    'Веб-камеры',
    'Накопители и SSD',
    'Флешки и карты памяти',
    'Умный дом',
    'Квадрокоптеры',
    'VR-очки',
    '3D-принтеры',
    'Запчасти для электроники',
    'Стабилизаторы и ИБП',
  ])],
  ['Недвижимость', new Set([
    'Квартиры',
    'Квартира',
    'Комнаты',
    'Комната',
    'Дома',
    'Дом',
    'Части дома',
    'Таунхаусы',
    'Таунхаус',
    'Дачи',
    'Дача',
    'Коттеджи',
    'Коттедж',
    'Земельные участки',
    'Земельный участок',
    'Гаражи и машиноместа',
    'Гараж',
    'Машино-место',
    'Коммерческие помещения',
    'Коммерческая недвижимость',
    'Офисы',
    'Офис',
    'Склады',
    'Склад',
    'Производственные помещения',
    'Производственное помещение',
    'Торговое помещение',
    'Готовый бизнес',
    'Недостроенный объект',
    'Недвижимость за рубежом',
    'Другое',
    'Апартаменты',
    'Общежития',
    'Помещения свободного назначения',
    'Коворкинги',
    'Земля коммерческого назначения',
  ])],
]);

const categoriesWithoutStrictSubcategories = new Set([
  'Продукты питания',
  'Военторг',
  'Строительные материалы',
  'Ювелирные изделия',
  'Хендмейд',
  'Детский мир',
  'Одежда',
  'Хобби и отдых',
  'Животные',
  'Пчёлы и мёд',
  'Красота и здоровье',
  'Спорт и отдых',
  'Работа',
  'Услуги',
  'Бытовая техника',
  'Сад и огород',
  'Для дома и дачи',
  'Для бизнеса',
  'Другое',
]);

const toPositiveNumber = (value: number | bigint | null | undefined) => {
  if (typeof value === 'bigint') {
    return value > BigInt(0);
  }
  return typeof value === 'number' && Number.isFinite(value) && value > 0;
};

export type PublicationReadyListing = {
  title: string | null;
  description: string | null;
  category: string | null;
  subcategory?: string | null;
  price: number | bigint | null;
  city?: string | null;
  photos?: unknown[] | null;
};

export const isListingReadyForPublication = (
  listing: PublicationReadyListing,
) => {
  const title = listing.title?.trim() ?? '';
  if (!title || title === LISTING_DRAFT_TITLE_PLACEHOLDER) {
    return false;
  }

  if (!(listing.description?.trim() ?? '')) {
    return false;
  }

  const category = listing.category?.trim() ?? '';
  if (!category || category === 'Все') {
    return false;
  }

  const knownSubcategories = categoriesWithKnownSubcategories.get(category);
  if (knownSubcategories) {
    const subcategory = listing.subcategory?.trim() ?? '';
    if (!knownSubcategories.has(subcategory)) {
      return false;
    }
  } else if (!categoriesWithoutStrictSubcategories.has(category)) {
    return false;
  }

  if (!toPositiveNumber(listing.price)) {
    return false;
  }

  if (!(listing.city?.trim() ?? '')) {
    return false;
  }

  if ((listing.photos?.length ?? 0) < 1) {
    return false;
  }

  return true;
};

export const requiresPublicationReadiness = (status: ListingStatus) =>
  status === ListingStatus.PENDING || status === ListingStatus.APPROVED;

export const listingPublicationReadyWhere = (): Prisma.ListingWhereInput => ({
  title: {
    notIn: ['', LISTING_DRAFT_TITLE_PLACEHOLDER],
  },
  description: {
    not: '',
  },
  category: {
    in: [
      ...categoriesWithKnownSubcategories.keys(),
      ...categoriesWithoutStrictSubcategories,
    ],
  },
  price: {
    gt: BigInt(0),
  },
  city: {
    not: '',
  },
  photos: {
    some: {},
  },
});
