/// 是否超支：有预算（>0）且支出严格大于预算。
bool isOverBudget(int spentCents, int budgetCents) =>
    budgetCents > 0 && spentCents > budgetCents;

/// 预算进度（仅展示用）：0..1，无预算为 0。
double budgetProgress(int spentCents, int budgetCents) =>
    budgetCents <= 0 ? 0 : (spentCents / budgetCents).clamp(0.0, 1.0);
