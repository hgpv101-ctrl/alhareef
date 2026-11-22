// مركز الإيصالات: طباعة دفتر أقساط عميل (قسط/شهر/كل الأقساط/مدى) + إيصالات الاستلام + شريط الإخراج
import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../core/engine.dart';
import '../core/receipt_data.dart';
import '../core/utils.dart';
import '../data/db.dart';
import '../theme.dart';
import 'receipt_pdf.dart';
import 'widgets.dart';

/// إيصالات استلام لدفعات اتسجّلت. الأرقام (رقم القسط، الباقي) محسوبة وقت كل دفعة.
Future<List<SlipData>> paidSlips(List<Map<String, Object?>> pays) async {
  final db = AppDb.i;
  final list = [for (final p in pays) if ((p['due_month'] ?? '').toString() != downLabel) p];
  if (list.isEmpty) return [];
  final co = await companyInfo();
  final codes = {for (final p in list) p['customer_code'].toString()};
  final fin = <String, CustFin>{};
  if (codes.length > 25) {
    for (final f in await db.financials()) {
      if (codes.contains(f.code)) fin[f.code] = f;
    }
  } else {
    for (final code in codes) {
      final r = await db.financials(code: code);
      if (r.isNotEmpty) fin[code] = r.first;
    }
  }
  // المسدد التراكمي عند كل دفعة (بترتيب التاريخ ثم الرقم)
  final cumById = <int, double>{};
  final codeList = codes.toList();
  for (var i = 0; i < codeList.length; i += 400) {
    final part = codeList.sublist(i, min(i + 400, codeList.length));
    final rows = await db.db.rawQuery(
      "SELECT id, customer_code, amount_paid FROM payments WHERE customer_code IN (${List.filled(part.length, '?').join(',')}) AND IFNULL(due_month,'') != ? ORDER BY customer_code, pay_date, id",
      [...part, downLabel],
    );
    var cur = '';
    var run = 0.0;
    for (final r in rows) {
      final c = r['customer_code'].toString();
      if (c != cur) {
        cur = c;
        run = 0.0;
      }
      run += (r['amount_paid'] as num).toDouble();
      cumById[(r['id'] as num).toInt()] = r2(run);
    }
  }
  final out = <SlipData>[];
  for (final p in list) {
    final c = fin[p['customer_code'].toString()];
    if (c == null) continue;
    final id = (p['id'] as num).toInt();
    out.add(slipForPayment(
      c, co,
      paidUpTo: cumById[id] ?? c.paidInst,
      amount: (p['amount_paid'] as num).toDouble(),
      payDate: slashDate(toDate(p['pay_date']) ?? today()),
      receiptNo: '$id',
      collector: (p['collector'] ?? '').toString(),
    ));
  }
  return out;
}

/// إيصال استلام لدفعة واحدة (مشاركة PDF)
Future<void> sharePaymentReceipt(Map<String, Object?> pay) async {
  final slips = await paidSlips([pay]);
  if (slips.isEmpty) throw const FormatException('دفعة المقدم ملهاش إيصال استلام منفصل.');
  final bytes = await buildSlipsPdf(slips, SlipLayout.single);
  await Printing.sharePdf(bytes: bytes, filename: 'receipt_${pay['customer_code']}_${pay['id']}.pdf');
}

/// شريط الإخراج: اختيار الشكل (3 في A4 / إيصال في الصفحة) + مشاركة PDF أو طباعة مباشرة
class OutputBar extends StatefulWidget {
  const OutputBar({super.key, required this.count, required this.build, this.name = 'receipts', this.perPage = 3});
  final int count;
  final Future<List<SlipData>> Function() build;
  final String name;
  final int perPage; // عدد الإيصالات في ورقة A4
  @override
  State<OutputBar> createState() => _OB();
}

/// اللغة المختارة للإيصال (عربي / إنجليزي) — مشتركة بين كل شاشات الطباعة، ومتحفوظة
final ValueNotifier<SlipLang> slipLangN = ValueNotifier<SlipLang>(SlipLang.ar);
bool _slipLangLoaded = false;
Future<void> loadSlipLang() async {
  if (_slipLangLoaded) return;
  _slipLangLoaded = true;
  final v = await AppDb.i.getSetting('receipt_lang');
  slipLangN.value = v == 'en' ? SlipLang.en : SlipLang.ar;
}

