import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../core/engine.dart';
import '../core/utils.dart';
import '../data/db.dart';
import '../data/ops.dart';
import '../data/repfile.dart';
import '../theme.dart';
import 'customers.dart';
import 'widgets.dart';

/// متابعة المندوبين والمحصلين (للمالك): استيراد ملفات + اكتشاف أخطاء + أداء + حزم بيانات
class RepFollowScreen extends StatefulWidget {
  const RepFollowScreen({super.key});
  @override
  State<RepFollowScreen> createState() => _S();
}

class _S extends State<RepFollowScreen> with SingleTickerProviderStateMixin {
  late final TabController tc = TabController(length: 4, vsync: this);
  List<Map<String, Object?>> reports = [];
  List<_Perf> reps = [], colls = [];
  List<_Anom> anoms = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = AppDb.i;
    final ym = isoDate(today()).substring(0, 7);
    final fin = await db.financials();
    final pays = await db.db.rawQuery("SELECT * FROM payments WHERE IFNULL(due_month,'')!=?", [downLabel]);
    final rp = await db.db.query('rep_reports', orderBy: 'id DESC');
    final repsL = await db.namesOf('المناديب');
    final collsL = await db.namesOf('المحصلين');
    _Perf perf(String n, bool isRep) {
      final mine = fin.where((c) => isRep ? c.rep == n : c.collector == n).toList();
      final monthPays = pays.where((p) => p['collector'] == n && (p['pay_date'] ?? '').toString().startsWith(ym)).toList();
      final reports = rp.where((r) => r['rep_name'] == n).toList();
      return _Perf(
        name: n, customers: mine.length, late: mine.where((c) => c.late).length, lateAmt: mine.fold<double>(0.0, (s, c) => s + c.arrears),
        monthCollected: monthPays.fold<double>(0.0, (s, p) => s + (p['amount_paid'] as num)), monthCount: monthPays.length,
        monthSales: fin.where((c) => c.rep == n && (c.start ?? '').startsWith(ym)).fold<double>(0.0, (s, c) => s + c.total),
        imports: reports.length, errs: reports.fold<int>(0, (s, r) => s + (r['n_err'] as num).toInt()), total: reports.fold<int>(0, (s, r) => s + (r['n_ok'] as num).toInt() + (r['n_warn'] as num).toInt() + (r['n_err'] as num).toInt()),
      );
    }
    final a = <_Anom>[];
    final byKey = <String, List<Map<String, Object?>>>{};
    for (final p in pays) {
      byKey.putIfAbsent('${p['customer_code']}|${p['amount_paid']}|${p['pay_date']}', () => []).add(p);
    }
    for (final e in byKey.values) {
      if (e.length > 1) a.add(_Anom(e.first['collector']?.toString() ?? '-', 'تكرار محتمل', '${e.first['customer_name']}: ${fmtMoney(e.first['amount_paid'] as num)} مسجّلة ${e.length} مرات بتاريخ ${e.first['pay_date']}'));
    }
    final byCode = {for (final c in fin) c.code: c};
    for (final p in pays) {
      final c = byCode[p['customer_code']];
      if (c == null) continue;
      if (c.monthly > 0 && (p['amount_paid'] as num) > c.monthly * 3) a.add(_Anom(p['collector']?.toString() ?? '-', 'مبلغ كبير', '${c.name}: ${fmtMoney(p['amount_paid'] as num)} (القسط ${fmtMoney(c.monthly)})'));
      final d = toDate(p['pay_date']);
      if (d != null && d.isAfter(today())) a.add(_Anom(p['collector']?.toString() ?? '-', 'تاريخ مستقبلي', '${c.name}: ${p['pay_date']}'));
    }
    // محصّل مسؤول عن عملاء متأخرين ومفيش تحصيل منه من 30 يوم
    for (final n in collsL) {
      final mine = fin.where((c) => c.collector == n && c.late).toList();
      final last = pays.where((p) => p['collector'] == n).map((p) => toDate(p['pay_date'])).whereType<DateTime>().toList()..sort();
      if (mine.isNotEmpty && (last.isEmpty || today().difference(last.last).inDays > 30)) {
        a.add(_Anom(n, 'خمول', '${mine.length} عميل متأخر عليه وآخر تحصيل ${last.isEmpty ? 'مفيش' : isoDate(last.last)}'));
      }
    }
    for (final r in rp) {
      final iss = (jsonDecode((r['issues'] ?? '[]').toString()) as List).cast<Map<String, dynamic>>().where((i) => i['level'] == 'err');
      for (final i in iss) {
        a.add(_Anom(r['rep_name'].toString(), 'خطأ في ملف', '${i['title']}: ${(i['msgs'] as List).join('، ')}'));
      }
    }
    if (!mounted) return;
    setState(() {
      reports = rp;
      reps = [for (final n in repsL) perf(n, true)];
      colls = [for (final n in collsL) perf(n, false)];
      anoms = a;
    });
  }

  Future<void> _import() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json'], allowMultiple: true);
    if (res == null || !mounted) return;
    for (final f in res.files) {
      if (f.path == null || !mounted) continue;
      try {
        final rf = RepFile.parse(await File(f.path!).readAsString(), fileName: f.name);
        final rv = await AppDb.i.reviewRepFile(rf);
        if (!mounted) return;
        await Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewScreen(review: rv)));
      } catch (e) {
        if (mounted) toast(context, '${f.name}: ${errText(e)}', err: true);
      }
    }
    _load();
  }

  /// اختيار مناطق (اختياري): من غير اختيار = كل المناطق
  Future<Set<String>?> _pickRegions() async {
    final all = [for (final r in await AppDb.i.db.query('regions', columns: ['name'], orderBy: 'name')) r['name'].toString()];
    if (all.isEmpty || !mounted) return <String>{};
    final sel = <String>{};
    return showModalBottomSheet<Set<String>>(
      context: context, isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * .7,
            child: Column(children: [
              const Padding(padding: EdgeInsets.all(14), child: Text('توزيع على المناطق (اختياري)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              const Text('اختار منطقة أو أكتر، ولو مخترتش حاجة هيظهر الكل', style: TextStyle(color: Colors.grey, fontSize: 12)),
              Expanded(
                child: ListView(children: [
                  for (final r in all)
                    CheckboxListTile(value: sel.contains(r), title: Text(r), onChanged: (v) => set(() => v == true ? sel.add(r) : sel.remove(r))),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, <String>{}), child: const Text('كل المناطق'))),
                  const SizedBox(width: 10),
                  Expanded(child: FilledButton(onPressed: () => Navigator.pop(ctx, {...sel}), child: Text(sel.isEmpty ? 'تم' : 'تم (${sel.length})'))),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// اختيار عميل معين (بحث بالاسم أو الكود)
  Future<String?> _pickCustomer(String pick) async {
    final fin = (await AppDb.i.financials()).where((c) => pick == '*' || c.rep == pick || c.collector == pick).toList();
    if (!mounted) return null;
    if (fin.isEmpty) {
      toast(context, 'مفيش عملاء للشخص ده.', err: true);
      return null;
    }
    var q = '';
    return showModalBottomSheet<String>(
      context: context, isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final nq = normAr(q).trim();
          final l = fin.where((c) => nq.isEmpty || normAr('${c.name} ${c.code} ${c.phone}').contains(nq)).take(60).toList();
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * .7,
              child: Column(children: [
                Padding(padding: const EdgeInsets.all(12), child: TextField(autofocus: true, onChanged: (v) => set(() => q = v), decoration: const InputDecoration(hintText: 'ابحث باسم العميل أو الكود', prefixIcon: Icon(Icons.search)))),
                Expanded(child: ListView(children: [for (final c in l) ListTile(title: Text(c.name), subtitle: Text('${c.code} • ${c.region}'), trailing: Text(fmtMoney(c.remaining)), onTap: () => Navigator.pop(ctx, c.code))])),
              ]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _package() async {
    final names = [...await AppDb.i.namesOf('المناديب'), ...await AppDb.i.namesOf('المحصلين')];
    if (!mounted) return;
    if (names.isEmpty) {
      toast(context, 'سجّل مندوب أو محصّل الأول.', err: true);
      return;
    }
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => ListView(shrinkWrap: true, children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('ابعت حزمة بيانات لـ...', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        for (final n in names) ListTile(title: Text(n), onTap: () => Navigator.pop(context, n)),
        ListTile(title: const Text('كل العملاء (لأي حد)'), onTap: () => Navigator.pop(context, '*')),
      ]),
    );
    if (pick == null || !mounted) return;
    final t = today();
    final thisM = '${t.year}-${t.month.toString().padLeft(2, '0')}';
    final nx = DateTime(t.year, t.month + 1);
    final nextM = '${nx.year}-${nx.month.toString().padLeft(2, '0')}';
    final scopeSel = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => ListView(shrinkWrap: true, children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('الحزمة تشمل إيه؟', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        ListTile(leading: const Icon(Icons.calendar_month_rounded), title: Text('تحصيل شهر $thisM'), subtitle: const Text('العملاء المطلوب منهم قسط لحد آخر الشهر ده (والمتأخر) ومعاهم المبلغ'), onTap: () => Navigator.pop(context, thisM)),
        ListTile(leading: const Icon(Icons.event_rounded), title: Text('تحصيل شهر $nextM'), subtitle: const Text('الأقساط المستحقة لحد آخر الشهر الجاي'), onTap: () => Navigator.pop(context, nextM)),
        ListTile(leading: const Icon(Icons.date_range_rounded), title: Text('تحصيل السنة كلها (${t.year})'), subtitle: const Text('كل الأقساط المستحقة لحد آخر السنة (والمتأخر) ومعاها المبالغ'), onTap: () => Navigator.pop(context, '${t.year}')),
        ListTile(leading: const Icon(Icons.person_search_rounded), title: const Text('عميل معين'), subtitle: const Text('تختار عميل واحد وتبعت بياناته'), onTap: () => Navigator.pop(context, '#cust')),
        ListTile(leading: const Icon(Icons.groups_rounded), title: const Text('كل العملاء'), subtitle: const Text('من غير فلتر شهر'), onTap: () => Navigator.pop(context, '*')),
      ]),
    );
    if (scopeSel == null || !mounted) return;
    String? custCode;
    if (scopeSel == '#cust') {
      custCode = await _pickCustomer(pick);
      if (custCode == null || !mounted) return;
    }
    // توزيع على المناطق: لو مختارتش منطقة بيظهر الكل
    var regionsSel = <String>{};
    if (custCode == null) {
      final r = await _pickRegions();
      if (r == null || !mounted) return;
      regionsSel = r;
    }
    final String? scope = (scopeSel == '*' || scopeSel == '#cust') ? null : scopeSel;
    await guard(context, () async {
      final p = await AppDb.i.exportRepPackage(pick == '*' ? 'الكل' : pick, allCustomers: pick == '*', ym: scope, regions: regionsSel, customer: custCode);
      await Share.shareXFiles([XFile(p, mimeType: 'application/json')], subject: 'حزمة بيانات ${pick == '*' ? '' : pick}', text: 'افتح الحريف ← شغل المندوب ← استيراد حزمة بيانات');
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('متابعة المناديب والمحصلين'),
          bottom: TabBar(controller: tc, isScrollable: true, labelColor: Colors.white, unselectedLabelColor: Colors.white60, indicatorColor: C.gold, tabs: [
            const Tab(text: 'المناديب'), const Tab(text: 'المحصلين'), Tab(text: 'أخطاء (${anoms.length})'), Tab(text: 'الملفات (${reports.length})'),
          ]),
        ),
        floatingActionButton: FloatingActionButton.extended(onPressed: _import, icon: const Icon(Icons.file_download_rounded), label: const Text('استيراد ملف')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: _package, icon: const Icon(Icons.upload_rounded), label: const Text('حزمة بيانات لمندوب'))),
            ]),
          ),
          Expanded(
            child: TabBarView(controller: tc, children: [
              _perfList(reps, true), _perfList(colls, false), _anomList(), _reportList(),
            ]),
          ),
        ]),
      );

  Widget _perfList(List<_Perf> l, bool isRep) => l.isEmpty
      ? Empty(isRep ? 'مفيش مناديب مسجّلين' : 'مفيش محصلين مسجّلين')
      : ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 90), itemCount: l.length,
          itemBuilder: (_, i) {
            final p = l[i];
            final errRate = p.total == 0 ? 0.0 : p.errs / p.total;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                    if (p.imports > 0) Pill('أخطاء ${(errRate * 100).round()}%', errRate > .15 ? C.red : (errRate > 0 ? C.orange : C.green)),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    Pill('${p.customers} عميل', C.blue),
                    if (p.late > 0) Pill('${p.late} متأخر (${fmtMoney(p.lateAmt)})', C.red),
                    Pill('تحصيل الشهر ${fmtMoney(p.monthCollected)} (${p.monthCount})', C.green),
                    if (isRep) Pill('مبيعات الشهر ${fmtMoney(p.monthSales)}', C.purple),
                    Pill('${p.imports} ملف', C.navy),
                  ]),
                ]),
              ),
            );
          },
        );

  Widget _anomList() => anoms.isEmpty
      ? const Empty('مفيش أخطاء أو شذوذ مكتشف 🎉')
      : ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 90), itemCount: anoms.length,
          itemBuilder: (_, i) {
            final a = anoms[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                leading: const Icon(Icons.warning_amber_rounded, color: C.orange),
                title: Text('${a.who} — ${a.type}', style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(a.text),
              ),
            );
          },
        );

  Widget _reportList() => reports.isEmpty
      ? const Empty('مفيش ملفات متسجّلة. اضغط «استيراد ملف».')
      : ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 90), itemCount: reports.length,
          itemBuilder: (_, i) {
            final r = reports[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _ReportDetail(r: r))),
                title: Text('${r['rep_name']} (${r['role']})', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${r['imported_at']}\nبيع ${fmtMoney(r['total_sales'] as num)} • تحصيل ${fmtMoney(r['total_collect'] as num)}'),
                isThreeLine: true,
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Pill('اتسجّل ${r['n_applied']}', C.green),
                  if ((r['n_err'] as num) > 0) Pill('أخطاء ${r['n_err']}', C.red),
                ]),
              ),
            );
          },
        );
}

