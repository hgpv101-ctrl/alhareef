import 'dart:typed_data';
// بيانات الإيصالات: كلاسات بسيطة (تتبعت بين الـ isolates) + حساب جدول الأقساط لكل عميل.
import 'engine.dart';
import 'utils.dart';

/// بيانات الشركة اللي بتتكتب على الإيصال
class CompanyInfo {
  const CompanyInfo(this.name, this.activity, this.phones, this.footer);
  final String name, activity, phones, footer;
}

/// قسط واحد من جدول العميل
class InstRow {
  const InstRow(this.no, this.due, this.amount, this.after, this.status, this.toPay);
  final int no; // رقم القسط 1..N
  final DateTime? due; // تاريخ الاستحقاق
  final double amount; // قيمة القسط حسب الخطة
  final double after; // الباقي على العميل بعد سداد هذا القسط
  final String status; // paid | partial | due
  final double toPay; // المتبقي من القسط (0 لو مسدد)
  bool get paid => status == 'paid';
}

/// تراكمي الأقساط مع تسوية فرق التقريب في القسط الأخير (العميل مايدفعش أكتر من الإجمالي)
List<double> adjCum(CustFin c) {
  final cum = List<double>.from(c.cum);
  if (c.months > 0 && cum.length > c.months) {
    final tol = (c.months * 0.005) > 0.01 ? c.months * 0.005 : 0.01;
    final target = r2(c.total - c.down);
    if ((target - cum[c.months]).abs() <= tol) cum[c.months] = target;
  }
  return cum;
}

InstRow instAt(CustFin c, List<double> cum, int k) {
  final amt = r2(cum[k + 1] - cum[k]);
  final String st;
  final double rest;
  if (c.paidInst + 0.004 >= cum[k + 1]) {
    st = 'paid';
    rest = 0.0;
  } else if (c.paidInst - cum[k] > 0.004) {
    st = 'partial';
    rest = r2(cum[k + 1] - c.paidInst);
  } else {
    st = 'due';
    rest = amt;
  }
  var after = r2(cum.last - cum[k + 1]);
  if (after < 0.01) after = 0.0;
  final base = c.firstDue;
  return InstRow(k + 1, base == null ? null : addMonths(base, k), amt, after, st, rest);
}

/// كل أقساط العميل (مسددة وغير مسددة)
List<InstRow> installmentRows(CustFin c) {
  if (c.months <= 0) return const [];
  final cum = adjCum(c);
  return [for (var k = 0; k < c.months; k++) instAt(c, cum, k)];
}

/// سطر في جدول أقساط الإيصال الإنجليزي (Contract Credit): التاريخ والقيمة وهل اتسدّد
class SlipRow {
  const SlipRow(this.no, this.date, this.amount, this.status);
  final int no;
  final String date; // 28/12/2026
  final double amount;
  final String status; // paid | partial | due
}

/// بيانات الإيصال الإنجليزي (من الإعدادات) — نصوص بس عشان تتبعت للـ isolate
class EnInfo {
  const EnInfo({
    required this.brand, required this.brandSub, required this.address, required this.accNo, required this.accName,
    required this.bank, required this.whatsapp, required this.manager, this.logo,
  });
  final String brand, brandSub, address, accNo, accName, bank, whatsapp, manager;
  final Uint8List? logo; // لوجو الشركة (اختياري) بدل الاسم المكتوب
}

/// بيانات إيصال واحد — أرقام وكلام بس عشان تتبعت للـ isolate
class SlipData {
  const SlipData({
    required this.kind, required this.code, required this.name, required this.phone, required this.address,
    required this.region, required this.rep, required this.collector, required this.item, required this.company,
    required this.activity, required this.phones, required this.plan, required this.no, required this.months,
    required this.total, required this.down, required this.amount, required this.after, required this.due,
    required this.start, required this.payDate, required this.receiptNo, this.sched = const [],
    this.enName = '', this.enAddress = '', this.enItem = '',
  });
  final String enName, enAddress, enItem; // الإيصال الإنجليزي بياخد دي (ولو فاضية بيرجع للعربي)
  final String kind; // coupon = قسط مطلوب (تعهد بالدفع) | paid = إيصال استلام
  final String code, name, phone, address, region, rep, collector, item, company, activity, phones, plan;
  final String due, start, payDate, receiptNo; // تواريخ بشكل 2026/04/01
  final int no, months;
  final double total, down, amount, after;
  final List<SlipRow> sched; // كل أقساط العميل (للإيصال الإنجليزي)
}

