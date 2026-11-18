import 'package:atta/src/utils/map_button_scroll_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ignores small scroll jitter and toggles after clear movement', () {
    final gate = MapButtonScrollGate();

    expect(gate.update(4, pixels: 400), isNull);
    expect(gate.update(-3, pixels: 400), isNull);
    expect(gate.update(5, pixels: 400), isNull);
    expect(gate.update(7, pixels: 400), isNull);
    expect(gate.update(6, pixels: 400), isFalse);

    expect(gate.update(-9, pixels: 400), isNull);
    expect(gate.update(-10, pixels: 400), isTrue);
  });

  test('does not toggle on zero delta', () {
    expect(MapButtonScrollGate().update(0), isNull);
  });

  test('stays visible for pull-to-refresh and while first row is visible', () {
    final gate = MapButtonScrollGate();

    expect(gate.update(30, pixels: -40), isTrue);
    expect(gate.update(30, pixels: 0), isTrue);
    expect(gate.update(30, pixels: 250), isTrue);
    expect(gate.update(30, pixels: 321), isFalse);
  });
}
