import 'package:flutter/material.dart';
import '../core/engine.dart';
import '../core/receipt_data.dart';
import '../core/utils.dart';
import '../data/db.dart';
import '../theme.dart';
import 'customers.dart';
import 'receipt_center.dart';
import 'receipt_pdf.dart';
import 'widgets.dart';

class _Due {
  const _Due(this.c, this.r);
  final CustFin c;
  final InstRow r;
  String get key => '${c.code}#${r.no}';
}

/// التحصيل حسب المدة: المحصّل فعلاً + المستحق في الفترة، مع طباعة الإيصالات دفعة واحدة
class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key});
  @override
  State<CollectionScreen> createState() => _S();
}

class _S extends State<CollectionScreen> {
  static const presets = ['النهارده', 'أمس', 'آخر 7 أيام', 'الشهر', 'الشهر اللي فات', 'الشهر الجاي', 'فترة مخصصة'];
  late DateTime from, to;
  String preset = 'الشهر';
  List<Map<String, Object?>> paid = [];
  List<CustFin> fin = [];
  List<_Due> dues = [];
  List<String> regions = [], collectors = [];
  final Set<String> off = {}; // المستبعد من الطباعة (الافتراضي الكل محدد)
  String? coll, region;
  bool withLate = false, loading = true, _busy = false, _again = false;

  @override
  void initState() {
    super.initState();
    _setPreset('الشهر');
    _load();
    dataRev.addListener(_load);
  }

  @override
  void dispose() {
    dataRev.removeListener(_load);
    super.dispose();
  }

