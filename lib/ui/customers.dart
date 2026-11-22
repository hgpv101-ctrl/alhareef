import 'dart:async';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/receipt_data.dart';
import '../core/engine.dart';
import '../core/utils.dart';
import '../data/db.dart';
import '../data/ops.dart';
import '../data/stock.dart';
import '../theme.dart';
import 'items_editor.dart';
import 'location.dart';
import 'receipt_center.dart';
import 'receipt_pdf.dart';
import 'widgets.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _S();
}

class _S extends State<CustomersScreen> {
  List<CustFin> all = [], list = [];
  Map<String, GeoPt> locs = {}; // مواقع العملاء اللي ليهم موقع
  List<String> idx = []; // نص البحث لكل عميل بيتجهّز مرة واحدة مش مع كل ضغطة
  String q = '', filter = 'الكل';
  Timer? _deb;
  bool _loading = false, _again = false;

  @override
  void initState() {
    super.initState();
    _load();
    dataRev.addListener(_load);
  }

  @override
  void dispose() {
    dataRev.removeListener(_load);
    _deb?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) {
      _again = true;
      return;
    }
    _loading = true;
    try {
      do {
        _again = false;
        final f = await AppDb.i.financials();
        final lc = await AppDb.i.customerLocations();
        final ix = [for (final c in f) normAr('${c.name} ${c.code} ${c.phone} ${c.region} ${c.item}')];
        if (!mounted) return;
        setState(() {
          all = f;
          locs = lc;
          idx = ix;
          _apply();
        });
      } while (_again);
    } finally {
      _loading = false;
    }
  }

  void _apply() {
    final nq = normAr(q);
    final out = <CustFin>[];
    for (var i = 0; i < all.length; i++) {
      final f = all[i];
      if (filter == 'متأخر' && !f.late) continue;
      if (filter == 'مسدد' && !f.settled) continue;
      if (filter == 'شغال' && (f.settled || f.late)) continue;
      if (nq.isEmpty || idx[i].contains(nq)) out.add(f);
    }
    list = out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('العملاء (${all.length})')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerForm()));
          _load();
        },
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('عميل جديد'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: TextField(onChanged: (v) {
            _deb?.cancel();
            _deb = Timer(const Duration(milliseconds: 220), () {
              if (mounted) setState(() { q = v; _apply(); });
            });
          }, decoration: const InputDecoration(hintText: 'ابحث بالاسم أو الكود أو التليفون', prefixIcon: Icon(Icons.search))),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
            for (final t in ['الكل', 'شغال', 'متأخر', 'مسدد'])
              Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ChoiceChip(label: Text(t), selected: filter == t, onSelected: (_) => setState(() { filter = t; _apply(); }))),
          ]),
        ),
        Expanded(
          child: list.isEmpty
              ? const Empty('مفيش عملاء')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 90),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final f = list[i];
                    final pct = f.total > 0 ? (f.paidTotal / f.total).clamp(0, 1).toDouble() : 0.0;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetail(code: f.code)));
                          _load();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              CircleAvatar(radius: 18, backgroundColor: C.purple.withValues(alpha: .13), child: Text(f.name.isEmpty ? '?' : f.name.substring(0, 1), style: const TextStyle(color: C.purple, fontWeight: FontWeight.w900))),
                              const SizedBox(width: 10),
                              Expanded(child: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                              if (locs[f.code] != null)
                                IconButton(
                                  tooltip: 'مكان العميل على خرائط جوجل', visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.location_on_rounded, color: C.green),
                                  onPressed: () => openInMaps(context, locs[f.code]!),
                                ),
                              if (f.settled) const Pill('مسدد ✓', C.green) else if (f.late) Pill('متأخر ${f.lateMonths} شهر', C.red) else const Pill('منتظم', C.blue),
                            ]),
                            Text('${f.code}  •  ${f.region}  •  ${f.item}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            const SizedBox(height: 8),
                            ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: pct, minHeight: 8, color: C.purple, backgroundColor: C.purple.withValues(alpha: .12))),
                            const SizedBox(height: 6),
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Text('المتبقي ${fmtMoney(f.remaining)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                              if (f.arrears > 0) Text('متأخر ${fmtMoney(f.arrears)}', style: const TextStyle(color: C.red, fontWeight: FontWeight.w700)),
                            ]),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class CustomerForm extends StatefulWidget {
  const CustomerForm({super.key, this.edit});
  final CustFin? edit;
  @override
  State<CustomerForm> createState() => _F();
}

