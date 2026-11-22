import 'package:flutter/material.dart';
import '../core/engine.dart';
import '../core/utils.dart';
import '../data/db.dart';
import '../data/regions.dart';
import '../theme.dart';
import 'widgets.dart';

const _noRegion = 'بدون منطقة';

class _RegStat {
  _RegStat(this.name);
  final String name;
  int? id;
  String sub = '', collector = '', notes = '';
  final List<CustFin> customers = [];
  double remaining = 0, arrears = 0, monthCollected = 0;
}

/// المناطق: تسجيل المناطق + بيانات كل منطقة لوحدها أو كل المناطق مع بعض + توزيعها على المحصّلين
class RegionsHub extends StatefulWidget {
  const RegionsHub({super.key});
  @override
  State<RegionsHub> createState() => _RegionsHubS();
}

class _RegionsHubS extends State<RegionsHub> {
  List<_RegStat> regs = [];
  List<String> collectors = [];
  bool loading = true, all = true;
  String? selected;

  @override
  void initState() {
    super.initState();
    _load();
    dataRev.addListener(_load);
  }

  @override
  void dispose() {
    dataRev.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final db = AppDb.i;
    final rows = await db.regionRows();
    final fin = await db.financials();
    final ym = isoDate(today()).substring(0, 7);
    final paid = await db.db.rawQuery(
        "SELECT IFNULL(c.region,'') r, IFNULL(SUM(p.amount_paid),0) s FROM payments p LEFT JOIN customers c ON c.customer_code=p.customer_code "
        "WHERE substr(p.pay_date,1,7)=? AND IFNULL(p.due_month,'')!=? GROUP BY r",
        [ym, downLabel]);
    final byName = <String, _RegStat>{};
    for (final r in rows) {
      final n = (r['name'] ?? '').toString().trim();
      if (n.isEmpty) continue;
      final s = byName.putIfAbsent(n, () => _RegStat(n));
      s.id = (r['id'] as num).toInt();
      s.sub = (r['sub_name'] ?? '').toString();
      s.collector = (r['collector'] ?? '').toString();
      s.notes = (r['notes'] ?? '').toString();
    }
    for (final c in fin) {
      final n = c.region.trim().isEmpty ? _noRegion : c.region.trim();
      final s = byName.putIfAbsent(n, () => _RegStat(n));
      s.customers.add(c);
      s.remaining += c.remaining;
      s.arrears += c.arrears;
    }
    for (final p in paid) {
      final n = (p['r'] ?? '').toString().trim().isEmpty ? _noRegion : p['r'].toString().trim();
      byName[n]?.monthCollected += ((p['s'] ?? 0) as num).toDouble();
    }
    final list = byName.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    final cols = await db.collectorNames();
    if (!mounted) return;
    setState(() {
      regs = list;
      collectors = cols;
      loading = false;
      if (selected != null && !list.any((e) => e.name == selected)) selected = null;
      selected ??= list.isEmpty ? null : list.first.name;
    });
  }

  Future<void> _edit([_RegStat? s]) async {
    final name = TextEditingController(text: s?.name == _noRegion ? '' : (s?.name ?? ''));
    final sub = TextEditingController(text: s?.sub ?? '');
    final notes = TextEditingController(text: s?.notes ?? '');
    String col = s?.collector ?? '';
    String? err;
    final ok = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(s?.id == null ? 'منطقة جديدة' : 'تعديل المنطقة', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 12),
              Field('اسم المنطقة', name),
              Field('القرية / المنطقة الفرعية (اختياري)', sub),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DropdownButtonFormField<String>(
                  value: collectors.contains(col) ? col : '',
                  decoration: const InputDecoration(labelText: 'المحصّل المسؤول عن المنطقة'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('— من غير محصّل —')),
                    for (final c in collectors) DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => set(() => col = v ?? ''),
                ),
              ),
              if (collectors.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('مفيش محصّلين متسجّلين. ضيفهم الأول من «مناديب ومحصلين» (الوظيفة: المحصلين).', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ),
              Field('ملاحظات', notes, lines: 2),
              if (err != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(err!, style: const TextStyle(color: C.red, fontWeight: FontWeight.w700))),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    try {
                      await AppDb.i.saveRegion(id: s?.id, name: name.text, sub: sub.text, collector: col, notes: notes.text);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      set(() => err = errText(e));
                    }
                  },
                  child: const Text('حفظ'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    if (ok == true) await _load();
  }

  Future<void> _apply(_RegStat s) async {
    if (s.collector.isEmpty) {
      toast(context, 'اختار محصّل للمنطقة الأول من «تعديل».', err: true);
      return;
    }
    if (!await confirm(context, 'تسجّل المحصّل «${s.collector}» على كل عملاء منطقة «${s.name}» (${s.customers.length} عميل)؟\nمفيش أي مبالغ بتتغيّر.')) return;
    if (!mounted) return;
    await guard(context, () async {
      final n = await AppDb.i.applyRegionCollector(s.name);
      if (mounted) toast(context, 'اتوزّع $n عميل على ${s.collector}');
    });
  }

  Future<void> _applyAll() async {
    final n = regs.where((r) => r.collector.isNotEmpty).length;
    if (n == 0) {
      toast(context, 'مفيش منطقة ليها محصّل. عدّل المناطق الأول.', err: true);
      return;
    }
    if (!await confirm(context, 'توزّع $n منطقة على محصّليها؟ (بيتسجّل المحصّل على عملاء كل منطقة، ومفيش مبالغ بتتغيّر)')) return;
    if (!mounted) return;
    await guard(context, () async {
      final t = await AppDb.i.applyAllRegionCollectors();
      if (mounted) toast(context, 'اتوزّع $t عميل');
    });
  }

