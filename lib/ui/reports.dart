import 'package:flutter/material.dart';
import '../core/engine.dart';
import '../core/utils.dart';
import '../data/db.dart';
import '../data/stock.dart';
import '../theme.dart';
import 'collection.dart';
import 'customers.dart';
import 'receipt_pdf.dart';
import 'widgets.dart';

Future<List<CustFin>> _fin() => AppDb.i.financials();

Widget _kv(String a, String b, {Color? c}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(a), Text(b, style: TextStyle(fontWeight: FontWeight.w800, color: c))]),
    );

/// بيشغّل الاستعلام مرة واحدة بس (كان بيتكرر مع كل إعادة بناء للشاشة)
class _Async<T> extends StatefulWidget {
  const _Async(this.f, this.b);
  final Future<T> Function() f;
  final Widget Function(BuildContext, T) b;
  @override
  State<_Async<T>> createState() => _AsyncS<T>();
}

class _AsyncS<T> extends State<_Async<T>> {
  late final Future<T> fut = widget.f();
  @override
  Widget build(BuildContext c) => FutureBuilder<T>(
      future: fut,
      builder: (ctx, s) => s.hasData ? widget.b(ctx, s.data as T) : (s.hasError ? Empty('${s.error}') : const Center(child: CircularProgressIndicator())));
}

class GeneralReport extends StatelessWidget {
  const GeneralReport({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('📈 التقارير الشاملة')),
        body: _Async<Map<String, double>>(() async {
          final d = AppDb.i.db;
          final f = await _fin();
          double one(List<Map<String, Object?>> r) => ((r.first.values.first ?? 0) as num).toDouble();
          return {
            'sales': f.fold<double>(0.0, (s, e) => s + e.total),
            'paid': f.fold<double>(0.0, (s, e) => s + e.paidTotal),
            'remain': f.fold<double>(0.0, (s, e) => s + e.remaining),
            'arrears': f.fold<double>(0.0, (s, e) => s + e.arrears),
            'customers': f.length.toDouble(),
            'late': f.where((e) => e.late).length.toDouble(),
            'settled': f.where((e) => e.settled).length.toDouble(),
            'exp': one(await d.rawQuery('SELECT IFNULL(SUM(amount),0) FROM expenses')),
            'stock': one(await d.rawQuery('SELECT IFNULL(SUM(qty*buy_price),0) FROM products WHERE qty>0')),
            'supp': one(await d.rawQuery('SELECT IFNULL(SUM(total-paid),0) FROM suppliers_invoices')),
            'cap': one(await d.rawQuery('SELECT IFNULL(SUM(capital),0) FROM partners')),
          };
        }, (ctx, m) => ListView(padding: const EdgeInsets.all(14), children: [
              Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
                _kv('عدد العملاء', '${m['customers']!.toInt()}'),
                _kv('متأخرين', '${m['late']!.toInt()}', c: C.red),
                _kv('مسددين', '${m['settled']!.toInt()}', c: C.green),
                const Divider(),
                _kv('إجمالي المبيعات', fmtMoney(m['sales'])),
                _kv('إجمالي المحصّل (بالمقدم)', fmtMoney(m['paid']), c: C.green),
                _kv('المتبقي عند العملاء', fmtMoney(m['remain']), c: C.purple),
                _kv('المتأخرات الحالية', fmtMoney(m['arrears']), c: C.red),
                const Divider(),
                _kv('المصروفات', fmtMoney(m['exp'])),
                _kv('قيمة المخزن (شراء)', fmtMoney(m['stock'])),
                _kv('مستحق للموردين', fmtMoney(m['supp'])),
                _kv('رأس مال المساهمين', fmtMoney(m['cap'])),
              ]))),
            ])),
      );
}

class LateReport extends StatelessWidget {
  const LateReport({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('⏰ متأخرات التقسيط')),
        body: _Async<List<CustFin>>(() async => (await _fin()).where((e) => e.late).toList()..sort((a, b) => b.arrears.compareTo(a.arrears)), (ctx, l) => Column(children: [
              Expanded(
                child: l.isEmpty
                    ? const Empty('مفيش متأخرين 🎉')
                    : ListView(padding: const EdgeInsets.all(12), children: [
                        for (final c in l)
                          Card(
                            child: ListTile(
                              onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => CustomerDetail(code: c.code))),
                              title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text('${c.region} • متأخر ${c.lateMonths} شهر • ${c.phone}'),
                              trailing: Text(fmtMoney(c.arrears), style: const TextStyle(color: C.red, fontWeight: FontWeight.w800)),
                            ),
                          ),
                      ]),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: () => shareTablePdf('متأخرات التقسيط', ['المتأخر', 'شهور', 'الموبايل', 'المنطقة', 'العميل'],
                      [for (final c in l) [fmtMoney(c.arrears), '${c.lateMonths}', c.phone, c.region, c.name]]),
                  icon: const Icon(Icons.picture_as_pdf), label: const Text('تصدير PDF'),
                ),
              ),
            ])),
      );
}

