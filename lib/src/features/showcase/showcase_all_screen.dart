import 'package:atta/src/features/showcase/showcase_preview_screen.dart';
import 'package:atta/src/models/showcase_item.dart';
import 'package:atta/src/services/showcase_service.dart';
import 'package:atta/src/utils/price_formatter.dart';
import 'package:atta/src/widgets/media_preview_box.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ShowcaseAllScreen extends StatefulWidget {
  const ShowcaseAllScreen({super.key});

  @override
  State<ShowcaseAllScreen> createState() => _ShowcaseAllScreenState();
}

class _ShowcaseAllScreenState extends State<ShowcaseAllScreen> {
  static const List<String> _filters = <String>[
    'Все',
    'Авто',
    'Недвижимость',
    'Электроника',
    'Услуги',
  ];

  late Future<List<ShowcaseItem>> _future;
  String _selectedFilter = 'Все';

  @override
  void initState() {
    super.initState();
    _future = context.read<ShowcaseService>().getShowcase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Витрина ATTA'),
        centerTitle: false,
      ),
      body: FutureBuilder<List<ShowcaseItem>>(
        future: _future,
        builder: (context, snapshot) {
          final allItems = snapshot.data ?? const <ShowcaseItem>[];
          final items = _selectedFilter == 'Все'
              ? allItems
              : allItems
                  .where((item) => item.category == _selectedFilter)
                  .toList();

          return Column(
            children: [
              SizedBox(
                height: 52,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (context, index) {
                    final filter = _filters[index];
                    final selected = filter == _selectedFilter;
                    return ChoiceChip(
                      label: Text(filter),
                      selected: selected,
                      onSelected: (_) {
                        setState(() => _selectedFilter = filter);
                      },
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemCount: _filters.length,
                ),
              ),
              Expanded(
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: _ShowcaseGridSkeleton(),
                      )
                    : items.isEmpty
                        ? const _EmptyShowcaseState()
                        : GridView.builder(
                            padding: const EdgeInsets.all(12),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 0.76,
                            ),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return _ShowcaseGridCard(item: item);
                            },
                          ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ShowcaseGridCard extends StatelessWidget {
  const _ShowcaseGridCard({required this.item});

  final ShowcaseItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ShowcasePreviewScreen(item: item),
            ),
          );
        },
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: MediaPreviewBox(
                  imageUrl: item.firstPhotoUrl ?? '',
                  categoryHint: 'listings',
                  borderRadius: 0,
                  emptyLabel: 'Фото недоступно',
                  errorLabel: 'Фото недоступно',
                  placeholderLabel: 'Загрузка фото...',
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.05),
                      Colors.black.withValues(alpha: 0.00),
                      Colors.black.withValues(alpha: 0.68),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 10,
                top: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Витрина',
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        shadows: [
                          Shadow(
                            blurRadius: 10,
                            color: Color(0x66000000),
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formatPrice(item.price)} ₽',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        shadows: [
                          Shadow(
                            blurRadius: 10,
                            color: Color(0x66000000),
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    if (item.city.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShowcaseGridSkeleton extends StatelessWidget {
  const _ShowcaseGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.76,
      ),
      itemBuilder: (_, __) => const SkeletonBox(radius: 16),
    );
  }
}

class _EmptyShowcaseState extends StatelessWidget {
  const _EmptyShowcaseState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Витрина пока пустая',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8),
            Text(
              'Здесь появятся объявления, которые пользователи продвигают за бонусы.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