  void _setPreset(String p) {
    final t = today();
    switch (p) {
      case 'النهارده':
        from = t;
        to = t;
      case 'أمس':
        from = DateTime(t.year, t.month, t.day - 1);
        to = from;
      case 'آخر 7 أيام':
        from = DateTime(t.year, t.month, t.day - 6);
        to = t;
      case 'الشهر':
        from = DateTime(t.year, t.month, 1);
        to = DateTime(t.year, t.month + 1, 0);
      case 'الشهر اللي فات':
        from = DateTime(t.year, t.month - 1, 1);
        to = DateTime(t.year, t.month, 0);
      case 'الشهر الجاي':
        from = DateTime(t.year, t.month + 1, 1);
        to = DateTime(t.year, t.month + 2, 0);
    }
    preset = p;
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context, firstDate: DateTime(2015), lastDate: DateTime(2045),
      initialDateRange: DateTimeRange(start: from, end: to),
    );
    if (r == null) return;
    setState(() {
      from = DateTime(r.start.year, r.start.month, r.start.day);
      to = DateTime(r.end.year, r.end.month, r.end.day);
      preset = 'فترة مخصصة';
    });
    _rangeChanged();
  }

  void _shift(int dir) {
    final wholeMonth = from.day == 1 && to.day == DateTime(from.year, from.month + 1, 0).day && to.month == from.month && to.year == from.year;
    setState(() {
      if (wholeMonth) {
        from = DateTime(from.year, from.month + dir, 1);
        to = DateTime(from.year, from.month + 1, 0);
      } else {
        final n = to.difference(from).inDays + 1;
        from = DateTime(from.year, from.month, from.day + dir * n);
        to = DateTime(to.year, to.month, to.day + dir * n);
      }
      preset = 'فترة مخصصة';
    });
    _rangeChanged();
  }

  void _rangeChanged() {
    setState(_calcDues);
    _loadPaid();
  }

  Future<void> _loadPaid() async {
    final r = await AppDb.i.db.rawQuery(
      "SELECT p.*, c.region FROM payments p LEFT JOIN customers c ON c.customer_code=p.customer_code "
      "WHERE p.pay_date >= ? AND p.pay_date < ? AND IFNULL(p.due_month,'') != ? ORDER BY p.pay_date DESC, p.id DESC",
      [isoDate(from), isoDate(DateTime(to.year, to.month, to.day + 1)), downLabel],
    );
    if (mounted) setState(() { paid = r; _opts(); });
  }

  Future<void> _load() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        final f = await AppDb.i.financials();
        await _loadPaid();
        if (!mounted) return;
        setState(() {
          fin = f;
          loading = false;
          _calcDues();
          _opts();
        });
      } while (_again);
    } finally {
      _busy = false;
    }
  }

  void _opts() {
    regions = ({for (final c in fin) if (c.region.isNotEmpty) c.region}.toList())..sort();
    collectors = ({
      for (final c in fin) if (c.collector.isNotEmpty) c.collector,
      for (final p in paid) if ((p['collector'] ?? '').toString().isNotEmpty) p['collector'].toString(),
    }.toList())..sort();
    if (region != null && !regions.contains(region)) region = null;
    if (coll != null && !collectors.contains(coll)) coll = null;
  }

  /// الأقساط اللي استحقاقها جوه الفترة (وغير مسددة)، ومعاها المتأخر قبل الفترة لو مطلوب
  void _calcDues() {
    final f = DateTime(from.year, from.month, from.day), t = DateTime(to.year, to.month, to.day);
    final out = <_Due>[];
    for (final c in fin) {
      if (c.settled || c.months <= 0 || c.firstDue == null || c.paidCount >= c.months) continue;
      if (addMonths(c.firstDue!, c.paidCount).isAfter(t)) continue;
      final cum = adjCum(c);
      for (var k = c.paidCount; k < c.months; k++) {
        final d = addMonths(c.firstDue!, k);
        if (d.isAfter(t)) break;
        if (d.isBefore(f) && !withLate) continue;
        final r = instAt(c, cum, k);
        if (!r.paid) out.add(_Due(c, r));
      }
    }
    out.sort((a, b) {
      final x = a.c.region.compareTo(b.c.region);
      if (x != 0) return x;
      final y = a.c.name.compareTo(b.c.name);
      return y != 0 ? y : a.r.no.compareTo(b.r.no);
    });
    dues = out;
  }

  List<Map<String, Object?>> get paidF => [
        for (final p in paid)
          if ((coll == null || (p['collector'] ?? '').toString() == coll) && (region == null || (p['region'] ?? '').toString() == region)) p
      ];

  List<_Due> get duesF => [
        for (final d in dues)
          if ((coll == null || d.c.collector == coll) && (region == null || d.c.region == region)) d
      ];

  String get rangeLabel => from == to ? slashDate(from) : '${slashDate(from)}  ←  ${slashDate(to)}';

  Widget _filters() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        child: Row(children: [
          Expanded(
            child: DropdownButtonFormField<String?>(
              value: region, isExpanded: true,
              decoration: const InputDecoration(labelText: 'المنطقة', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              items: [const DropdownMenuItem<String?>(value: null, child: Text('كل المناطق')), for (final r in regions) DropdownMenuItem<String?>(value: r, child: Text(r))],
              onChanged: (v) => setState(() => region = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String?>(
              value: coll, isExpanded: true,
              decoration: const InputDecoration(labelText: 'المحصّل', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              items: [const DropdownMenuItem<String?>(value: null, child: Text('كل المحصّلين')), for (final r in collectors) DropdownMenuItem<String?>(value: r, child: Text(r))],
              onChanged: (v) => setState(() => coll = v),
            ),
          ),
        ]),
      );

  Widget _paidTab(List<Map<String, Object?>> pf) {
    final by = <String, double>{};
    for (final p in pf) {
      final k = (p['collector'] ?? '').toString().isEmpty ? 'بدون محصّل' : p['collector'].toString();
      by[k] = (by[k] ?? 0) + (p['amount_paid'] as num).toDouble();
    }
    final total = pf.fold<double>(0, (s, p) => s + (p['amount_paid'] as num).toDouble());
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: pf.isEmpty ? null : () => showSlipOutputSheet(context, count: pf.length, name: 'receipts_${isoDate(from)}_${isoDate(to)}', title: 'إيصالات استلام الفترة', build: () => paidSlips(pf)),
              icon: const Icon(Icons.print_rounded), label: Text('إيصالات الاستلام (${pf.length})'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: pf.isEmpty ? null : () => guard(context, () => shareTablePdf('كشف التحصيل $rangeLabel', ['التاريخ', 'العميل', 'المنطقة', 'المحصّل', 'المبلغ'], [
                  for (final p in pf) ['${p['pay_date']}', '${p['customer_name'] ?? ''}', '${p['region'] ?? ''}', '${p['collector'] ?? ''}', fmtMoney(p['amount_paid'] as num)],
                  ['', 'الإجمالي', '', '', fmtMoney(total)],
                ])),
            icon: const Icon(Icons.picture_as_pdf_rounded), label: const Text('كشف'),
          ),
        ]),
      ),
      if (by.length > 1)
        SizedBox(
          height: 38,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
            for (final e in by.entries)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => setState(() => coll = collectors.contains(e.key) ? e.key : null),
                  child: Pill('${e.key}: ${fmtMoney(e.value)}', C.blue),
                ),
              ),
          ]),
        ),
      Expanded(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : pf.isEmpty
                ? const Empty('مفيش تحصيل في الفترة دي')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
                    itemCount: pf.length,
                    itemBuilder: (_, i) {
                      final p = pf[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetail(code: p['customer_code'].toString()))),
                          title: Text(p['customer_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${p['pay_date']} • ${p['collector'] ?? ''} • ${p['region'] ?? ''}'),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(fmtMoney(p['amount_paid'] as num), style: const TextStyle(color: C.green, fontWeight: FontWeight.w800)),
                            IconButton(
                              icon: const Icon(Icons.print_outlined, color: C.purple),
                              onPressed: () => guard(context, () => sharePaymentReceipt(p)),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }

  Widget _duesTab(List<_Due> df) {
    final sel = [for (final d in df) if (!off.contains(d.key)) d];
    return Column(children: [
      SwitchListTile(
        dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 18),
        title: const Text('مع المتأخرات قبل الفترة'),
        value: withLate,
        onChanged: (v) => setState(() { withLate = v; _calcDues(); }),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        child: Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: sel.isEmpty
                  ? null
                  : () => showSlipOutputSheet(context, count: sel.length, name: 'dues_${isoDate(from)}_${isoDate(to)}', title: 'إيصالات الأقساط المستحقة', build: () async {
                        final co = await companyInfo();
                        return [for (final d in sel) slipForRow(d.c, co, d.r)];
                      }),
              icon: const Icon(Icons.print_rounded), label: Text('طباعة المحدد (${sel.length})'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: df.isEmpty ? null : () => setState(() { if (off.isEmpty) { off.addAll(df.map((d) => d.key)); } else { off.clear(); } }),
            child: Text(off.isEmpty ? 'إلغاء الكل' : 'تحديد الكل'),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            tooltip: 'كشف PDF',
            onPressed: df.isEmpty ? null : () => guard(context, () => shareTablePdf('المستحق $rangeLabel', ['القسط', 'الاستحقاق', 'العميل', 'المنطقة', 'المبلغ'], [
                  for (final d in df) ['${d.r.no}/${d.c.months}', d.r.due == null ? '' : slashDate(d.r.due!), d.c.name, d.c.region, fmtMoney(d.r.status == 'partial' ? d.r.toPay : d.r.amount)],
                  ['', '', 'الإجمالي', '', fmtMoney(df.fold<double>(0, (s, d) => s + d.r.toPay))],
                ])),
            icon: const Icon(Icons.picture_as_pdf_rounded),
          ),
        ]),
      ),
      Expanded(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : df.isEmpty
                ? const Empty('مفيش أقساط مستحقة في الفترة دي')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                    itemCount: df.length,
                    itemBuilder: (_, i) {
                      final d = df[i];
                      final late = d.r.due != null && d.r.due!.isBefore(DateTime(from.year, from.month, from.day));
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: CheckboxListTile(
                          value: !off.contains(d.key),
                          onChanged: (v) => setState(() { if (v == true) { off.remove(d.key); } else { off.add(d.key); } }),
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(d.c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('قسط ${d.r.no} من ${d.c.months} • ${d.r.due == null ? '' : slashDate(d.r.due!)} • ${d.c.region}${late ? ' • متأخر' : ''}'),
                          secondary: Text(fmtMoney(d.r.status == 'partial' ? d.r.toPay : d.r.amount), style: TextStyle(color: late ? C.red : C.blue, fontWeight: FontWeight.w800)),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final pf = paidF, df = duesF;
    final total = pf.fold<double>(0, (s, p) => s + (p['amount_paid'] as num).toDouble());
    final dueTotal = df.fold<double>(0, (s, d) => s + d.r.toPay);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('التحصيل والإيصالات'),
          bottom: TabBar(
            labelColor: Colors.white, unselectedLabelColor: Colors.white60, indicatorColor: C.gold,
            tabs: [Tab(text: 'المحصّل (${pf.length})'), Tab(text: 'المستحق (${df.length})')],
          ),
        ),
        body: Column(children: [
          Container(
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 6), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            decoration: BoxDecoration(gradient: C.grad, borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_right, color: Colors.white)),
              Expanded(
                child: InkWell(
                  onTap: _pickRange,
                  child: Column(children: [
                    Text(rangeLabel, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    Text('${fmtMoney(total)} جنيه', style: const TextStyle(color: C.gold, fontSize: 22, fontWeight: FontWeight.w900)),
                    Text('مستحق في الفترة ${fmtMoney(dueTotal)} • اضغط لتغيير الفترة', style: const TextStyle(color: Colors.white60, fontSize: 11)),
                  ]),
                ),
              ),
              IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_left, color: Colors.white)),
            ]),
          ),
          SizedBox(
            height: 42,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
              for (final p in presets)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ChoiceChip(
                    label: Text(p), selected: preset == p,
                    onSelected: (_) {
                      if (p == 'فترة مخصصة') {
                        _pickRange();
                      } else {
                        setState(() => _setPreset(p));
                        _rangeChanged();
                      }
                    },
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 6),
          _filters(),
          Expanded(child: TabBarView(children: [_paidTab(pf), _duesTab(df)])),
        ]),
      ),
    );
  }
}
