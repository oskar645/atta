import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const double _desktopWebPhotoBreakpoint = 768;

bool usesDesktopWebPhotoNavigation(BuildContext context) {
  return kIsWeb &&
      MediaQuery.sizeOf(context).width >= _desktopWebPhotoBreakpoint;
}

class DesktopWebPhotoNavigation extends StatelessWidget {
  const DesktopWebPhotoNavigation({
    super.key,
    required this.child,
    required this.currentIndex,
    required this.photoCount,
    required this.onPrevious,
    required this.onNext,
    this.enabledOverride,
  });

  final Widget child;
  final int currentIndex;
  final int photoCount;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final bool? enabledOverride;

  @override
  Widget build(BuildContext context) {
    final enabled = enabledOverride ?? usesDesktopWebPhotoNavigation(context);
    if (!enabled || photoCount <= 1) return child;

    final canGoBack = currentIndex > 0;
    final canGoForward = currentIndex < photoCount - 1;

    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent || _isEditingText()) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft && canGoBack) {
          onPrevious();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight && canGoForward) {
          onNext();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (canGoBack)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: _PhotoArrow(
                  key: const ValueKey('photo_previous'),
                  icon: Icons.chevron_left,
                  semanticLabel: 'Предыдущее фото',
                  onPressed: onPrevious,
                ),
              ),
            ),
          if (canGoForward)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _PhotoArrow(
                  key: const ValueKey('photo_next'),
                  icon: Icons.chevron_right,
                  semanticLabel: 'Следующее фото',
                  onPressed: onNext,
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _isEditingText() {
    var isEditing = false;
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null) return false;
    if (focusedContext.widget is EditableText) return true;
    focusedContext.visitAncestorElements((element) {
      if (element.widget is EditableText) {
        isEditing = true;
        return false;
      }
      return true;
    });
    return isEditing;
  }
}

class _PhotoArrow extends StatefulWidget {
  const _PhotoArrow({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  State<_PhotoArrow> createState() => _PhotoArrowState();
}

class _PhotoArrowState extends State<_PhotoArrow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Semantics(
        button: true,
        label: widget.semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.onPressed,
          child: SizedBox.square(
            dimension: 44,
            child: AnimatedOpacity(
              opacity: _hovered ? 1 : 0.78,
              duration: const Duration(milliseconds: 120),
              child: Icon(
                widget.icon,
                size: 26,
                color: Colors.white,
                shadows: const [
                  Shadow(
                    color: Color(0x99000000),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
