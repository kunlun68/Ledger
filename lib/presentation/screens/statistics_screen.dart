import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../application/providers.dart';
import '../../core/date_util.dart';
import '../../core/money.dart';
import '../../core/stats.dart';
import '../../data/database.dart';
import '../theme/app_theme.dart';

/// 分类色板：饼图/柱状图共用，按 index 轮换
const pieColors = <Color>[
  Color(0xFF1E88E5), Color(0xFF43A047), Color(0xFFFB8C00), Color(0xFF8E24AA),
  Color(0xFFE53935), Color(0xFF00ACC1), Color(0xFF6D4C41), Color(0xFF546E7A),
  Color(0xFFF4511E), Color(0xFF7CB342), Color(0xFF5E35B1), Color(0xFFD81B60),
];

/// 统计页：本月分类占比饼图 + 近 6 个月收支柱状图 + 支出分类排行。
/// 显示月份由 [currentMonthProvider] 决定（与首页共享）。
class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(currentMonthProvider);
    final cats = ref.watch(allCategoriesProvider).value ?? const <Category>[];
    final all = ref.watch(allTransactionsProvider).value ?? const <Transaction>[];
    final byCategory = ref.watch(categoryExpenseProvider);
    final trend = monthlyTrend(all, months: 6);

    String catName(int id) =>
        cats.where((c) => c.id == id).map((c) => c.name).firstOrNull ?? '未分类';

    final ranking = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(title: Text('统计 · ${formatYyyymm(month)}')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _SectionCard(title: '本月支出分类占比', child: ranking.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('本月暂无支出记录')))
              : SizedBox(
                  height: 220,
                  child: PieChart(PieChartData(
                    sections: [
                      for (var i = 0; i < ranking.length; i++)
                        PieChartSectionData(
                          value: ranking[i].value.toDouble(),
                          color: pieColors[i % pieColors.length],
                          title: catName(ranking[i].key),
                          titleStyle: const TextStyle(fontSize: 11, color: Colors.white),
                          radius: 40,
                        ),
                    ],
                    centerSpaceRadius: 40,
                  )))),
          _SectionCard(title: '近 6 个月收支趋势', child: SizedBox(
              height: 200,
              child: BarChart(BarChartData(
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= trend.length) return const SizedBox.shrink();
                      final m = trend[i].yyyymm % 100;
                      return Padding(padding: const EdgeInsets.only(top: 4),
                          child: Text('$m月', style: const TextStyle(fontSize: 10)));
                    },
                  )),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  for (var i = 0; i < trend.length; i++) ...[
                    BarChartGroupData(x: i, barsSpace: 2, barRods: [
                      BarChartRodData(
                          toY: (trend[i].incomeCents / 100).toDouble(),
                          color: AppTheme.incomeColor, width: 12),
                      BarChartRodData(
                          toY: (trend[i].expenseCents / 100).toDouble(),
                          color: AppTheme.expenseColor, width: 12),
                    ]),
                  ],
                ],
              )))),
          _SectionCard(title: '支出分类排行', child: ranking.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('暂无数据'))
              : Column(children: [
                  for (final e in ranking)
                    ListTile(
                      dense: true,
                      leading: CircleAvatar(
                          backgroundColor: pieColors[ranking.indexOf(e) % pieColors.length],
                          child: Text(catName(e.key).characters.first,
                              style: const TextStyle(color: Colors.white, fontSize: 12))),
                      title: Text(catName(e.key)),
                      trailing: Text(formatCents(e.value),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                ])),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            child,
          ]),
        ),
      );
}