class WhatsappReminders extends StatelessWidget {
  const WhatsappReminders({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('💬 تذكير المتأخرين')),
        body: _Async<List<CustFin>>(() async => (await _fin()).where((e) => e.late && e.phone.isNotEmpty).toList(), (ctx, l) => l.isEmpty
            ? const Empty('مفيش متأخرين عندهم رقم موبايل')
            : ListView(padding: const EdgeInsets.all(12), children: [
                for (final c in l)
                  Card(
                    child: ListTile(
                      title: Text(c.name),
                      subtitle: Text('${fmtMoney(c.arrears)} جنيه • ${c.phone}'),
                      trailing: IconButton(icon: const Icon(Icons.chat, color: C.green), onPressed: () => openWhatsapp(c.phone, reminderText(c))),
                    ),
                  ),
              ])),
      );
}

class RepsReport extends StatelessWidget {
  const RepsReport({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('🏃 تقرير المندوبين')),
        body: _Async<Map<String, List<CustFin>>>(() async {
          final m = <String, List<CustFin>>{};
          for (final c in await _fin()) {
            m.putIfAbsent(c.rep.isEmpty ? 'بدون مندوب' : c.rep, () => []).add(c);
          }
          return m;
        }, (ctx, m) => ListView(padding: const EdgeInsets.all(12), children: [
              for (final e in m.entries)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.key, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      _kv('عدد العملاء', '${e.value.length}'),
                      _kv('إجمالي المبيعات', fmtMoney(e.value.fold<double>(0.0, (s, c) => s + c.total))),
                      _kv('المحصّل', fmtMoney(e.value.fold<double>(0.0, (s, c) => s + c.paidTotal)), c: C.green),
                      _kv('المتبقي', fmtMoney(e.value.fold<double>(0.0, (s, c) => s + c.remaining)), c: C.purple),
                      _kv('متأخر', fmtMoney(e.value.fold<double>(0.0, (s, c) => s + c.arrears)), c: C.red),
                    ]),
                  ),
                ),
            ])),
      );
}

class MonthlyReport extends StatelessWidget {
  const MonthlyReport({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('📅 التجميعات الشهرية')),
        body: _Async<List<Map<String, Object?>>>(() => AppDb.i.db.rawQuery(
            "SELECT substr(pay_date,1,7) ym, SUM(amount_paid) s, COUNT(*) n FROM payments WHERE IFNULL(due_month,'')!=? GROUP BY ym ORDER BY ym DESC", [downLabel]),
            (ctx, r) => r.isEmpty
                ? const Empty('مفيش دفعات')
                : ListView(padding: const EdgeInsets.all(12), children: [
                    for (final x in r) Card(child: ListTile(title: Text('${x['ym']}'), subtitle: Text('${x['n']} دفعة'), trailing: Text(fmtMoney(x['s'] as num), style: const TextStyle(color: C.green, fontWeight: FontWeight.w800)))),
                  ])),
      );
}

class InOutReport extends StatelessWidget {
  const InOutReport({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('🔄 الداخل والخارج')),
        body: _Async<List<Map<String, Object?>>>(() => AppDb.i.db.query('stock_moves', orderBy: 'id DESC', limit: 300), (ctx, r) => r.isEmpty
            ? const Empty('مفيش حركات')
            : ListView(padding: const EdgeInsets.all(12), children: [
                for (final m in r)
                  Card(
                    child: ListTile(
                      title: Text('${m['product_name']}'),
                      subtitle: Text('${m['move_date']} • ${m['kind']} • ${m['ref'] ?? ''}'),
                      trailing: Text('${(m['qty'] as num) > 0 ? '+' : ''}${m['qty']}  (رصيد ${m['balance_after']})', style: TextStyle(color: (m['qty'] as num) >= 0 ? C.green : C.red, fontWeight: FontWeight.w800)),
                    ),
                  ),
              ])),
      );
}

/// دفتر الإيصالات = التحصيل حسب المدة (المحصّل + المستحق + الطباعة الجماعية)
class ReceiptsBook extends StatelessWidget {
  const ReceiptsBook({super.key});
  @override
  Widget build(BuildContext context) => const CollectionScreen();
}

class WarehouseScreen extends StatefulWidget {
  const WarehouseScreen({super.key});
  @override
  State<WarehouseScreen> createState() => _W();
}

