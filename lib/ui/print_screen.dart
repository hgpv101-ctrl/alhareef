// قسم الطباعة: إيصالات تحصيل (أو أقساط مستحقة) ليوم / شهر / سنة / فترة، وتختار كام إيصال في الورقة.
// 3 في الورقة = الحجم الكبير الأصلي، 4 وأكتر = بيصغّر الإيصال بالتناسب.
import 'package:flutter/material.dart';
import '../core/engine.dart';
import '../core/receipt_data.dart';
import '../core/utils.dart';
import '../data/db.dart';
import '../theme.dart';
import 'receipt_center.dart';
import 'receipt_pdf.dart';
import 'widgets.dart';

class PrintScreen extends StatefulWidget {
  const PrintScreen({super.key});
  @override
  State<PrintScreen> createState() => _PS();
}

class _PS extends State<PrintScreen> {
  static const periods = ['اليوم', 'الشهر', 'السنة', 'فترة'];
  int period = 1; // 0 يوم | 1 شهر | 2 سنة | 3 فترة
  int kind = 0; // 0 إيصالات تحصيل | 1 أقساط مستحقة
  int perPage = 3;
  bool withLate = false;
  late DateTime from, to, anchor;
  bool loading = true;
  List<Map<String, Object?>> allPaid = [];
  List<Map<String, Object?>> paid = [];
  String? region, coll;
  List<String> regions = [], collectors = [];
  List<CustFin> fin = [];
  List<_Due> dues = [];

  @override
  void initState() {
    super.initState();
    anchor = today();
    _setRange();
    AppDb.i.getSetting('print_per_page').then((v) {
      final n = int.tryParse(v);
      if (mounted && n != null && n >= 2 && n <= 8) setState(() => perPage = n);
    });
    _load();
  }

  void _setRange() {
    final a = anchor;
    switch (period) {
      case 0:
        from = to = DateTime(a.year, a.month, a.day);
      case 1:
        from = DateTime(a.year, a.month, 1);
        to = DateTime(a.year, a.month + 1, 0);
      case 2:
        from = DateTime(a.year, 1, 1);
        to = DateTime(a.year, 12, 31);
      default:
        break; // فترة: from/to بيتحددوا من الاختيار
    }
  }

  void _shift(int dir) {
    if (period == 3) return;
    final a = anchor;
    anchor = switch (period) {
      0 => DateTime(a.year, a.month, a.day + dir),
      1 => DateTime(a.year, a.month + dir, 1),
      _ => DateTime(a.year + dir, 1, 1),
    };
    _setRange();
    _load();
  }