class _Perf {
  _Perf({required this.name, required this.customers, required this.late, required this.lateAmt, required this.monthCollected, required this.monthCount,
      required this.monthSales, required this.imports, required this.errs, required this.total});
  final String name;
  final int customers, late, monthCount, imports, errs, total;
  final double lateAmt, monthCollected, monthSales;
}

class _Anom {
  _Anom(this.who, this.type, this.text);
  final String who, type, text;
}

class _ReportDetail extends StatelessWidget {
  const _ReportDetail({required this.r});
  final Map<String, Object?> r;
  @override
  Widget build(BuildContext context) {
    final iss = (jsonDecode((r['issues'] ?? '[]').toString()) as List).cast<Map<String, dynamic>>();
    return Scaffold(
      appBar: AppBar(title: Text('ملف ${r['rep_name']}')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Text('الملف: ${r['file_name']}\nاتستورد: ${r['imported_at']}\nبيع ${r['n_sales']} (${fmtMoney(r['total_sales'] as num)}) • تحصيل ${r['n_collect']} (${fmtMoney(r['total_collect'] as num)})\nسليم ${r['n_ok']} • تنبيه ${r['n_warn']} • خطأ ${r['n_err']} • اتسجّل ${r['n_applied']}'))),
        if (iss.isEmpty) const Empty('مفيش ملاحظات'),
        for (final i in iss)
          Card(
            margin: const EdgeInsets.only(top: 6),
            child: ListTile(
              leading: Icon(i['level'] == 'err' ? Icons.error_rounded : Icons.warning_amber_rounded, color: i['level'] == 'err' ? C.red : C.orange),
              title: Text('${i['title']}'), subtitle: Text((i['msgs'] as List).join('\n')),
            ),
          ),
      ]),
    );
  }
}

