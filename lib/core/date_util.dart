/// 本地当前日期 → yyyyMMdd，如 20260813。
int todayYyyymmdd() {
  final n = DateTime.now();
  return n.year * 10000 + n.month * 100 + n.day;
}

/// 20260813 → 202608
int yyyymmOf(int yyyymmdd) => yyyymmdd ~/ 100;

/// 202608 → "2026年8月"
String formatYyyymm(int yyyymm) {
  final y = yyyymm ~/ 100;
  final m = yyyymm % 100;
  return '$y年$m月';
}
