import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/recurring.dart';

void main() {
  test('clampDayToMonth narrows day to month end', () {
    expect(clampDayToMonth(31, 202601), 31); // 1 月 31 天
    expect(clampDayToMonth(31, 202602), 28); // 平年 2 月
    expect(clampDayToMonth(31, 202402), 29); // 闰年 2 月
    expect(clampDayToMonth(30, 202602), 28); // 30 日进 2 月
    expect(clampDayToMonth(15, 202602), 15); // 正常
  });

  test('monthsBetween returns exclusive-from ascending months', () {
    expect(monthsBetween(202608, 202608), isEmpty); // from >= to
    expect(monthsBetween(202608, 202607), isEmpty); // 反向
    expect(monthsBetween(202601, 202603), [202602, 202603]);
    expect(monthsBetween(202512, 202602), [202601, 202602]); // 跨年
  });
}
