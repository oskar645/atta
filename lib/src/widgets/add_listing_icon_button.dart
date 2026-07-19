import 'package:atta/src/features/listings/add_listing_screen.dart';
import 'package:flutter/material.dart';

class AddListingIconButton extends StatelessWidget {
  const AddListingIconButton({super.key});

  static const double _tapSize = 52;
  static const double _iconSize = 34;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Добавить',
      constraints: const BoxConstraints(
        minWidth: _tapSize,
        minHeight: _tapSize,
      ),
      padding: EdgeInsets.zero,
      icon: const Icon(
        Icons.add_circle,
        color: Colors.blue,
        size: _iconSize,
      ),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AddListingScreen()),
      ),
    );
  }
}
