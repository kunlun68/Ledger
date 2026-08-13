import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/money.dart';

void main() {
  test('parseCents basic', () {
    expect(parseCents('12.34'), 1234);
    expect(parseCents('12'), 1200);
    expect(parseCents('0.5'), 50);
    expect(parseCents('0'), 0);
  });
  test('parseCents rejects invalid input', () {
    expect(() => parseCents('12.345'), throwsFormatException);
    expect(() => parseCents('abc'), throwsFormatException);
    expect(() => parseCents(''), throwsFormatException);
    expect(() => parseCents('1.2.3'), throwsFormatException);
    expect(() => parseCents('.5'), throwsFormatException);
    expect(() => parseCents('-'), throwsFormatException);
  });
  test('formatCents', () {
    expect(formatCents(1234), '12.34');
    expect(formatCents(0), '0.00');
    expect(formatCents(-50), '-0.50');
    expect(formatCents(100000), '1000.00');
  });
}