  Future<void> _pick() async {
    if (period == 3) {
      final r = await showDateRangePicker(
        context: context, firstDate: DateTime(2000), lastDate: DateTime(2100),
        initialDateRange: DateTimeRange(start: from, end: to),
      );
      if (r == null) return;
      from = r.start;
      to = r.end;
    } else {
      final d = await showDatePicker(context: context, initialDate: anchor, firstDate: DateTime(2000), lastDate: DateTime(2100));
      if (d == null) return;
      anchor = d;
      _setRange();
    }
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final db = AppDb.i;
      if (kind == 0) {
        final r = await db.db.rawQuery(
          "SELECT p.*, c.region FROM payments p LEFT JOIN customers c ON c.customer_code=p.customer_code WHERE p.pay_date >= ? AND p.pay_date < ? AND IFNULL(p.due_month,'') != ? ORDER BY p.pay_date, p.id",
          [isoDate(from), isoDate(DateTime(to.year, to.month, to.day + 1)), downLabel],
        );
        allPaid = r;
      } else {
        if (fin.isEmpty) fin = await db.financials();
      }
      _applyFilters();
    } catch (e) {
      if (mounted) toast(context, errText(e), err: true);
    }
    if (mounted) setState(() => loading = false);
  }

  /// فلترة بالمنطقة والمحصّل، وتحديث قوايم الاختيار من البيانات المعروضة
  void _applyFilters() {
    if (kind == 0) {
      regions = ({for (final p in allPaid) if ((p['region'] ?? '').toString().isNotEmpty) p['region'].toString()}.toList())..sort();
      collectors = ({for (final p in allPaid) if ((p['collector'] ?? '').toString().isNotEmpty) p['collector'].toString()}.toList())..sort();
    } else {
      _calcDues();
      regions = ({for (final d in dues) if (d.c.region.isNotEmpty) d.c.region}.toList())..sort();
      collectors = ({for (final d in dues) if (d.c.collector.isNotEmpty) d.c.collector}.toList())..sort();
    }
    if (region != null && !regions.contains(region)) region = null;
    if (coll != null && !collectors.contains(coll)) coll = null;
    if (kind == 0) {
      paid = [
        for (final p in allPaid)
          if ((coll == null || (p['collector'] ?? '').toString() == coll) && (region == null || (p['region'] ?? '').toString() == region)) p
      ];
    } else {
      dues = [
        for (final d in dues)
          if ((coll == null || d.c.collector == coll) && (region == null || d.c.region == region)) d
      ];
    }
  }

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

  String get label {
    switch (period) {
      case 0:
        return arDigits(slashDate(from));
      case 1:
        return arDigits('${from.year}/${from.month.toString().padLeft(2, '0')}');
      case 2:
        return arDigits('${from.year}');
      default:
        return arDigits('${slashDate(from)}  ←  ${slashDate(to)}');
    }
  }

  int get count => kind == 0 ? paid.length : dues.length;

  Future<List<SlipData>> _build() async {
    if (kind == 0) return paidSlips(paid);
    final co = await companyInfo();
    return [for (final d in dues) slipForRow(d.c, co, d.r)];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الطباعة')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const SlipLangPicker(),
        const SizedBox(height: 14),
        const Text('إيه اللي يتطبع؟', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 0, label: Text('إيصالات التحصيل')),
            ButtonSegment(value: 1, label: Text('أقساط مستحقة')),
          ],
          selected: {kind},
          onSelectionChanged: (s) {
            kind = s.first;
            _load();
          },
        ),
        const SizedBox(height: 14),
        const Text('الفترة', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (var i = 0; i < periods.length; i++)
            ChoiceChip(
              label: Text(periods[i]), selected: period == i,
              onSelected: (_) {
                period = i;
                _setRange();
                _load();
              },
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          IconButton.outlined(onPressed: period == 3 ? null : () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pick, icon: const Icon(Icons.calendar_month_rounded),
              label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          IconButton.outlined(onPressed: period == 3 ? null : () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
        ]),
        if (kind == 1)
          SwitchListTile(
            dense: true, contentPadding: EdgeInsets.zero,
            title: const Text('مع المتأخرات قبل الفترة'),
            value: withLate,
            onChanged: (v) {
              withLate = v;
              _load();
            },
          ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String?>(
              value: region, isExpanded: true,
              decoration: const InputDecoration(labelText: 'المنطقة', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              items: [const DropdownMenuItem<String?>(value: null, child: Text('كل المناطق')), for (final r in regions) DropdownMenuItem<String?>(value: r, child: Text(r))],
              onChanged: (v) => setState(() { region = v; _applyFilters(); }),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String?>(
              value: coll, isExpanded: true,
              decoration: const InputDecoration(labelText: 'المحصّل', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              items: [const DropdownMenuItem<String?>(value: null, child: Text('كل المحصّلين')), for (final r in collectors) DropdownMenuItem<String?>(value: r, child: Text(r))],
              onChanged: (v) => setState(() { coll = v; _applyFilters(); }),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        const Text('كام إيصال في الورقة؟', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (final n in [2, 3, 4, 5, 6, 8])
            ChoiceChip(
              label: Text(arDigits(n)), selected: perPage == n,
              onSelected: (_) {
                setState(() => perPage = n);
                AppDb.i.setSetting('print_per_page', '$n');
              },
            ),
        ]),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('٣ = الحجم الكبير الأصلي • ٤ وأكتر = الإيصال بيصغّر', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ),
        const SizedBox(height: 16),
        if (loading)
          const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator())
        else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.purple.withValues(alpha: .08), borderRadius: BorderRadius.circular(14)),
            child: Text(
              kind == 0
                  ? '${arDigits(paid.length)} إيصال تحصيل • ${arDigits(fmtMoney(paid.fold<double>(0, (t, p) => t + (p['amount_paid'] as num).toDouble())))} جنيه'
                  : '${arDigits(dues.length)} قسط مستحق • ${arDigits(fmtMoney(dues.fold<double>(0, (t, d) => t + d.r.toPay)))} جنيه',
              textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 10),
          OutputBar(key: ValueKey('$kind-$period-$perPage-$count-$region-$coll-${isoDate(from)}-${isoDate(to)}'), count: count, perPage: perPage, build: _build, name: kind == 0 ? 'receipts_${isoDate(from)}_${isoDate(to)}' : 'dues_${isoDate(from)}_${isoDate(to)}'),
        ],
      ]),
    );
  }
}

class _Due {
  const _Due(this.c, this.r);
  final CustFin c;
  final InstRow r;
}
