import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

String formatPrice(int value) {
  final f = NumberFormat('#,###', 'ru_RU');
  return f.format(value).replaceAll(',', ' ');
}

int parseFormattedPrice(String value) {
  final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
  return int.tryParse(digitsOnly) ?? 0;
}

class PriceThousandsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final formatted = formatPrice(int.parse(digits));
    final digitsBeforeCursor = newValue.selection.baseOffset <= 0
        ? 0
        : newValue.text
            .substring(
              0,
              newValue.selection.baseOffset.clamp(0, newValue.text.length),
            )
            .replaceAll(RegExp(r'[^0-9]'), '')
            .length;

    final nextOffset = _selectionOffsetForDigits(
      formatted,
      digitsBeforeCursor,
    );

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
  }

  int _selectionOffsetForDigits(String formatted, int digitsBeforeCursor) {
    if (digitsBeforeCursor <= 0) return 0;
    var digitsSeen = 0;
    for (var i = 0; i < formatted.length; i++) {
      if (RegExp(r'[0-9]').hasMatch(formatted[i])) {
        digitsSeen += 1;
      }
      if (digitsSeen >= digitsBeforeCursor) {
        return i + 1;
      }
    }
    return formatted.length;
  }
}