class _F extends State<CustomerForm> {
  final name = TextEditingController(), phone = TextEditingController(), addr = TextEditingController(), region = TextEditingController(),
      rep = TextEditingController(), coll = TextEditingController(), item = TextEditingController(), total = TextEditingController(), down = TextEditingController(),
      months = TextEditingController(), plan = TextEditingController(), code = TextEditingController(),
      buyDate = TextEditingController(), firstDate = TextEditingController();
  final tN = List.generate(4, (_) => TextEditingController()), tA = List.generate(4, (_) => TextEditingController());
  List<Map<String, Object?>> regions = [], reps = [], colls = [], prods = [], oldItems = [];
  final lines = <SaleLine>[];
  bool totalTouched = false, itemTouched = false, enItemTouched = false;
  String? nextCode; // الكود اللي هيتدّي تلقائي (واحد للعربي والإنجليزي)
  bool en = false; // تبويب الإدخال: عربي / English (إيصال Contract Credit)
  final enName = TextEditingController(), enAddr = TextEditingController(), enItem = TextEditingController();
  GeoPt? geo;
  bool geoLoaded = true; // في التعديل: ما نكتبش الموقع قبل ما يتحمّل (عشان ما نمسحوش بالغلط)

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    if (e != null) {
      geoLoaded = false;
      AppDb.i.customerLocation(e.code).then((p) {
        if (mounted) setState(() { geo ??= p; geoLoaded = true; });
      });
    }
    if (e != null) {
      name.text = e.name; phone.text = e.phone; addr.text = e.address; region.text = e.region; rep.text = e.rep; coll.text = e.collector; item.text = e.item;
      total.text = numText(e.total); down.text = numText(e.down); months.text = '${e.months}'; plan.text = e.plan;
      code.text = e.code;
      enName.text = e.enName; enAddr.text = e.enAddress; enItem.text = e.enItem;
      buyDate.text = e.start ?? '';
      firstDate.text = e.firstDue == null ? '' : isoDate(e.firstDue!);
      try {
        final pl = parsePlan(e.plan);
        for (var i = 0; i < pl.length && i < 4; i++) {
          tN[i].text = '${pl[i][0]}'; tA[i].text = numText((pl[i][1]).toDouble());
        }
      } catch (_) {}
    } else {
      AppDb.i.nextCustomerCode().then((v) {
        if (mounted) setState(() => nextCode = v);
      });
      AppDb.i.getSetting('default_months').then((v) => months.text = v);
      buyDate.text = isoDate(today());
      firstDate.text = isoDate(addMonths(today(), 1));
    }
    () async {
      final d = AppDb.i.db;
      regions = await d.query('regions', orderBy: 'name');
      reps = await d.query('representatives', where: "type='المناديب'", orderBy: 'name');
      // لو خيار «المحصّل = المندوب» شغّال، المناديب كمان بيظهروا كاختيار للمحصّل
      colls = await d.query('representatives', where: (await AppDb.i.getSetting('rep_is_collector')) == 'نعم' ? "type IN ('المحصلين','المناديب')" : "type='المحصلين'", orderBy: 'name');
      prods = await d.query('products', orderBy: 'name');
      if (widget.edit != null) oldItems = await AppDb.i.customerItems(widget.edit!.code);
      if (mounted) setState(() {});
    }();
  }

  String numText(double v) => v == v.truncate() ? '${v.truncate()}' : '$v';

  /// لما الأصناف تتغيّر: الإجمالي والمنتج بيتملّوا تلقائي (إلا لو إنت عدّلتهم بإيدك)
  void _linesChanged() {
    setState(() {
      if (lines.isEmpty) return;
      if (!totalTouched || total.text.trim().isEmpty) total.text = numText(sumLines(lines));
      if (!itemTouched || item.text.trim().isEmpty) item.text = itemsDesc([for (final l in lines) l.toMap()]);
      // PRODUCT بالإنجليزي: اسم الصنف الإنجليزي من المخزن (ولو مش مكتوب بنستخدم اسمه العربي)
      if (!enItemTouched || enItem.text.trim().isEmpty) {
        enItem.text = itemsDesc([for (final l in lines) {...l.toMap(), 'name': l.enName.trim().isNotEmpty ? l.enName.trim() : l.name}]);
      }
    });
  }

  /// نظام القسط من الخانات الأربع: "8×150 + 5×380"
  String tiersText() {
    final parts = <String>[];
    for (var i = 0; i < 4; i++) {
      final n = int.tryParse(trDigits(tN[i].text.trim())) ?? 0, a = parseNumSafe(tA[i].text);
      if (n > 0 && a > 0) parts.add('$n×${a == a.truncate() ? a.truncate() : a}');
    }
    return parts.join(' + ');
  }

  double _tiersTotal() {
    var x = 0.0;
    for (var i = 0; i < 4; i++) {
      x += (int.tryParse(trDigits(tN[i].text.trim())) ?? 0) * parseNumSafe(tA[i].text);
    }
    return x;
  }

  Future<void> pickDate(TextEditingController c, {bool syncFirst = false}) async {
    final init = toDate(c.text) ?? today();
    final d = await showDatePicker(context: context, initialDate: init, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d == null) return;
    setState(() {
      c.text = isoDate(d);
      if (syncFirst) firstDate.text = isoDate(addMonths(d, 1));
    });
  }

  Widget dateField(String label, TextEditingController c, {bool syncFirst = false}) => Expanded(
        child: TextField(
          controller: c, readOnly: true, onTap: () => pickDate(c, syncFirst: syncFirst),
          decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.event_rounded)),
        ),
      );

  Widget pick(String label, TextEditingController c, List<String> opts) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Autocomplete<String>(
          optionsBuilder: (t) => opts.where((o) => normAr(o).contains(normAr(t.text))),
          initialValue: TextEditingValue(text: c.text),
          onSelected: (v) => c.text = v,
          fieldViewBuilder: (_, ctl, fn, __) => TextField(controller: ctl, focusNode: fn, onChanged: (v) => c.text = v, decoration: InputDecoration(labelText: label)),
        ),
      );

  /// أصناف المخزن (مشتركة بين تبويبي عربي / English)
  List<Widget> _itemsBlock() => [
        if (widget.edit == null)
          ItemsEditor(products: prods, lines: lines, onChanged: _linesChanged, title: 'المنتجات (أضف أكتر من منتج — السعر والإجمالي بيتحسبوا تلقائي)')
        else if (oldItems.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('الأصناف المسجّلة على العقد', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                for (final it in oldItems)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('${it['qty']} × ${it['product_name']}'),
                      Text(fmtMoney((it['line_total'] ?? 0) as num), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                  ),
                const Text('لتغيير الأصناف بعد البيع استخدم «المرتجعات».', style: TextStyle(color: Colors.grey, fontSize: 11)),
              ]),
            ),
          ),
      ];

  /// خانات الإيصال الإنجليزي (Contract Credit) بنفس ترتيب الإيصال
  List<Widget> _enFields(double monthly, double t, double d) => [
        const Text('English Contract — بيانات الإيصال الإنجليزي (منفصلة عن العربي)', style: TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 10),
        ..._itemsBlock(),
        TextField(controller: enItem, onChanged: (_) => enItemTouched = true, decoration: const InputDecoration(labelText: 'PRODUCT')),
        Row(children: [
          Expanded(child: TextField(controller: total, onChanged: (_) => setState(() => totalTouched = true), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'TOTAL PRICE'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: down, onChanged: (_) => setState(() {}), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ADVANCE'))),
        ]),
        const SizedBox(height: 10),
        Row(children: [dateField('DATE OF PURCHASE', buyDate, syncFirst: true), const SizedBox(width: 8), dateField('FIRST PAYMENT DATE', firstDate)]),
        const SizedBox(height: 14),
        const Text('PAYMENT SCHEDULE (months × monthly payment)', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(child: TextField(controller: tN[i], onChanged: (_) => setState(() {}), keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Stage ${i + 1}: months'))),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('×', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
              Expanded(child: TextField(controller: tA[i], onChanged: (_) => setState(() {}), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'MONTHLY PAYMENT'))),
            ]),
          ),
        if (tiersText().isEmpty) TextField(controller: months, onChanged: (_) => setState(() {}), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'or: number of months (fixed payment)')),
        const SizedBox(height: 14),
        Field('1. CUSTOMERS NAME', enName),
        Field('2. CUSTOMERS NUMBER', phone, num: true),
        Field('3. CUSTOMERS ADDRESS', enAddr),
        TextField(controller: code, enabled: widget.edit == null, decoration: InputDecoration(labelText: '4. CUSTOMERS CODE', hintText: nextCode == null ? null : 'next: $nextCode')),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: C.purple.withValues(alpha: .1), borderRadius: BorderRadius.circular(14)),
          child: Text(tiersText().isNotEmpty
              ? 'Plan: ${tiersText()}\nTotal ${fmtMoney(_tiersTotal())} — balance after advance ${fmtMoney(t - d)}'
              : 'Monthly payment: ${fmtMoney(monthly)}'),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final t = parseNumSafe(total.text), d = parseNumSafe(down.text), m = int.tryParse(trDigits(months.text)) ?? 0;
    final monthly = (m > 0 && t > d) ? (t - d) / m : 0.0;
    return Scaffold(
      appBar: AppBar(title: Text(widget.edit == null ? 'عميل جديد' : 'تعديل عميل')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('عربي')),
              ButtonSegment(value: true, label: Text('English Contract')),
            ],
            selected: {en},
            onSelectionChanged: (v) => setState(() => en = v.first),
          ),
        ),
        const SizedBox(height: 12),
        if (en) ..._enFields(monthly, t, d) else ...[
        // ترتيب الخانات زي الإيصال الورقي
        Row(children: [
          Expanded(child: TextField(controller: code, enabled: widget.edit == null, keyboardType: TextInputType.text, decoration: InputDecoration(labelText: 'كود العميل (اختياري)', hintText: nextCode == null ? null : 'التالي: $nextCode'))),
          const SizedBox(width: 8),
          Expanded(child: Field('هاتف', phone, num: true)),
        ]),
        pick('المنطقة', region, [for (final r in regions) r['name'].toString()]),
        Field('اسم العميل', name),
        Field('العنوان', addr),
        LocationField(addr: addr, point: geo, onChanged: (p) => setState(() => geo = p)),
        ..._itemsBlock(),
        const SizedBox(height: 10),
        TextField(
          controller: item, onChanged: (_) => itemTouched = true,
          decoration: const InputDecoration(labelText: 'وصف المنتجات على الإيصال (بيتكتب تلقائي من الأصناف)'),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: total, onChanged: (_) => setState(() => totalTouched = true), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الإجمالي'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: down, onChanged: (_) => setState(() {}), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المقدم'))),
        ]),
        const SizedBox(height: 10),
        Row(children: [dateField('تاريخ الشراء', buyDate, syncFirst: true), const SizedBox(width: 8), dateField('تاريخ الدفع (أول قسط)', firstDate)]),
        const SizedBox(height: 14),
        const Text('نظام القسط (عدد الشهور × قيمة القسط)', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(child: TextField(controller: tN[i], onChanged: (_) => setState(() {}), keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'مرحلة ${i + 1}: عدد الشهور'))),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('×', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
              Expanded(child: TextField(controller: tA[i], onChanged: (_) => setState(() {}), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'القسط'))),
            ]),
          ),
        if (tiersText().isEmpty) TextField(controller: months, onChanged: (_) => setState(() {}), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'أو: عدد شهور بقسط ثابت')),
        const SizedBox(height: 10),
        pick('المندوب (البائع)', rep, [for (final r in reps) r['name'].toString()]),
        pick('المحصّل (اللي بيجمّع القسط)', coll, [for (final r in colls) r['name'].toString()]),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: C.purple.withValues(alpha: .1), borderRadius: BorderRadius.circular(14)),
          child: Text(tiersText().isNotEmpty
              ? 'نظام القسط: ${tiersText()}\nمجموعه ${fmtMoney(_tiersTotal())} — المتبقي بعد المقدم ${fmtMoney(t - d)}'
              : 'القسط الشهري: ${fmtMoney(monthly)} جنيه\n${t > 0 ? moneyWords(monthly) : ''}'),
        ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.save_rounded),
          label: const Text('حفظ'),
          onPressed: () => guard(context, () async {
            final data = {
              // كل تبويب يشتغل لوحده: لو الاسم/العنوان/المنتج العربي فاضيين بنستخدم الإنجليزي (والعكس مش لازم)
              'name': name.text.trim().isNotEmpty ? name.text : enName.text, 'phone': phone.text,
              'address': addr.text.trim().isNotEmpty ? addr.text : enAddr.text, 'region': region.text, 'rep': rep.text, 'collector': coll.text,
              'item': item.text.trim().isNotEmpty ? item.text : enItem.text,
              'total': parseNum(total.text), 'down': parseNum(down.text), 'months': parseNum(months.text).toInt(), 'plan': tiersText(),
              'code': code.text.trim(), 'start': buyDate.text.trim(), 'first_due': firstDate.text.trim(),
              if (geoLoaded) ...{'lat': geo?.lat, 'lng': geo?.lng},
              'en_name': enName.text, 'en_address': enAddr.text, 'en_item': enItem.text,
              if (widget.edit == null && lines.isNotEmpty) 'items': [for (final l in lines) l.toMap()],
            };
            if (widget.edit == null) {
              final code = await AppDb.i.addCustomer(data);
              if (mounted) toast(context, 'اتسجل العميل بكود $code');
              if (mounted && await confirm(context, 'تطبع دفتر الأقساط (إيصال لكل قسط)؟')) {
                final nf = await AppDb.i.financials(code: code);
                if (nf.isNotEmpty && mounted) await showCustomerPrintSheet(context, nf.first, initialMode: 2);
              }
            } else {
              if (!await adminGate(context)) return;
              await AppDb.i.updateCustomer(widget.edit!.code, data);
              if (mounted) toast(context, 'اتحفظ التعديل');
            }
            if (mounted) Navigator.pop(context);
          }),
        ),
      ]),
    );
  }
}