class _W extends State<WarehouseScreen> {
  List<Map<String, Object?>> rows = [];
  bool lowOnly = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await AppDb.i.db.query('products', orderBy: 'name');
    if (mounted) setState(() => rows = r);
  }

  Future<void> _move(Map<String, Object?> p) async {
    final q = TextEditingController();
    String kind = 'وارد';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('${p['name']} (رصيد ${p['qty']})'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<String>(segments: const [ButtonSegment(value: 'وارد', label: Text('وارد')), ButtonSegment(value: 'صادر', label: Text('صادر')), ButtonSegment(value: 'جرد', label: Text('جرد'))], selected: {kind}, onSelectionChanged: (s) => set(() => kind = s.first)),
            const SizedBox(height: 10),
            TextField(controller: q, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: kind == 'جرد' ? 'الرصيد الفعلي' : 'الكمية')),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تنفيذ'))],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await guard(context, () async {
      final n = parseNum(q.text).toInt();
      // الحركة والسجل في عملية واحدة، والفرق بيتحسب من الرصيد الحالي في القاعدة مش من الرقم اللي كان ظاهر على الشاشة
      await AppDb.i.adjustStock((p['id'] as num).toInt(), kind, n, notes: '${p['name']}');
      await _load();
    }, ok: 'اتسجلت الحركة');
  }

  @override
  Widget build(BuildContext context) {
    final l = rows.where((p) => !lowOnly || ((p['qty'] ?? 0) as num) <= ((p['min_qty'] ?? 3) as num)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('🏬 المخزن'), actions: [IconButton(icon: Icon(lowOnly ? Icons.warning_amber : Icons.warning_amber_outlined), onPressed: () => setState(() => lowOnly = !lowOnly))]),
      body: l.isEmpty
          ? const Empty('مفيش أصناف')
          : ListView(padding: const EdgeInsets.all(12), children: [
              for (final p in l)
                Card(
                  child: ListTile(
                    onTap: () => _move(p),
                    title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${p['code'] ?? ''} • بيع ${fmtMoney((p['sell_price'] ?? 0) as num)}'),
                    trailing: Pill('${p['qty'] ?? 0}', ((p['qty'] ?? 0) as num) <= ((p['min_qty'] ?? 3) as num) ? C.red : C.green),
                  ),
                ),
            ]),
    );
  }
}

/// تصفية المناديب — عمولة التحصيل (مبلغ لكل 1000) + عمولة البيع (مبلغ لكل قطعة حسب الصنف)
class SettlementScreen extends StatefulWidget {
  const SettlementScreen({super.key});
  @override
  State<SettlementScreen> createState() => _ST();
}

class _ST extends State<SettlementScreen> {
  List<Map<String, Object?>> reps = [];
  String? rep;
  DateTime month = DateTime(today().year, today().month);
  Map<String, Object?>? res;

  @override
  void initState() {
    super.initState();
    AppDb.i.db.rawQuery("SELECT DISTINCT name FROM representatives WHERE type IN ('المناديب','المحصلين') ORDER BY name").then((v) => mounted ? setState(() => reps = v) : null);
  }

  String get ym => '${month.year}-${month.month.toString().padLeft(2, '0')}';