/// معاينة الملف قبل التطبيق: كل سجل بحالته (سليم/تنبيه/خطأ) والمالك يقرر
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.review});
  final ReviewResult review;
  @override
  State<ReviewScreen> createState() => _RS();
}

class _RS extends State<ReviewScreen> {
  bool busy = false;
  List<String>? done;

  @override
  Widget build(BuildContext context) {
    final r = widget.review;
    final f = r.file;
    final blocked = r.fileErrors.isNotEmpty;
    final n = r.checks.where((c) => c.apply && c.ok).length;
    return Scaffold(
      appBar: AppBar(title: Text('مراجعة ملف ${f.repName}')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: done != null
              ? FilledButton(onPressed: () => Navigator.pop(context), child: const Text('تمام'))
              : FilledButton.icon(
                  icon: const Icon(Icons.auto_fix_high_rounded),
                  label: Text(busy ? '...' : 'سجّل $n سجل في أماكنهم تلقائي'),
                  onPressed: (blocked || busy || n == 0)
                      ? null
                      : () async {
                          setState(() => busy = true);
                          try {
                            final m = await AppDb.i.applyRepReview(r);
                            if (mounted) setState(() { done = m; busy = false; });
                          } catch (e) {
                            if (mounted) {
                              setState(() => busy = false);
                              toast(context, errText(e), err: true);
                            }
                          }
                        },
                ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${f.repName} (${f.role}) • ${f.createdAt}', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [
                Pill('بيع ${fmtMoney(r.sales)}', C.purple), Pill('تحصيل ${fmtMoney(r.collected)}', C.green),
                Pill('سليم ${r.nOk}', C.green), Pill('تنبيه ${r.nWarn}', C.orange), Pill('خطأ ${r.nErr}', C.red),
              ]),
              for (final e in r.fileErrors) Padding(padding: const EdgeInsets.only(top: 8), child: Text('⛔ $e', style: const TextStyle(color: C.red, fontWeight: FontWeight.w700))),
              for (final e in r.fileWarns) Padding(padding: const EdgeInsets.only(top: 8), child: Text('⚠️ $e', style: const TextStyle(color: C.orange))),
            ]),
          ),
        ),
        if (done != null) ...[
          const Padding(padding: EdgeInsets.fromLTRB(6, 12, 6, 6), child: Text('نتيجة التسجيل', style: TextStyle(fontWeight: FontWeight.w800))),
          for (final m in done!) Padding(padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8), child: Text(m, style: TextStyle(color: m.startsWith('✗') ? C.red : C.green))),
        ] else
          for (final c in r.checks)
            Card(
              margin: const EdgeInsets.only(top: 8),
              color: c.level == 'err' ? C.red.withValues(alpha: .07) : (c.level == 'warn' ? C.orange.withValues(alpha: .07) : null),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(c.level == 'err' ? Icons.error_rounded : (c.level == 'warn' ? Icons.warning_amber_rounded : Icons.check_circle_rounded), color: c.level == 'err' ? C.red : (c.level == 'warn' ? C.orange : C.green)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(c.e.title, style: const TextStyle(fontWeight: FontWeight.w700))),
                    if (c.ok) Switch(value: c.apply, onChanged: blocked ? null : (v) => setState(() => c.apply = v)),
                  ]),
                  Text('${kinds[c.e.kind] ?? c.e.kind} • ${c.e.payDate.isEmpty ? c.e.ts : c.e.payDate}${c.e.kind == 'sale' ? ' • مقدم ${fmtMoney(c.e.down)} • ${c.e.plan.isEmpty ? '${c.e.months} شهر' : c.e.plan}' : ''}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  if (c.e.items.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('🛒 ${c.e.items.map((i) => '${i['qty']}× ${i['name']} (${fmtMoney(i['price'] as num)})').join(' + ')}', style: const TextStyle(fontSize: 12)),
                    ),
                  for (final e in c.errors) Text('⛔ $e', style: const TextStyle(color: C.red, fontSize: 13)),
                  for (final w in c.warns) Text('⚠️ $w', style: const TextStyle(color: C.orange, fontSize: 13)),
                ]),
              ),
            ),
        const SizedBox(height: 80),
      ]),
    );
  }
}

