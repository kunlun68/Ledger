/// 把 day 收窄到 yyyymm 月份实际天数内（2 月 30 日 → 2 月末）。
int clampDayToMonth(int day, int yyyymm) {
  final year = yyyymm ~/ 100, month = yyyymm % 100;
  final lastDay = DateTime(year, month + 1, 0).day;
  return day > lastDay ? lastDay : day;
}

/// (from, to] 的缺失月份序列，升序；from >= to 返回空。
List<int> monthsBetween(int fromYyyymm, int toYyyymm) {
  final result = <int>[];
  if (fromYyyymm >= toYyyymm) return result;
  var cur = fromYyyymm;
  while (cur < toYyyymm) {
    final next = DateTime(cur ~/ 100, cur % 100 + 1, 1);
    cur = next.year * 100 + next.month;
    if (cur <= toYyyymm) result.add(cur);
  }
  return result;
}
