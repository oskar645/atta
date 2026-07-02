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
  return formatRussianPhone(input);
}

String formatRussianPhone(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return '';

  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  String localDigits;
  if (digits.length == 10) {
    localDigits = digits;
  } else if (digits.length == 11 &&
      (digits.startsWith('7') || digits.startsWith('8'))) {
    localDigits = digits.substring(1);
  } else {
    return trimmed;
  }

  return '+7 ${localDigits.substring(0, 3)} ${localDigits.substring(3, 6)} '
      '${localDigits.substring(6, 8)} ${localDigits.substring(8, 10)}';
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