/// اختيار لغة الإيصال — بيتحط في أول شاشة الطباعة (عربي أو إنجليزي)
class SlipLangPicker extends StatefulWidget {
  const SlipLangPicker({super.key});
  @override
  State<SlipLangPicker> createState() => _SLP();
}

class _SLP extends State<SlipLangPicker> {
  @override
  void initState() {
    super.initState();
    loadSlipLang();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SlipLang>(
        valueListenable: slipLangN,
        builder: (_, lang, __) => SizedBox(
          width: double.infinity,
          child: SegmentedButton<SlipLang>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: SlipLang.ar, label: Text('إيصال عربي')),
              ButtonSegment(value: SlipLang.en, label: Text('English Contract')),
            ],
            selected: {lang},
            onSelectionChanged: (s) {
              slipLangN.value = s.first;
              AppDb.i.setSetting('receipt_lang', s.first == SlipLang.en ? 'en' : 'ar');
            },
          ),
        ),
      );
}

class _OB extends State<OutputBar> {
  SlipLayout layout = SlipLayout.a4x3;
  SlipLang get lang => slipLangN.value;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    AppDb.i.getSetting('receipt_layout').then((v) {
      if (mounted && v == 'single') setState(() => layout = SlipLayout.single);
    });
    loadSlipLang();
    slipLangN.addListener(_onLang);
  }

  void _onLang() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    slipLangN.removeListener(_onLang);
    super.dispose();
  }

  Future<void> _go(bool print) async {
    setState(() => busy = true);
    try {
      final slips = await widget.build();
      if (slips.isEmpty) throw const FormatException('مفيش إيصالات تتطبع.');
      final bytes = await buildSlipsPdf(slips, layout, perPage: widget.perPage, lang: lang);
      if (print) {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: widget.name);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: '${widget.name}.pdf');
      }
    } catch (e) {
      if (mounted) toast(context, errText(e), err: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.count;
    final en = lang == SlipLang.en;
    final pages = layout == SlipLayout.a4x3 ? (n / widget.perPage).ceil() : n;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<SlipLayout>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: SlipLayout.a4x3, label: Text(en ? '2 per A4 (landscape)' : '${arDigits(widget.perPage)} إيصالات في A4')),
          ButtonSegment(value: SlipLayout.single, label: Text(en ? 'One per page (A5)' : 'إيصال في الصفحة')),
        ],
        selected: {layout},
        onSelectionChanged: (s) {
          setState(() => layout = s.first);
          AppDb.i.setSetting('receipt_layout', s.first == SlipLayout.single ? 'single' : 'a4x3');
        },
      ),
      const SizedBox(height: 8),
      Text(n == 0 ? 'مفيش إيصالات للطباعة' : (en ? 'الإيصال الإنجليزي: عقد (Contract Credit) لكل عميل بجدول أقساطه' : '$n إيصال ← $pages صفحة'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      if (busy) const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: LinearProgressIndicator()),
      Row(children: [
        Expanded(child: FilledButton.icon(onPressed: busy || n == 0 ? null : () => _go(false), icon: const Icon(Icons.share_rounded), label: const Text('مشاركة PDF'))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(onPressed: busy || n == 0 ? null : () => _go(true), icon: const Icon(Icons.print_rounded), label: const Text('طباعة'))),
      ]),
    ]);
  }
}

/// شيت عام: عدد الإيصالات + شريط الإخراج (بيستخدمه التحصيل حسب المدة)
Future<void> showSlipOutputSheet(BuildContext context,
        {required int count, required Future<List<SlipData>> Function() build, String name = 'receipts', String title = 'طباعة الإيصالات'}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 10),
          const SlipLangPicker(),
          const SizedBox(height: 12),
          OutputBar(count: count, build: build, name: name),
        ]),
      ),
    );

/// طباعة دفتر أقساط عميل: القسط الحالي / شهر معين / كل الأقساط / من قسط لقسط
Future<void> showCustomerPrintSheet(BuildContext context, CustFin c, {int initialMode = 0}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CustPrint(c: c, mode: initialMode),
    );

class _CustPrint extends StatefulWidget {
  const _CustPrint({required this.c, this.mode = 0});
  final CustFin c;
  final int mode;
  @override
  State<_CustPrint> createState() => _CP();
}