  Future<void> _calc() async {
    if (rep == null) return;
    final d = AppDb.i.db;
    final info = await d.rawQuery('SELECT IFNULL(coll_comm,0) r FROM representatives WHERE name=? ORDER BY id LIMIT 1', [rep]);
    final per1000 = info.isEmpty ? 0.0 : ((info.first['r'] ?? 0) as num).toDouble();
    final collectors = {for (final r in await d.query('representatives', where: "type='المحصلين'")) r['name']};
    var collected = 0.0, n = 0;
    for (final p in await d.rawQuery(
        "SELECT p.amount_paid a, p.collector col, c.rep_name crep FROM payments p LEFT JOIN customers c ON c.customer_code=p.customer_code WHERE substr(p.pay_date,1,7)=? AND IFNULL(p.due_month,'')!=?", [ym, downLabel])) {
      final owner = collectors.contains(p['col']) ? p['col'] : p['crep'];
      if (owner == rep) {
        n++;
        collected += ((p['a'] ?? 0) as num).toDouble();
      }
    }
    // عمولة التحصيل = (المحصّل ÷ 1000) × المبلغ اللي حدده المالك لكل 1000 جنيه
    final collComm = r2(collected / 1000 * per1000);
    // عمولة البيع = كمية كل صنف (بعد خصم المرتجع) × عمولة القطعة المحددة في بيانات الصنف
    final prods = await d.rawQuery("SELECT id, name, IFNULL(rep_comm,0) rc FROM products WHERE IFNULL(name,'')!=''");
    final commById = {for (final p in prods) (p['id'] as num).toInt(): ((p['rc'] ?? 0) as num).toDouble()};
    prods.sort((a, b) => b['name'].toString().length.compareTo(a['name'].toString().length));
    var salesComm = 0.0, salesBase = 0.0, pieces = 0;
    final extras = await d.query('commission_lines', where: 'rep_name=? AND ym=?', whereArgs: [rep, ym]);
    final extraCodes = {for (final e in extras) e['customer_code']};
    double commByName(String itemText) {
      final item = normAr(itemText);
      for (final p in prods) {
        final nm = normAr(p['name'].toString());
        if (nm.isNotEmpty && item.contains(nm)) return ((p['rc'] ?? 0) as num).toDouble();
      }
      return 0.0;
    }
    for (final c in await d.rawQuery("SELECT customer_code, total_amount, item_desc FROM customers WHERE rep_name=? AND substr(start_date,1,7)=?", [rep, ym])) {
      if (extraCodes.contains(c['customer_code'])) continue;
      salesBase += ((c['total_amount'] ?? 0) as num).toDouble();
      final lines = await d.query('customer_items', where: 'customer_code=?', whereArgs: [c['customer_code']]);
      if (lines.isEmpty) {
        // عميل قديم من غير بنود: بنحسبه قطعة واحدة بالاسم
        pieces += 1;
        salesComm += commByName(c['item_desc']?.toString() ?? '');
        continue;
      }
      for (final l in lines) {
        final q = (((l['qty'] ?? 0) as num).toInt() - ((l['returned_qty'] ?? 0) as num).toInt());
        if (q <= 0) continue;
        final pid = l['product_id'] == null ? null : (l['product_id'] as num).toInt();
        final rc = pid != null && commById.containsKey(pid) ? commById[pid]! : commByName(l['product_name']?.toString() ?? '');
        pieces += q;
        salesComm += q * rc;
      }
    }
    salesComm = r2(salesComm);
    final extra = r2(extras.fold<double>(0.0, (s, e) => s + ((e['amount'] ?? 0) as num)));
    setState(() => res = {'n': n, 'collected': r2(collected), 'per1000': per1000, 'collComm': collComm, 'salesBase': r2(salesBase), 'pieces': pieces, 'salesComm': salesComm, 'extra': extra, 'total': r2(collComm + salesComm + extra)});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('🧮 تصفية المناديب')),
        body: ListView(padding: const EdgeInsets.all(14), children: [
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'المندوب / المحصّل'),
            items: [for (final r in reps) DropdownMenuItem(value: r['name'].toString(), child: Text(r['name'].toString()))],
            onChanged: (v) { rep = v; _calc(); },
          ),
          const SizedBox(height: 10),
          Row(children: [
            IconButton(onPressed: () { setState(() => month = DateTime(month.year, month.month - 1)); _calc(); }, icon: const Icon(Icons.chevron_right)),
            Expanded(child: Center(child: Text(ym, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)))),
            IconButton(onPressed: () { setState(() => month = DateTime(month.year, month.month + 1)); _calc(); }, icon: const Icon(Icons.chevron_left)),
          ]),
          if (res != null)
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              _kv('عدد الدفعات', '${res!['n']}'),
              _kv('إجمالي المحصّل', fmtMoney(res!['collected'] as num)),
              _kv('عمولة التحصيل (${fmtMoney(res!['per1000'] as num)} لكل 1000)', fmtMoney(res!['collComm'] as num)),
              _kv('مبيعات الشهر', fmtMoney(res!['salesBase'] as num)),
              _kv('عدد القطع المباعة', '${res!['pieces']}'),
              _kv('عمولة المبيعات', fmtMoney(res!['salesComm'] as num)),
              _kv('عمولات إضافية', fmtMoney(res!['extra'] as num)),
              const Divider(),
              _kv('✅ إجمالي المستحق', fmtMoney(res!['total'] as num), c: C.green),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => guard(context, () async {
                  final r = res!;
                  // حذف التصفية القديمة وإدخال الجديدة والسجل: عملية واحدة (لو فشلت التصفية القديمة ترجع زي ما هي)
                  await AppDb.i.db.transaction((tx) async {
                    await tx.delete('settlements', where: 'rep_name=? AND ym=?', whereArgs: [rep, ym]);
                    await tx.insert('settlements', {
                      'rep_name': rep, 'ym': ym, 'collected': r['collected'], 'coll_comm': r['collComm'], 'sales_total': r['salesBase'],
                      'sales_comm': r['salesComm'], 'extra_comm': r['extra'], 'total': r['total'], 'closed_at': DateTime.now().toIso8601String().substring(0, 16).replaceFirst('T', ' '),
                    });
                    await AppDb.i.logIn(tx, 'اعتماد تصفية', '$rep - $ym - ${fmtMoney(r['total'] as num)}');
                  });
                }, ok: 'اتعتمدت التصفية'),
                child: const Text('اعتماد التصفية'),
              ),
            ]))),
        ]),
      );
}
