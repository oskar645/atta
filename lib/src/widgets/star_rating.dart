import 'package:flutter/material.dart';

class StarRating extends StatelessWidget {
  final double value; // 0..5
  final double size;
  const StarRating({super.key, required this.value, this.size = 18});

  @override
  Widget build(BuildContext context) {
    final full = value.floor();
    final half = (value - full) >= 0.5;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        IconData icon;
        if (i < full)
          icon = Icons.star;
        else if (i == full && half)
          icon = Icons.star_half;
        else
          icon = Icons.star_border;

        return Icon(icon, size: size, color: Colors.amber);
      }),
    );
  }
}