  Future<void> _delete(_RegStat s) async {
    if (s.id == null) return;
    if (!await adminGate(context, 'حذف المنطقة «${s.name}»')) return;
    if (!mounted) return;
    if (!await confirm(context, 'تحذف منطقة «${s.name}»؟')) return;
    if (!mounted) return;
    await guard(context, () async {
      await AppDb.i.deleteRegion(s.id!);
      await _load();
    }, ok: 'اتحذفت المنطقة');
  }

  Widget _mini(String label, String v, Color c, {bool light = false}) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(color: c.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: TextStyle(fontWeight: FontWeight.w800, color: c, fontSize: 14))),
            Text(label, style: TextStyle(fontSize: 11, color: light ? Colors.white70 : null)),
          ]),
        ),
      );

  Widget _card(_RegStat s, {bool withCustomers = false}) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.place_rounded, color: C.green),
              const SizedBox(width: 8),
              Expanded(child: Text(s.sub.isEmpty ? s.name : '${s.name} — ${s.sub}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') _edit(s);
                  if (v == 'apply') _apply(s);
                  if (v == 'del') _delete(s);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(s.id == null ? 'تسجيل كمنطقة' : 'تعديل')),
                  if (s.id != null) const PopupMenuItem(value: 'apply', child: Text('توزيع عملائها على المحصّل')),
                  if (s.id != null) const PopupMenuItem(value: 'del', child: Text('حذف')),
                ],
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(bottom: 8, right: 4),
              child: Text(
                s.id == null ? 'منطقة مكتوبة على العملاء ومش متسجّلة (دوس ⋮ وسجّلها)' : (s.collector.isEmpty ? 'المحصّل: لسه ماتوزعتش' : 'المحصّل: ${s.collector}'),
                style: TextStyle(color: s.collector.isEmpty ? Colors.orange.shade800 : Colors.grey.shade700, fontSize: 12),
              ),
            ),
            Row(children: [
              _mini('عملاء', '${s.customers.length}', C.blue),
              _mini('المتبقي', fmtMoney(s.remaining), C.purple),
              _mini('المتأخر', fmtMoney(s.arrears), C.red),
              _mini('محصّل الشهر', fmtMoney(s.monthCollected), C.green),
            ]),
            if (withCustomers) ...[
              const Divider(height: 22),
              if (s.customers.isEmpty) const Text('مفيش عملاء في المنطقة دي.', style: TextStyle(color: Colors.grey)),
              for (final c in s.customers)
                ListTile(
                  dense: true, contentPadding: EdgeInsets.zero,
                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${c.code}  •  ${c.collector.isEmpty ? 'من غير محصّل' : c.collector}'),
                  trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(fmtMoney(c.remaining), style: const TextStyle(fontWeight: FontWeight.w800)),
                    if (c.arrears > 0) Text('متأخر ${fmtMoney(c.arrears)}', style: const TextStyle(color: C.red, fontSize: 11)),
                  ]),
                ),
            ],
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cur = regs.where((e) => e.name == selected).toList();
    final total = _RegStat('الإجمالي')
      ..remaining = regs.fold<double>(0.0, (s, e) => s + e.remaining)
      ..arrears = regs.fold<double>(0.0, (s, e) => s + e.arrears)
      ..monthCollected = regs.fold<double>(0.0, (s, e) => s + e.monthCollected);
    final custTotal = regs.fold<int>(0, (s, e) => s + e.customers.length);
    return Scaffold(
      appBar: AppBar(title: const Text('📍 المناطق'), actions: [
        IconButton(tooltip: 'توزيع كل المناطق على المحصلين', onPressed: _applyAll, icon: const Icon(Icons.share_location_rounded)),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('منطقة جديدة')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 90), children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('كل المناطق مع بعض'), icon: Icon(Icons.layers_rounded)),
                  ButtonSegment(value: false, label: Text('منطقة واحدة'), icon: Icon(Icons.place_outlined)),
                ],
                selected: {all},
                onSelectionChanged: (v) => setState(() => all = v.first),
              ),
              const SizedBox(height: 12),
              if (regs.isEmpty) const Empty('لسه مفيش مناطق. دوس «منطقة جديدة» وسجّل أول منطقة.'),
              if (all && regs.isNotEmpty) ...[
                Card(
                  color: C.navy,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(children: [
                      Text('إجمالي كل المناطق (${regs.length} منطقة • $custTotal عميل)', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Row(children: [
                        _mini('المتبقي', fmtMoney(total.remaining), Colors.white, light: true),
                        _mini('المتأخر', fmtMoney(total.arrears), C.gold, light: true),
                        _mini('محصّل الشهر', fmtMoney(total.monthCollected), Colors.greenAccent, light: true),
                      ]),
                    ]),
                  ),
                ),
                const SizedBox(height: 10),
                for (final s in regs) _card(s),
              ],
              if (!all && regs.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  value: selected,
                  decoration: const InputDecoration(labelText: 'اختار المنطقة'),
                  items: [for (final s in regs) DropdownMenuItem(value: s.name, child: Text(s.name))],
                  onChanged: (v) => setState(() => selected = v),
                ),
                const SizedBox(height: 10),
                for (final s in cur) _card(s, withCustomers: true),
              ],
            ]),
    );
  }
}
