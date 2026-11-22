// المحرك المالي — نقل حرفي لـ customers_financials
import 'utils.dart';

class CustFin {
  final String code, name, phone, address, region, rep, collector, item, plan;
  final double total, down, monthly, paidInst, paidTotal, remaining, expected, arrears, partial;
  final int months, dueN, lateMonths, paidCount;
  final DateTime? firstDue, nextDue;
  final String? start;
  final List<double> sched, cum;
  final String enName, enAddress, enItem; // بيانات الإيصال الإنجليزي (منفصلة عن العربي)
  CustFin({
    this.enName = '', this.enAddress = '', this.enItem = '',
    required this.code, required this.name, required this.phone, required this.address, required this.region,
    required this.rep, required this.collector, required this.item, required this.plan, required this.total, required this.down,
    required this.monthly, required this.paidInst, required this.paidTotal, required this.remaining,
    required this.expected, required this.arrears, required this.partial, required this.months,
    required this.dueN, required this.lateMonths, required this.paidCount, required this.firstDue,
    required this.nextDue, required this.start, required this.sched, required this.cum,
  });
  bool get late => arrears > 0;
  bool get settled => remaining <= 0;
  String get instDesc => plan.isNotEmpty ? '$plan ($months شهر)' : '${fmtMoney(monthly)} × $months شهر';

  /// القسط المقترح (باقي القسط الحالي، والأخير بيشيل فروق التقريب)
  double get suggested {
    var a = r2((monthly - partial) < remaining ? (monthly - partial) : remaining);
    final d = remaining - a;
    final tol = (months * 0.005) > 0.01 ? months * 0.005 : 0.01;
    if (d > 0 && d <= tol) a = remaining;
    return a;
  }
}

CustFin computeFin(Map<String, Object?> c, double paidInstRaw, DateTime asOf, int grace) {
  double n(Object? v) => ((v ?? 0) as num).toDouble();
  final total = n(c['total_amount']), down = n(c['down_payment']);
  var monthly = n(c['monthly_installment']);
  var months = ((c['months_count'] ?? 0) as num).toInt();
  var fd = toDate(c['first_due_date']);
  if (fd == null) {
    final sd = toDate(c['start_date']);
    fd = sd == null ? null : addMonths(sd, 1);
  }
  final planTxt = (c['plan_text'] ?? '').toString();
  final sched = planSched(planTxt, monthly, months);
  months = sched.length;
  final cum = <double>[0.0];
  for (final a in sched) {
    cum.add(r2(cum.last + a));
  }
  final paidInst = r2(paidInstRaw);
  final paidTotal = r2(down + paidInst);
  final remaining = (r2(total - paidTotal)) < 0 ? 0.0 : r2(total - paidTotal);
  final dueN = countDue(fd, months, asOf, grace + 1);
  double expected;
  if (months > 0 && dueN >= months) {
    expected = total;
  } else {
    final k = dueN < months ? dueN : months;
    final e = down + cum[k];
    expected = e < total ? e : total;
  }
  final arrears = (r2(expected - paidTotal)) < 0 ? 0.0 : r2(expected - paidTotal);
  var paidCount = months > 0 ? (bisectRight(cum, paidInst + 0.004) - 1) : 0;
  if (paidCount > months) paidCount = months;
  if (paidCount < 0) paidCount = 0;
  var late = 0;
  if (arrears > 0) {
    final a = dueN < 1 ? 1 : dueN;
    final b = (dueN - paidCount) < 1 ? 1 : (dueN - paidCount);
    late = a < b ? a : b;
  }
  final cur = paidCount < months ? sched[paidCount] : (sched.isNotEmpty ? sched.last : monthly);
  monthly = cur;
  var partial = months > 0 ? r2(paidInst - cum[paidCount]) : 0.0;
  if (partial < 0.01 || paidCount >= months || partial >= cur) partial = 0.0;
  final nextDue = (fd != null && remaining > 0 && paidCount < months) ? addMonths(fd, paidCount) : null;
  return CustFin(
    code: c['customer_code'].toString(), name: (c['name'] ?? '').toString(), phone: (c['phone'] ?? '').toString(),
    address: (c['address'] ?? '').toString(), region: (c['region'] ?? '').toString(), rep: (c['rep_name'] ?? '').toString(), collector: (c['collector_name'] ?? '').toString(),
    item: (c['item_desc'] ?? '').toString(), plan: planTxt, total: total, down: down, monthly: monthly,
    paidInst: paidInst, paidTotal: paidTotal, remaining: remaining, expected: r2(expected), arrears: arrears,
    partial: partial, months: months, dueN: dueN, lateMonths: late, paidCount: paidCount, firstDue: fd,
    nextDue: nextDue, start: c['start_date']?.toString(), sched: sched, cum: cum,
    enName: (c['en_name'] ?? '').toString(), enAddress: (c['en_address'] ?? '').toString(), enItem: (c['en_item'] ?? '').toString(),
  );
}
