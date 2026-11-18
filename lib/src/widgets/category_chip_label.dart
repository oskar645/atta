import 'package:flutter/material.dart';

import '../theme/soft_shadows.dart';

IconData? categoryIcon(String category) => switch (category) {
      'Все' => null,
      'Авто' => Icons.directions_car_rounded,
      'Запчасти' => Icons.build_rounded,
      'Электроника' => Icons.devices_rounded,
      'Недвижимость' => Icons.home_work_rounded,
      'Продукты питания' => Icons.restaurant_rounded,
      'Военторг' => Icons.shield_rounded,
      'Строительные материалы' => Icons.construction_rounded,
      'Ювелирные изделия' => Icons.diamond_rounded,
      'Хендмейд' => Icons.palette_rounded,
      'Детский мир' => Icons.toys_rounded,
      'Одежда' => Icons.checkroom_rounded,
      'Хобби и отдых' => Icons.interests_rounded,
      'Животные' => Icons.pets_rounded,
      'Пчёлы и мёд' => Icons.hive_rounded,
      'Красота и здоровье' => Icons.spa_rounded,
      'Спорт и отдых' => Icons.sports_soccer_rounded,
      'Работа' => Icons.work_rounded,
      'Услуги' => Icons.handyman_rounded,
      'Бытовая техника' => Icons.kitchen_rounded,
      'Сад и огород' => Icons.yard_rounded,
      'Для дома и дачи' => Icons.chair_rounded,
      'Для бизнеса' => Icons.business_center_rounded,
      _ => Icons.category_rounded,
    };

Color categoryChipBackgroundColor(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.light
      ? Colors.white
      : theme.colorScheme.surfaceContainer;
}

class CategoryChipSurface extends StatelessWidget {
  const CategoryChipSurface({
    super.key,
    required this.selected,
    required this.child,
    this.boxShadows,
    this.supportRoundedShadowCorners = false,
  });

  final bool selected;
  final Widget child;
  final List<BoxShadow>? boxShadows;
  final bool supportRoundedShadowCorners;

  @override
  Widget build(BuildContext context) {
    final shadows = selected
        ? const <BoxShadow>[]
        : boxShadows ?? attaCoolSoftCardShadows(context);
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: shadows,
      ),
      child: child,
    );
    if (!supportRoundedShadowCorners || selected) return surface;
    return AttaRoundedCornerShadowSupport(
      radius: 999,
      shadows: shadows,
      child: surface,
    );
  }
}

class CategoryChipLabel extends StatelessWidget {
  const CategoryChipLabel({
    super.key,
    required this.category,
    required this.selected,
    this.selectedForegroundColor,
    this.unselectedForegroundColor,
  });

  final String category;
  final bool selected;
  final Color? selectedForegroundColor;
  final Color? unselectedForegroundColor;

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? selectedForegroundColor : unselectedForegroundColor;
    final icon = categoryIcon(category);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 5),
        ],
        Text(
          category,
          style: TextStyle(
            color: color,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
