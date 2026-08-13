/// 金额以「分」(int) 为单位。输入 "12.34" → 1234。
///
/// 禁止用 double 参与金额计算；所有金额字段存储与运算均用整数分。
int parseCents(String input) {
  final s = input.trim();
  if (s.isEmpty || s == '-' || s == '.') throw const FormatException('invalid amount');
  final negative = s.startsWith('-');
  final body = negative ? s.substring(1) : s;
  final parts = body.split('.');
  if (parts.length > 2) throw const FormatException('invalid amount');
  final whole = parts[0];
  if (whole.isEmpty || whole.contains(RegExp(r'[^0-9]'))) {
    throw const FormatException('invalid amount');
  }
  if (parts.length == 2) {
    final frac = parts[1];
    if (frac.isEmpty || frac.length > 2 || frac.contains(RegExp(r'[^0-9]'))) {
      throw const FormatException('invalid amount');
    }
    final cents = int.parse(whole) * 100 + int.parse(frac.padRight(2, '0'));
    return negative ? -cents : cents;
  }
  final cents = int.parse(whole) * 100;
  return negative ? -cents : cents;
}

/// 1234 → "12.34"；-50 → "-0.50"；0 → "0.00"。
String formatCents(int cents) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
}
