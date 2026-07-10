import 'package:flutter/material.dart';

class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.radius = 12,
    this.margin,
  });

  final double? width;
  final double? height;
  final double radius;
  final EdgeInsetsGeometry? margin;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mediaQuery = MediaQuery.maybeOf(context);
    final reduceMotion = mediaQuery?.disableAnimations == true ||
        mediaQuery?.accessibleNavigation == true;
    if (reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = Color.lerp(
          scheme.surfaceContainerHighest,
          scheme.outlineVariant,
          Theme.of(context).brightness == Brightness.dark ? 0.22 : 0.45,
        ) ??
        scheme.surfaceContainerHighest;
    final highlight = Color.lerp(
          base,
          Colors.white,
          Theme.of(context).brightness == Brightness.dark ? 0.12 : 0.42,
        ) ??
        base;

    return Container(
      margin: widget.margin,
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final mediaQuery = MediaQuery.maybeOf(context);
          final reduceMotion = mediaQuery?.disableAnimations == true ||
              mediaQuery?.accessibleNavigation == true;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: reduceMotion
                  ? LinearGradient(colors: [base, base])
                  : LinearGradient(
                      begin: Alignment(-1.2 + (_controller.value * 2.4), -0.2),
                      end: Alignment(-0.2 + (_controller.value * 2.4), 0.2),
                      colors: <Color>[
                        base,
                        highlight,
                        base,
                      ],
                      stops: const <double>[0.1, 0.45, 0.9],
                    ),
            ),
          );
        },
      ),
    );
  }
}

class SkeletonLine extends StatelessWidget {
  const SkeletonLine({
    super.key,
    this.width,
    this.height = 12,
    this.radius = 999,
    this.margin,
  });

  final double? width;
  final double height;
  final double radius;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(
      width: width,
      height: height,
      radius: radius,
      margin: margin,
    );
  }
}

class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({
    super.key,
    this.size = 40,
    this.margin,
  });

  final double size;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(
      width: size,
      height: size,
      radius: size / 2,
      margin: margin,
    );
  }
}

class SkeletonListingCard extends StatelessWidget {
  const SkeletonListingCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: SkeletonBox(radius: 12),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(8, 8, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonLine(height: 14),
                  SizedBox(height: 8),
                  SkeletonLine(width: 78, height: 18),
                  SizedBox(height: 10),
                  SkeletonLine(width: 90, height: 12),
                  SizedBox(height: 8),
                  SkeletonLine(width: 64, height: 11),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SkeletonMyListingTile extends StatelessWidget {
  const SkeletonMyListingTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: const Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 92, height: 69, radius: 12),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLine(height: 14),
                    SizedBox(height: 8),
                    SkeletonLine(width: 92, height: 18),
                    SizedBox(height: 8),
                    SkeletonLine(width: 84, height: 12),
                    SizedBox(height: 6),
                    SkeletonLine(width: 118, height: 12),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: SkeletonLine(height: 38, radius: 12)),
              SizedBox(width: 8),
              Expanded(child: SkeletonLine(height: 38, radius: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

class SkeletonListingGrid extends StatelessWidget {
  const SkeletonListingGrid({
    super.key,
    this.itemCount = 6,
    this.padding = const EdgeInsets.fromLTRB(10, 10, 10, 10),
    this.physics = const AlwaysScrollableScrollPhysics(),
    this.childAspectRatio = 0.72,
    this.shrinkWrap = false,
  });

  final int itemCount;
  final EdgeInsetsGeometry padding;
  final ScrollPhysics physics;
  final double childAspectRatio;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: padding,
      physics: physics,
      shrinkWrap: shrinkWrap,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: itemCount,
      itemBuilder: (_, __) => const SkeletonListingCard(),
    );
  }
}

class SkeletonChatRow extends StatelessWidget {
  const SkeletonChatRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      leading: SkeletonCircle(size: 48),
      title: SkeletonLine(height: 14),
      subtitle: Padding(
        padding: EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonLine(height: 12),
            SizedBox(height: 6),
            SkeletonLine(width: 120, height: 12),
          ],
        ),
      ),
      trailing: SizedBox(
        width: 44,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SkeletonLine(width: 36, height: 10),
            SizedBox(height: 8),
            SkeletonCircle(size: 18),
          ],
        ),
      ),
    );
  }
}

class SkeletonMessageBubble extends StatelessWidget {
  const SkeletonMessageBubble({
    super.key,
    this.isMine = false,
    this.isImage = false,
  });

  final bool isMine;
  final bool isImage;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: isImage
              ? const SkeletonBox(width: 180, height: 140, radius: 18)
              : const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 220, height: 48, radius: 18),
                  ],
                ),
        ),
      ),
    );
  }
}

class SkeletonProfileHeader extends StatelessWidget {
  const SkeletonProfileHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonCircle(size: 84),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(width: 160, height: 24),
                SizedBox(height: 10),
                SkeletonLine(width: 120, height: 14),
                SizedBox(height: 14),
                SkeletonLine(width: 86, height: 28),
                SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: SkeletonLine(height: 42, radius: 12)),
                    SizedBox(width: 8),
                    Expanded(child: SkeletonLine(height: 42, radius: 12)),
                    SizedBox(width: 8),
                    Expanded(child: SkeletonLine(height: 42, radius: 12)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SkeletonWalletCard extends StatelessWidget {
  const SkeletonWalletCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonLine(width: 72, height: 13),
          SizedBox(height: 10),
          SkeletonLine(width: 140, height: 30),
          SizedBox(height: 14),
          SkeletonLine(height: 12),
          SizedBox(height: 8),
          SkeletonLine(width: 170, height: 12),
          SizedBox(height: 8),
          SkeletonLine(width: 120, height: 12),
        ],
      ),
    );
  }
}

class SkeletonNotificationRow extends StatelessWidget {
  const SkeletonNotificationRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonCircle(size: 22),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonLine(width: 180, height: 14),
                  SizedBox(height: 10),
                  SkeletonLine(height: 12),
                  SizedBox(height: 6),
                  SkeletonLine(width: 90, height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SkeletonAdminModerationCard extends StatelessWidget {
  const SkeletonAdminModerationCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      margin: EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonLine(width: 180, height: 16),
            SizedBox(height: 8),
            SkeletonLine(width: 120, height: 12),
            SizedBox(height: 6),
            SkeletonLine(width: 150, height: 12),
            SizedBox(height: 6),
            SkeletonLine(width: 90, height: 12),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: SkeletonLine(height: 38, radius: 12)),
                SizedBox(width: 8),
                Expanded(child: SkeletonLine(height: 38, radius: 12)),
                SizedBox(width: 8),
                Expanded(child: SkeletonLine(height: 38, radius: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SkeletonSupportTicketRow extends StatelessWidget {
  const SkeletonSupportTicketRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonLine(width: 120, height: 11),
          SizedBox(height: 8),
          SkeletonLine(height: 13),
          SizedBox(height: 6),
          SkeletonLine(width: 160, height: 13),
        ],
      ),
    );
  }
}

class SkeletonPhotoGrid extends StatelessWidget {
  const SkeletonPhotoGrid({
    super.key,
    this.itemCount = 4,
    this.crossAxisCount = 3,
    this.aspectRatio = 1,
    this.padding = const EdgeInsets.all(12),
  });

  final int itemCount;
  final int crossAxisCount;
  final double aspectRatio;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: padding,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: aspectRatio,
      ),
      itemCount: itemCount,
      itemBuilder: (_, __) => const SkeletonBox(radius: 14),
    );
  }
}