/// المحصلين: أداء + تفاصيل الدفعات + شذوذ
class CollectorsScreen extends StatefulWidget {
  const CollectorsScreen({super.key});
  @override
  State<CollectorsScreen> createState() => _CS();
}

class _CS extends State<CollectorsScreen> {
  List<Map<String, Object?>> rows = [];
  DateTime month = DateTime(today().year, today().month);
  String get ym => '${month.year}-${month.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _l();
  }

  Future<void> _l() async {
    final r = await AppDb.i.db.rawQuery('''
      SELECT IFNULL(NULLIF(collector,''),'—') c, COUNT(*) n, SUM(amount_paid) s, COUNT(DISTINCT customer_code) cu, MAX(pay_date) last
      FROM payments WHERE substr(pay_date,1,7)=? AND IFNULL(due_month,'')!=? GROUP BY c ORDER BY s DESC''', [ym, downLabel]);
    if (mounted) setState(() => rows = r);
  }

  @override
  Widget build(BuildContext context) {
    final total = rows.fold<double>(0.0, (s, r) => s + (r['s'] as num));
    return Scaffold(
      appBar: AppBar(title: const Text('المحصّلين')),
      body: Column(children: [
        Container(
          margin: const EdgeInsets.all(12), padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(gradient: C.grad, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            IconButton(onPressed: () { month = DateTime(month.year, month.month - 1); _l(); }, icon: const Icon(Icons.chevron_right, color: Colors.white)),
            Expanded(child: Column(children: [Text(ym, style: const TextStyle(color: Colors.white70)), Text('${fmtMoney(total)} جنيه', style: const TextStyle(color: C.gold, fontSize: 24, fontWeight: FontWeight.w900))])),
            IconButton(onPressed: () { month = DateTime(month.year, month.month + 1); _l(); }, icon: const Icon(Icons.chevron_left, color: Colors.white)),
          ]),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Empty('مفيش تحصيل في الشهر ده')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 20), itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    final pct = total > 0 ? (r['s'] as num) / total : 0.0;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CollectorDetail(name: r['c'].toString(), ym: ym))),
                        title: Text('${r['c']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${r['n']} دفعة • ${r['cu']} عميل • آخر تحصيل ${r['last']}'),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(value: pct.toDouble(), color: C.green, backgroundColor: C.green.withValues(alpha: .12), minHeight: 6),
                        ]),
                        trailing: Text(fmtMoney(r['s'] as num), style: const TextStyle(color: C.green, fontWeight: FontWeight.w900)),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class CollectorDetail extends StatelessWidget {
  const CollectorDetail({super.key, required this.name, required this.ym});
  final String name, ym;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('تحصيل $name')),
        body: FutureBuilder<List<Map<String, Object?>>>(
          future: AppDb.i.db.rawQuery("SELECT * FROM payments WHERE IFNULL(NULLIF(collector,''),'—')=? AND substr(pay_date,1,7)=? AND IFNULL(due_month,'')!=? ORDER BY pay_date DESC, id DESC", [name, ym, downLabel]),
          builder: (_, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final l = s.data!;
            return ListView.builder(
              padding: const EdgeInsets.all(12), itemCount: l.length,
              itemBuilder: (_, i) => Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetail(code: l[i]['customer_code'].toString()))),
                  title: Text('${l[i]['customer_name']}'), subtitle: Text('${l[i]['pay_date']} • ${l[i]['notes'] ?? ''}'),
                  trailing: Text(fmtMoney(l[i]['amount_paid'] as num), style: const TextStyle(color: C.green, fontWeight: FontWeight.w800)),
                ),
              ),
            );
          },
        ),
      );
}
