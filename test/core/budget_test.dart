import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/budget.dart';

void main() {
  test('isOverBudget: strict greater, zero budget never over', () {
    expect(isOverBudget(100, 200), isFalse);
    expect(isOverBudget(200, 200), isFalse); // 相等不算超
    expect(isOverBudget(201, 200), isTrue);
    expect(isOverBudget(9999, 0), isFalse); // 无预算
  });

  test('budgetProgress clamps to 0..1, zero budget is 0', () {
    expect(budgetProgress(50, 100), 0.5);
    expect(budgetProgress(200, 100), 1.0); // 超支钳制
    expect(budgetProgress(100, 0), 0.0);
  });
}
