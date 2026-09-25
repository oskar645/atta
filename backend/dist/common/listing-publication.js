"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.listingModerationReadySql = exports.listingPublicationReadyWhere = exports.requiresPublicationReadiness = exports.isListingReadyForPublication = exports.LISTING_PUBLICATION_NOT_READY = exports.LISTING_DRAFT_TITLE_PLACEHOLDER = void 0;
const client_1 = require("@prisma/client");
exports.LISTING_DRAFT_TITLE_PLACEHOLDER = 'Черновик объявления';
exports.LISTING_PUBLICATION_NOT_READY = 'LISTING_PUBLICATION_NOT_READY';
const categoriesWithKnownSubcategories = new Map([
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
const toPositiveNumber = (value) => {
    if (typeof value === 'bigint') {
        return value > BigInt(0);
    }
    return typeof value === 'number' && Number.isFinite(value) && value > 0;
};
const isListingReadyForPublication = (listing) => {
    const title = listing.title?.trim() ?? '';
    if (!title || title === exports.LISTING_DRAFT_TITLE_PLACEHOLDER) {
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
    }
    else if (!categoriesWithoutStrictSubcategories.has(category)) {
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
exports.isListingReadyForPublication = isListingReadyForPublication;
const requiresPublicationReadiness = (status) => status === client_1.ListingStatus.PENDING || status === client_1.ListingStatus.APPROVED;
exports.requiresPublicationReadiness = requiresPublicationReadiness;
const listingPublicationReadyWhere = () => ({
    title: {
        notIn: ['', exports.LISTING_DRAFT_TITLE_PLACEHOLDER],
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
exports.listingPublicationReadyWhere = listingPublicationReadyWhere;
// SQL is required here to match String.trim() for legacy, unnormalised rows.
// Alias `l` is the listings table. Keep publication writes and public feed unchanged.
const listingModerationReadySql = () => {
    const whitespace = '\u0009\u000a\u000b\u000c\u000d\u0020\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000\ufeff';
    const trim = (column) => client_1.Prisma.sql `btrim(${column}, ${whitespace})`;
    const category = trim(client_1.Prisma.sql `l.category`);
    const subcategory = trim(client_1.Prisma.sql `l.subcategory`);
    const categoryRules = [
        client_1.Prisma.sql `${category} IN (${client_1.Prisma.join([...categoriesWithoutStrictSubcategories])})`,
        ...[...categoriesWithKnownSubcategories].map(([name, children]) => client_1.Prisma.sql `(${category} = ${name} AND ${subcategory} IN (${client_1.Prisma.join([...children])}))`),
    ];
    return client_1.Prisma.sql `
    l.status = 'PENDING'::"ListingStatus"
    AND l.deleted_at IS NULL AND l.archived_at IS NULL
    AND ${trim(client_1.Prisma.sql `l.title`)} NOT IN ('', ${exports.LISTING_DRAFT_TITLE_PLACEHOLDER})
    AND ${trim(client_1.Prisma.sql `l.description`)} <> ''
    AND (${client_1.Prisma.join(categoryRules, ' OR ')})
    AND l.price > 0
    AND ${trim(client_1.Prisma.sql `l.city`)} <> ''
    AND EXISTS (SELECT 1 FROM listing_photos p WHERE p.listing_id = l.id)
  `;
};
exports.listingModerationReadySql = listingModerationReadySql;
//# sourceMappingURL=listing-publication.js.map