import 'package:flutter/services.dart';

String extractRuPhoneDigits(String input) {
  var digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('8') && digits.length >= 11) {
    digits = digits.substring(1);
  } else if (digits.startsWith('7') && digits.length >= 11) {
    digits = digits.substring(1);
  }
  if (digits.length > 10) {
    digits = digits.substring(0, 10);
  }
  return digits;
}

String normalizeRuPhoneForApi(String input) {
  final localDigits = extractRuPhoneDigits(input);
  if (localDigits.length != 10) return '';
  return '7$localDigits';
}

String formatRuPhoneForField(String input) {
  final digits = extractRuPhoneDigits(input);
  if (digits.isEmpty) return '';

  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i == 3) {
      buffer.write(' ');
    } else if (i == 6 || i == 8) {
      buffer.write('-');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

String formatRuPhoneForDisplay(String input) {
  final body = formatRuPhoneForField(input);
  return body.isEmpty ? '+7' : '+7 $body';
}

class RuPhoneInputFormatter extends TextInputFormatter {
  const RuPhoneInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = extractRuPhoneDigits(newValue.text);
    final formatted = formatRuPhoneForField(digits);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