class _CP extends State<_CustPrint> {
  late final List<InstRow> rows = installmentRows(widget.c);
  late int mode = widget.mode;
  bool includePaid = false;
  String? month;
  final from = TextEditingController(), to = TextEditingController();
  CompanyInfo? co;

  @override
  void initState() {
    super.initState();
    companyInfo().then((v) {
      if (mounted) setState(() => co = v);
    });
  }

  @override
  void dispose() {
    from.dispose();
    to.dispose();
    super.dispose();
  }

  String _ym(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

  List<String> get months {
    final s = <String>[];
    for (final r in rows) {
      if (r.due == null) continue;
      final k = _ym(r.due!);
      if (!s.contains(k)) s.add(k);
    }
    return s;
  }

  String? get defMonth {
    for (final r in rows) {
      if (!r.paid && r.due != null) return _ym(r.due!);
    }
    return months.isEmpty ? null : months.last;
  }

  List<InstRow> get sel {
    bool ok(InstRow r) => includePaid || !r.paid;
    switch (mode) {
      case 0:
        for (final r in rows) {
          if (!r.paid) return [r];
        }
        return [];
      case 1:
        final m = month ?? defMonth;
        return [for (final r in rows) if (r.due != null && _ym(r.due!) == m && ok(r)) r];
      case 2:
        return [for (final r in rows) if (ok(r)) r];
      default:
        final a = int.tryParse(trDigits(from.text.trim())) ?? 0, b = int.tryParse(trDigits(to.text.trim())) ?? 0;
        final lo = a <= 0 ? 1 : a, hi = b <= 0 ? rows.length : b;
        return [for (final r in rows) if (r.no >= lo && r.no <= hi && ok(r)) r];
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final s = sel;
    const labels = ['القسط الحالي', 'شهر معين', 'كل الأقساط', 'من قسط لقسط'];
    final sum = s.fold<double>(0, (t, r) => t + (r.status == 'partial' ? r.toPay : r.amount));
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('طباعة إيصالات ${c.name}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        Text('${c.months} قسط • المسدد ${c.paidCount} • المتبقي ${fmtMoney(c.remaining)} جنيه', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 10),
        const SlipLangPicker(),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.center, children: [
          for (var i = 0; i < labels.length; i++) ChoiceChip(label: Text(labels[i]), selected: mode == i, onSelected: (_) => setState(() => mode = i)),
        ]),
        const SizedBox(height: 10),
        if (mode == 1)
          months.isEmpty
              ? const Text('مفيش تواريخ استحقاق للعميل ده', textAlign: TextAlign.center)
              : DropdownButtonFormField<String>(
                  value: month ?? defMonth,
                  decoration: const InputDecoration(labelText: 'الشهر'),
                  items: [for (final m in months) DropdownMenuItem(value: m, child: Text(arDigits(m.replaceAll('-', '/'))))],
                  onChanged: (v) => setState(() => month = v),
                ),
        if (mode == 3)
          Row(children: [
            Expanded(child: TextField(controller: from, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'من قسط رقم'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: to, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'إلى قسط رقم'))),
          ]),
        if (mode != 0)
          SwitchListTile(
            dense: true, contentPadding: EdgeInsets.zero,
            title: const Text('اطبع المسدد كمان'),
            value: includePaid, onChanged: (v) => setState(() => includePaid = v),
          ),
        if (s.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 6), padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.purple.withValues(alpha: .08), borderRadius: BorderRadius.circular(14)),
            child: Text(
              s.length == 1
                  ? 'القسط ${s.first.no} • ${s.first.due == null ? '' : slashDate(s.first.due!)} • ${fmtMoney(s.first.status == 'partial' ? s.first.toPay : s.first.amount)} جنيه'
                  : 'من القسط ${s.first.no} (${s.first.due == null ? '-' : slashDate(s.first.due!)}) إلى القسط ${s.last.no} (${s.last.due == null ? '-' : slashDate(s.last.due!)})\nإجمالي ${fmtMoney(sum)} جنيه',
              textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        const SizedBox(height: 6),
        if (co == null)
          const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator())
        else
          OutputBar(count: s.length, name: 'receipts_${c.code}', build: () async => [for (final r in sel) slipForRow(c, co!, r)]),
      ]),
    );
  }
}