/// نظام القسط: «عدد × قسط» لكل مرحلة (لحد 4 مراحل، والمراحل الفاضية مابتظهرش)
String planString(CustFin c) {
  final tiers = <List<num>>[];
  try {
    tiers.addAll(parsePlan(c.plan));
  } catch (_) {}
  if (tiers.isEmpty && c.months > 0) tiers.add([c.months, c.monthly]);
  String n0(num v) => v == v.truncate() ? '${v.truncate()}' : v.toStringAsFixed(2);
  // بنعرض المراحل الفعلية بس (من غير «٠ × ٠») عشان الخانة تفضل مقروءة
  final shown = tiers.where((t) => t[0] != 0 || t[1] != 0).take(4).toList();
  if (shown.isEmpty) return '';
  return arDigits(shown.map((t) => '${t[0]} × ${n0(t[1])}').join(' + '));
}

SlipData _make(CustFin c, CompanyInfo co,
    {required String kind, required int no, required double amount, required double after, DateTime? due,
    String payDate = '', String receiptNo = '', String collector = ''}) {
  final st = toDate(c.start);
  String dmy(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  final sched = [for (final r in installmentRows(c)) SlipRow(r.no, r.due == null ? '' : dmy(r.due!), r.amount, r.status)];
  return SlipData(
    kind: kind, code: c.code, name: c.name, phone: c.phone, address: c.address, region: c.region, rep: c.rep,
    collector: collector.isNotEmpty ? collector : c.collector, item: c.item, company: co.name, activity: co.activity,
    phones: co.phones, plan: planString(c), no: no, months: c.months, total: c.total, down: c.down, amount: amount,
    after: after, due: due == null ? '' : slashDate(due), start: st == null ? '' : slashDate(st), payDate: payDate,
    receiptNo: receiptNo, sched: sched, enName: c.enName, enAddress: c.enAddress, enItem: c.enItem,
  );
}

/// إيصال قسط مطلوب (للدفتر / التحصيل الميداني)
SlipData slipForRow(CustFin c, CompanyInfo co, InstRow r, {double? amount, double? after}) => _make(
      c, co, kind: 'coupon', no: r.no, amount: amount ?? (r.status == 'partial' ? r.toPay : r.amount),
      after: after ?? r.after, due: r.due,
    );

/// إيصال استلام لدفعة اتسجّلت — الأرقام محسوبة وقت الدفعة نفسها مش حالة العميل النهارده
SlipData slipForPayment(CustFin c, CompanyInfo co,
    {required double paidUpTo, required double amount, required String payDate, required String receiptNo, required String collector}) {
  final cum = adjCum(c);
  var cnt = c.months > 0 ? bisectRight(cum, paidUpTo + 0.004) - 1 : 0;
  if (cnt > c.months) cnt = c.months;
  if (cnt < 0) cnt = 0;
  final partial = c.months > 0 && cnt < c.months && (paidUpTo - cum[cnt]) > 0.004;
  var no = cnt + (partial ? 1 : 0);
  if (c.months > 0 && no > c.months) no = c.months;
  if (no < 1) no = 1;
  var after = r2(cum.last - paidUpTo);
  if (after < 0.01) after = 0.0;
  final due = (c.firstDue != null && c.months > 0) ? addMonths(c.firstDue!, no - 1) : null;
  return _make(c, co, kind: 'paid', no: no, amount: amount, after: after, due: due, payDate: payDate, receiptNo: receiptNo, collector: collector);
}
