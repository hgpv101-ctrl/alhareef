// نقل fp_due_groups / fp_forecast / fp_visit_plan من البرنامج الأصلي
import 'engine.dart';
import 'utils.dart';

class DueGroups {
  final List<CustFin> today, late, tomorrow;
  final double todayAmt, lateAmt, tomorrowAmt;
  final Map<String, double> dueAmt;
  DueGroups(this.today, this.late, this.tomorrow, this.todayAmt, this.lateAmt, this.tomorrowAmt, this.dueAmt);
}

DueGroups dueGroups(List<CustFin> all, DateTime asOf) {
  final tom = asOf.add(const Duration(days: 1));
  final t = <CustFin>[], l = <CustFin>[], m = <CustFin>[];
  final amt = <String, double>{};
  for (final c in all) {
    if (c.remaining <= 0.004) continue;
    final due = (r2(c.monthly - c.partial)) < 0 ? 0.0 : r2(c.monthly - c.partial);
    amt[c.code] = due;
    final nd = c.nextDue;
    if (c.arrears > 0) {
      l.add(c);
    } else if (nd != null && isoDate(nd) == isoDate(asOf)) {
      t.add(c);
    } else if (nd != null && isoDate(nd) == isoDate(tom)) {
      m.add(c);
    }
  }
  l.sort((a, b) => b.arrears.compareTo(a.arrears));
  t.sort((a, b) => a.name.compareTo(b.name));
  m.sort((a, b) => a.name.compareTo(b.name));
  double s(List<CustFin> x, double Function(CustFin) f) => r2(x.fold<double>(0.0, (p, e) => p + f(e)));
  return DueGroups(t, l, m, s(t, (c) => amt[c.code]!), s(l, (c) => c.arrears), s(m, (c) => amt[c.code]!), amt);
}

class ForecastRow {
  final String ym;
  final double amount;
  final int count;
  ForecastRow(this.ym, this.amount, this.count);
}

(List<ForecastRow>, double) forecast(List<CustFin> all, DateTime asOf, {int? months = 6}) {
  final buckets = <(int, int), List<num>>{};
  var late = 0.0;
  for (final c in all) {
    if (c.remaining <= 0.004 || c.firstDue == null || c.months <= 0) continue;
    late += c.arrears;
    final start = c.paidCount > c.dueN ? c.paidCount : c.dueN;
    for (var k = start; k < c.months; k++) {
      final amt = c.sched[k] - (k == c.paidCount ? c.partial : 0.0);
      if (amt <= 0) continue;
      final d = addMonths(c.firstDue!, k);
      final key = d.isAfter(asOf) ? (d.year, d.month) : (asOf.year, asOf.month);
      final b = buckets.putIfAbsent(key, () => [0.0, 0]);
      b[0] += amt;
      b[1] += 1;
    }
  }
  final cur = (asOf.year, asOf.month);
  var keys = buckets.keys.where((k) => k.$1 > cur.$1 || (k.$1 == cur.$1 && k.$2 >= cur.$2)).toList()
    ..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  if (months != null) keys = keys.where((k) => (k.$1 - cur.$1) * 12 + (k.$2 - cur.$2) < months).toList();
  return ([for (final k in keys) ForecastRow('${k.$2.toString().padLeft(2, '0')}-${k.$1}', r2(buckets[k]![0].toDouble()), buckets[k]![1].toInt())], r2(late));
}

/// مندوب ← منطقة ← عملاء متأخرين
List<(String, List<(String, List<CustFin>)>)> visitPlan(List<CustFin> late, {String? rep}) {
  final src = rep == null ? late : late.where((c) => c.rep == rep).toList();
  final plan = <String, Map<String, List<CustFin>>>{};
  for (final c in src) {
    plan.putIfAbsent(c.rep.isEmpty ? 'بدون مندوب' : c.rep, () => {}).putIfAbsent(c.region.isEmpty ? 'بدون منطقة' : c.region, () => []).add(c);
  }
  final reps = plan.keys.toList()..sort();
  return [
    for (final r in reps)
      (
        r,
        () {
          final regs = plan[r]!;
          final order = regs.keys.toList()
            ..sort((a, b) {
              final n = regs[b]!.length.compareTo(regs[a]!.length);
              if (n != 0) return n;
              final s = regs[b]!.fold<double>(0.0, (p, c) => p + c.arrears).compareTo(regs[a]!.fold<double>(0.0, (p, c) => p + c.arrears));
              return s != 0 ? s : a.compareTo(b);
            });
          return [for (final g in order) (g, (regs[g]!..sort((a, b) => a.address.compareTo(b.address))))];
        }()
      )
  ];
}

String summaryText(DueGroups g) {
  final o = <String>[
    '☀️ ملخص النهارده:',
    '• مستحق النهارده: ${g.today.length} قسط — المتوقع ${fmtMoney(g.todayAmt)} جنيه',
    '• متأخرين: ${g.late.length} عميل — إجمالي المتأخر ${fmtMoney(g.lateAmt)} جنيه',
    '• مستحق بكرة: ${g.tomorrow.length} قسط (${fmtMoney(g.tomorrowAmt)} جنيه)',
  ];
  if (g.late.isNotEmpty) {
    o.add('أكتر المتأخرين:');
    for (final c in g.late.take(5)) {
      o.add('   - ${c.name} (${c.code}): ${fmtMoney(c.arrears)} جنيه');
    }
  }
  return o.join('\n');
}