double parseNumSafe(String s) {
  try {
    return parseNum(s);
  } catch (_) {
    return 0;
  }
}

class CustomerDetail extends StatefulWidget {
  const CustomerDetail({super.key, required this.code});
  final String code;
  @override
  State<CustomerDetail> createState() => _D();
}

class _D extends State<CustomerDetail> {
  CustFin? f;
  List<Map<String, Object?>> pays = [], items = [];
  GeoPt? geo;
  bool geoBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await AppDb.i.financials(code: widget.code);
    final p = await AppDb.i.customerPayments(widget.code);
    final it = await AppDb.i.customerItems(widget.code);
    final g = await AppDb.i.customerLocation(widget.code);
    if (mounted) setState(() { f = r.isEmpty ? null : r.first; pays = p; items = it; geo = g; });
  }

  /// بيحدد موقع العميل من مكانك دلوقتي (وانت عنده)
  Future<void> _setHere() async {
    setState(() => geoBusy = true);
    try {
      final p = await currentGeo();
      await AppDb.i.setCustomerLocation(widget.code, p.lat, p.lng);
      await _load();
      if (mounted) toast(context, 'اتحفظ موقع العميل ✅');
    } on FormatException catch (e) {
      if (mounted) toast(context, e.message, err: true);
    } catch (e) {
      if (mounted) toast(context, 'ما قدرتش أجيب الموقع: ${errText(e)}', err: true);
    }
    if (mounted) setState(() => geoBusy = false);
  }

  Future<void> _pay() async {
    final c = f!;
    final amt = TextEditingController(text: numT(c.suggested));
    final notes = TextEditingController(text: 'قسط شهري');
    String? col = c.collector.isEmpty ? null : c.collector;
    final reps = await AppDb.i.db.query('representatives', where: "type IN ('المحصلين','المناديب')", orderBy: 'type DESC, name');
    if (!mounted) return;
    final ok = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('تحصيل من ${c.name}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          Text('المتبقي ${fmtMoney(c.remaining)}  •  القسط ${fmtMoney(c.monthly)}'),
          const SizedBox(height: 12),
          Field('المبلغ', amt, num: true),
          if (reps.isNotEmpty)
            DropdownButtonFormField<String>(
              value: reps.any((r) => r['name'].toString() == col) ? col : null,
              decoration: const InputDecoration(labelText: 'المحصّل'),
              items: [for (final r in reps) DropdownMenuItem(value: r['name'].toString(), child: Text(r['name'].toString()))],
              onChanged: (v) => col = v,
            ),
          const SizedBox(height: 10),
          Field('ملاحظات', notes),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تسجيل الدفعة'))),
        ]),
      ),
    );
    if (ok != true || !mounted) return;
    await guard(context, () async {
      final a = parseNum(amt.text);
      await AppDb.i.addPayment(c.code, a, collector: col ?? '', notes: notes.text);
      await _load();
      if (mounted && await confirm(context, 'اتسجلت ${fmtMoney(a)} جنيه. تطبع إيصال الاستلام PDF؟')) {
        if (pays.isNotEmpty) {
          final last = pays.reduce((x, y) => ((x['id'] as num) >= (y['id'] as num)) ? x : y);
          await sharePaymentReceipt(last);
        }
      }
    });
  }

  String numT(double v) => v == v.truncate() ? '${v.truncate()}' : '$v';

  /// خصم على إجمالي العميل (من غير كلمة سر)
  Future<void> _discount(CustFin c) async {
    final amt = TextEditingController(), why = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('خصم لـ ${c.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('المتبقي ${fmtMoney(c.remaining)} جنيه', style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          Field('قيمة الخصم', amt, num: true),
          Field('السبب', why),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('تطبيق الخصم')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final a = parseNumSafe(amt.text);
    if (a <= 0) {
      toast(context, 'اكتب قيمة الخصم', err: true);
      return;
    }
    await guard(context, () async {
      await AppDb.i.addDiscount(c.code, a, why.text.trim());
      await _load();
    }, ok: 'اتطبّق الخصم ✅');
  }

  @override
  Widget build(BuildContext context) {
    final c = f;
    if (c == null) return Scaffold(appBar: AppBar(), body: const Empty('العميل مش موجود'));
    Widget row(String a, String b, {Color? col}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(a, style: const TextStyle(color: Colors.grey)), Text(b, style: TextStyle(fontWeight: FontWeight.w700, color: col))]),
        );
    return Scaffold(
      appBar: AppBar(title: Text(c.name), actions: [
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'edit') {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerForm(edit: c)));
              _load();
            } else if (v == 'del') {
              if (await confirm(context, 'تحذف العميل ${c.name} وكل دفعاته؟') && mounted && await adminGate(context)) {
                await guard(context, () async {
                  await AppDb.i.deleteCustomer(c.code);
                  if (mounted) Navigator.pop(context);
                });
              }
            } else if (v == 'slip') {
              await showCustomerPrintSheet(context, c);
            } else if (v == 'receipt') {
              await shareStatement(c, pays);
            } else if (v == 'en') {
              await guard(context, () async {
                final co = await companyInfo();
                final rows = installmentRows(c);
                if (rows.isEmpty) throw const FormatException('العميل ده ملهوش جدول أقساط.');
                final bytes = await buildSlipsPdf([slipForRow(c, co, rows.first)], SlipLayout.single, lang: SlipLang.en);
                await Printing.sharePdf(bytes: bytes, filename: 'contract_${c.code}.pdf');
              });
            } else if (v == 'disc') {
              await _discount(c);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('تعديل البيانات')),
            PopupMenuItem(value: 'slip', child: Text('طباعة إيصالات الأقساط…')),
            PopupMenuItem(value: 'en', child: Text('إيصال إنجليزي Contract Credit (PDF)')),
            PopupMenuItem(value: 'receipt', child: Text('كشف حساب PDF')),
            PopupMenuItem(value: 'disc', child: Text('خصم للعميل')),
            PopupMenuItem(value: 'del', child: Text('حذف العميل')),
          ],
        ),
      ]),
      floatingActionButton: c.settled ? null : FloatingActionButton.extended(onPressed: _pay, icon: const Icon(Icons.payments_rounded), label: const Text('تحصيل قسط')),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 90), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              row('الكود', c.code),
              row('الموبايل', c.phone.isEmpty ? '-' : c.phone),
              row('المنطقة', c.region),
              row('المندوب', c.rep.isEmpty ? '-' : c.rep),
              row('المحصّل', c.collector.isEmpty ? '-' : c.collector),
              row('البضاعة', c.item),
              const Divider(),
              row('الإجمالي', fmtMoney(c.total)),
              row('المقدم', fmtMoney(c.down)),
              row('الأقساط', c.instDesc),
              row('المدفوع', fmtMoney(c.paidTotal), col: C.green),
              row('المتبقي', fmtMoney(c.remaining), col: C.purple),
              if (c.arrears > 0) row('متأخر (${c.lateMonths} شهر)', fmtMoney(c.arrears), col: C.red),
              if (c.nextDue != null) row('القسط الجاي', isoDate(c.nextDue!)),
              if (c.partial > 0) row('مدفوع جزئياً من القسط', fmtMoney(c.partial)),
            ]),
          ),
        ),
        if (items.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 8),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('الأصناف المباعة', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                for (final it in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Expanded(child: Text('${it['qty']} × ${it['product_name']}${((it['returned_qty'] ?? 0) as num) > 0 ? '  (مرتجع ${it['returned_qty']})' : ''}')),
                      Text(fmtMoney((it['unit_price'] ?? 0) as num), style: const TextStyle(color: Colors.grey)),
                      const SizedBox(width: 10),
                      Text(fmtMoney((it['line_total'] ?? 0) as num), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                  ),
              ]),
            ),
          ),
        Card(
          margin: const EdgeInsets.only(top: 8),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(geo == null ? Icons.location_off_rounded : Icons.location_on_rounded, color: geo == null ? Colors.grey : C.green),
                const SizedBox(width: 8),
                Expanded(child: Text(geo == null ? 'مكان العميل: مش متحدد على الخريطة' : 'مكان العميل متحدد على الخريطة', style: const TextStyle(fontWeight: FontWeight.w800))),
              ]),
              if (c.address.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(c.address, style: const TextStyle(color: Colors.grey, fontSize: 12.5))),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (geo != null) ...[
                  FilledButton.icon(onPressed: () => openInMaps(context, geo!), icon: const Icon(Icons.map_rounded, size: 18), label: const Text('افتح في خرائط جوجل')),
                  OutlinedButton.icon(onPressed: () => navigateTo(context, geo!), icon: const Icon(Icons.directions_rounded, size: 18), label: const Text('ابدأ الملاحة للعميل')),
                ] else if (c.address.isNotEmpty || c.region.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => searchAddressInMaps(context, [c.address, c.region].where((x) => x.trim().isNotEmpty).join(' ')),
                    icon: const Icon(Icons.search_rounded, size: 18), label: const Text('ابحث بالعنوان في خرائط جوجل'),
                  ),
                OutlinedButton.icon(
                  onPressed: geoBusy ? null : _setHere,
                  icon: geoBusy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location_rounded, size: 18),
                  label: Text(geo == null ? 'حدد موقعه من مكاني الحالي' : 'حدّث الموقع (أنا عنده دلوقتي)'),
                ),
              ]),
            ]),
          ),
        ),
        if (c.phone.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: () => launchUrl(Uri.parse('tel:${c.phone}')), icon: const Icon(Icons.call), label: const Text('اتصال'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: () => openWhatsapp(c.phone, reminderText(c)), icon: const Icon(Icons.chat), label: const Text('واتساب'))),
            ]),
          ),
        const Padding(padding: EdgeInsets.fromLTRB(6, 10, 6, 6), child: Text('سجل الدفعات', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        if (pays.isEmpty) const Empty('مفيش دفعات'),
        for (final p in pays.reversed)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              leading: CircleAvatar(backgroundColor: C.green.withValues(alpha: .15), child: const Icon(Icons.check_rounded, color: C.green)),
              title: Text('${fmtMoney(p['amount_paid'] as num)} جنيه', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${p['pay_date']}  •  ${p['due_month']}  •  ${p['collector'] ?? ''}'),
              trailing: p['due_month'] == downLabel
                  ? null
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.print_outlined, color: C.purple),
                        onPressed: () => guard(context, () => sharePaymentReceipt(p)),
                      ),
                      IconButton(
                          icon: const Icon(Icons.delete_outline, color: C.red),
                          onPressed: () async {
                            if (await confirm(context, 'تحذف الدفعة دي؟') && mounted && await adminGate(context)) {
                              await guard(context, () async {
                                await AppDb.i.deletePayment(p['id'] as int);
                                _load();
                              });
                            }
                          }),
                    ]),
            ),
          ),
      ]),
    );
  }
}

String _sig() {
  final co = AppDb.i.cached('company_name').trim(), ph = AppDb.i.cached('phones').trim();
  return '${co.isNotEmpty ? '\n$co' : ''}${ph.isNotEmpty ? '\n📞 $ph' : ''}';
}

/// رسالة تذكير بالقسط (واتساب) — مرتبة وواضحة وفيها كل بيانات الحساب
String reminderText(CustFin c) {
  final amt = c.suggested > 0 ? c.suggested : c.monthly;
  final due = c.nextDue == null ? '' : '\n📅 تاريخ الاستحقاق: ${slashDate(c.nextDue!)}';
  final lateTxt = c.arrears > 0 ? '\n⚠️ متأخر عليك: ${fmtMoney(c.arrears)} جنيه (${c.lateMonths} شهر)' : '';
  return 'السلام عليكم ورحمة الله ${c.name} 🌹'
      '\nبنفكّرك بقسطك الشهري:'
      '\n💰 قيمة القسط: ${fmtMoney(amt)} جنيه$due$lateTxt'
      '\n📌 المتبقي على حضرتك: ${fmtMoney(c.remaining)} جنيه'
      '\n\nلو سدّدت قبل كده تجاهل الرسالة، ولأي استفسار كلّمنا في أي وقت.'
      '\nشكراً لتعاملك معانا 🌹${_sig()}';
}

/// رسالة تأكيد استلام مبلغ
String paymentThanksText(String name, double amount, {double? remaining}) =>
    'السلام عليكم ورحمة الله $name 🌹'
    '\n✅ استلمنا منك مبلغ ${fmtMoney(amount)} جنيه'
    '\n(${moneyWords(amount)})'
    '${remaining != null ? '\n📌 المتبقي على حضرتك: ${fmtMoney(remaining)} جنيه' : ''}'
    '\nشكراً لالتزامك وتعاملك معانا 🌹${_sig()}';

String waNumber(String phone) {
  var d = trDigits(phone).replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('00')) d = d.substring(2);
  if (d.startsWith('0')) d = '2$d';
  return d;
}

Future<void> openWhatsapp(String phone, String text) =>
    launchUrl(Uri.parse('https://wa.me/${waNumber(phone)}?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
