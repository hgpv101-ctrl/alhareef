// رسائل واتساب لكل العملاء (على دفعات + تتبّع مين اتبعتله) • العملاء الأقرب لمكانك + جولة على خرائط جوجل.
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/engine.dart';
import '../core/utils.dart';
import '../data/db.dart';
import '../theme.dart';
import 'customers.dart' show openWhatsapp, reminderText, waNumber;
import 'location.dart';
import 'widgets.dart';

Future<void> _ensureLog() => AppDb.i.db.execute(
    'CREATE TABLE IF NOT EXISTS wa_log (campaign TEXT, customer_code TEXT, ts TEXT, PRIMARY KEY (campaign, customer_code))');

// =================== رسائل واتساب للعملاء ===================

enum _Aud { all, late, due, unsettled }

class BulkMessageScreen extends StatefulWidget {
  const BulkMessageScreen({super.key});
  @override
  State<BulkMessageScreen> createState() => _BM();
}

class _BM extends State<BulkMessageScreen> {
  List<CustFin> all = [];
  Set<String> sent = {};
  bool loading = true;
  _Aud aud = _Aud.late;
  String region = '';
  bool reminder = true; // true = تذكير تلقائي بالقسط، false = رسالة حرة
  int batchSize = 30;
  int batch = 0;
  final campaign = TextEditingController(text: 'حملة ${slashDate(today())}');
  final msg = TextEditingController(
      text: 'السلام عليكم {الاسم} 🌹\nمعاك {الشركة}.\nالمتبقي على حضرتك {المتبقي} جنيه، وقسطك {القسط} جنيه.\nشكراً لتعاملك معانا.');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    campaign.dispose();
    msg.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _ensureLog();
    final f = await AppDb.i.financials();
    if (!mounted) return;
    setState(() { all = f; loading = false; });
    await _loadSent();
  }

  Future<void> _loadSent() async {
    final r = await AppDb.i.db.query('wa_log', columns: ['customer_code'], where: 'campaign=?', whereArgs: [campaign.text.trim()]);
    if (mounted) setState(() => sent = {for (final x in r) x['customer_code'].toString()});
  }

  List<String> get regions => {for (final c in all) if (c.region.trim().isNotEmpty) c.region.trim()}.toList()..sort();

  List<CustFin> get audience {
    final t = today();
    return [
      for (final c in all)
        if (waNumber(c.phone).length >= 9 &&
            (region.isEmpty || c.region.trim() == region) &&
            switch (aud) {
              _Aud.all => true,
              _Aud.late => c.late && !c.settled,
              _Aud.due => !c.settled && c.nextDue != null && !c.nextDue!.isAfter(t),
              _Aud.unsettled => !c.settled,
            })
          c,
    ];
  }

  String _text(CustFin c) {
    if (reminder) return reminderText(c);
    final amt = c.suggested > 0 ? c.suggested : c.monthly;
    return msg.text
        .replaceAll('{الاسم}', c.name)
        .replaceAll('{المتبقي}', fmtMoney(c.remaining))
        .replaceAll('{القسط}', fmtMoney(amt))
        .replaceAll('{المتأخر}', fmtMoney(c.arrears))
        .replaceAll('{الاستحقاق}', c.nextDue == null ? '' : slashDate(c.nextDue!))
        .replaceAll('{الشركة}', AppDb.i.cached('company_name'));
  }

  Future<void> _mark(String code, bool on) async {
    final k = campaign.text.trim();
    if (on) {
      await AppDb.i.db.insert('wa_log', {'campaign': k, 'customer_code': code, 'ts': DateTime.now().toIso8601String()});
    } else {
      await AppDb.i.db.delete('wa_log', where: 'campaign=? AND customer_code=?', whereArgs: [k, code]);
    }
    await _loadSent();
  }

  Future<void> _send(CustFin c) async {
    if (campaign.text.trim().isEmpty) {
      toast(context, 'اكتب اسم للحملة الأول', err: true);
      return;
    }
    try {
      await openWhatsapp(c.phone, _text(c));
      await _mark(c.code, true);
    } catch (_) {
      if (mounted) toast(context, 'مش قادر أفتح واتساب', err: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = audience;
    final batches = list.isEmpty ? 1 : (list.length / batchSize).ceil();
    if (batch >= batches) batch = batches - 1;
    final part = list.skip(batch * batchSize).take(batchSize).toList();
    final doneAll = list.where((c) => sent.contains(c.code)).length;
    final todo = part.where((c) => !sent.contains(c.code)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('رسائل واتساب للعملاء')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(14), children: [
              Field('اسم الحملة (نفس الاسم = بتكمّل من حيث وقفت)', campaign),
              Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: _loadSent, child: const Text('تحديث حالة الإرسال'))),
              const Text('مين هيستلم؟', style: TextStyle(fontWeight: FontWeight.w800)),
              Wrap(spacing: 8, children: [
                for (final e in {_Aud.all: 'كل العملاء', _Aud.late: 'المتأخرين', _Aud.due: 'استحق قسطهم', _Aud.unsettled: 'غير المسددين'}.entries)
                  ChoiceChip(label: Text(e.value), selected: aud == e.key, onSelected: (_) => setState(() { aud = e.key; batch = 0; })),
              ]),
              if (regions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: DropdownButtonFormField<String>(
                    value: region, decoration: const InputDecoration(labelText: 'المنطقة'),
                    items: [const DropdownMenuItem(value: '', child: Text('كل المناطق')), for (final r in regions) DropdownMenuItem(value: r, child: Text(r))],
                    onChanged: (v) => setState(() { region = v ?? ''; batch = 0; }),
                  ),
                ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [ButtonSegment(value: true, label: Text('تذكير بالقسط')), ButtonSegment(value: false, label: Text('رسالة أكتبها'))],
                selected: {reminder},
                onSelectionChanged: (s) => setState(() => reminder = s.first),
              ),
              if (!reminder) ...[
                const SizedBox(height: 8),
                Field('نص الرسالة', msg, lines: 5),
                const Text('تقدر تستخدم: {الاسم} {المتبقي} {القسط} {المتأخر} {الاستحقاق} {الشركة}', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
              const SizedBox(height: 12),
              Row(children: [
                const Text('حجم الدفعة: '),
                for (final n in [20, 30, 50, 100])
                  Padding(padding: const EdgeInsets.only(left: 6), child: ChoiceChip(label: Text('$n'), selected: batchSize == n, onSelected: (_) => setState(() { batchSize = n; batch = 0; }))),
              ]),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('المستهدفين: ${list.length} عميل (عندهم رقم)  •  اتبعتلهم: $doneAll  •  فاضل: ${list.length - doneAll}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: list.isEmpty ? 0 : doneAll / list.length, minHeight: 8, borderRadius: BorderRadius.circular(6)),
                    const SizedBox(height: 8),
                    Row(children: [
                      IconButton(onPressed: batch > 0 ? () => setState(() => batch--) : null, icon: const Icon(Icons.chevron_right_rounded)),
                      Expanded(child: Text('الدفعة ${batch + 1} من $batches  (${part.length} عميل، فاضل ${todo.length})', textAlign: TextAlign.center)),
                      IconButton(onPressed: batch < batches - 1 ? () => setState(() => batch++) : null, icon: const Icon(Icons.chevron_left_rounded)),
                    ]),
                    const SizedBox(height: 4),
                    FilledButton.icon(
                      onPressed: todo.isEmpty ? null : () => _send(todo.first),
                      icon: const Icon(Icons.send_rounded),
                      label: Text(todo.isEmpty ? 'الدفعة دي خلصت ✅' : 'ابعت للتالي: ${todo.first.name}'),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('كل ضغطة بتفتح واتساب بالرسالة جاهزة لعميل — دوس «إرسال» وارجع للتطبيق وكمّل. واتساب مابيسمحش بإرسال جماعي أوتوماتيك من غير خدمة API مدفوعة.',
                          style: TextStyle(color: Colors.grey, fontSize: 11.5)),
                    ),
                  ]),
                ),
              ),
              for (final c in part)
                Card(
                  child: ListTile(
                    leading: Icon(sent.contains(c.code) ? Icons.check_circle_rounded : Icons.radio_button_unchecked, color: sent.contains(c.code) ? C.green : Colors.grey),
                    title: Text(c.name),
                    subtitle: Text('${c.phone}  •  متبقي ${fmtMoney(c.remaining)}${c.late ? '  •  متأخر' : ''}'),
                    trailing: IconButton(tooltip: 'ابعت', icon: const Icon(Icons.chat_rounded, color: C.green), onPressed: () => _send(c)),
                    onTap: sent.contains(c.code) ? () => _mark(c.code, false) : null,
                    onLongPress: () => _mark(c.code, !sent.contains(c.code)),
                  ),
                ),
              const Padding(padding: EdgeInsets.all(8), child: Text('اضغط على عميل اتبعتله لتلغي العلامة، أو اضغط مطوّلاً لتعلّم/تلغي يدوي.', style: TextStyle(color: Colors.grey, fontSize: 11.5))),
            ]),
    );
  }
}

// =================== العملاء الأقرب لمكانك ===================

enum _St { all, late, ok, unsettled }

class NearbyCustomersScreen extends StatefulWidget {
  const NearbyCustomersScreen({super.key});
  @override
  State<NearbyCustomersScreen> createState() => _NC();
}

class _NC extends State<NearbyCustomersScreen> {
  List<CustFin> all = [];
  Map<String, GeoPt> locs = {};
  GeoPt? me;
  bool loading = true, busy = false;
  _St st = _St.unsettled;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final f = await AppDb.i.financials();
    final l = await AppDb.i.customerLocations();
    if (mounted) setState(() { all = f; locs = l; loading = false; });
    await _locate();
  }

  Future<void> _locate() async {
    setState(() => busy = true);
    try {
      final p = await currentGeo();
      if (mounted) setState(() => me = p);
    } on FormatException catch (e) {
      if (mounted) toast(context, e.message, err: true);
    } catch (e) {
      if (mounted) toast(context, 'ما قدرتش أجيب مكانك: ${errText(e)}', err: true);
    }
    if (mounted) setState(() => busy = false);
  }

  double? _km(CustFin c) {
    final p = locs[c.code];
    if (p == null || me == null) return null;
    return Geolocator.distanceBetween(me!.lat, me!.lng, p.lat, p.lng) / 1000;
  }

  List<CustFin> get list {
    final r = [
      for (final c in all)
        if (locs[c.code] != null &&
            switch (st) { _St.all => true, _St.late => c.late && !c.settled, _St.ok => !c.late && !c.settled, _St.unsettled => !c.settled })
          c,
    ];
    if (me != null) r.sort((a, b) => _km(a)!.compareTo(_km(b)!));
    return r;
  }

  /// جولة: أقرب [n] عميل كنقاط على خرائط جوجل (جوجل بيقبل لحد 9 نقاط وسيطة)
  Future<void> _tour(List<CustFin> l) async {
    if (me == null || l.isEmpty) return;
    final pts = [for (final c in l.take(9)) locs[c.code]!];
    final dest = pts.last;
    final way = pts.length > 1 ? pts.sublist(0, pts.length - 1).map((p) => '${p.lat},${p.lng}').join('|') : '';
    final u = 'https://www.google.com/maps/dir/?api=1&origin=${me!.lat},${me!.lng}&destination=${dest.lat},${dest.lng}'
        '${way.isEmpty ? '' : '&waypoints=${Uri.encodeComponent(way)}'}&travelmode=driving';
    final ok = await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && mounted) toast(context, 'مش قادر أفتح خرائط جوجل', err: true);
  }

  @override
  Widget build(BuildContext context) {
    final l = list;
    final noLoc = all.where((c) => locs[c.code] == null && !c.settled).length;
    return Scaffold(
      appBar: AppBar(title: const Text('العملاء الأقرب ليك'), actions: [IconButton(onPressed: busy ? null : _locate, icon: const Icon(Icons.my_location_rounded))]),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(14), children: [
              Wrap(spacing: 8, children: [
                for (final e in {_St.unsettled: 'غير المسددين', _St.late: 'متأخر', _St.ok: 'منتظم', _St.all: 'الكل'}.entries)
                  ChoiceChip(label: Text(e.value), selected: st == e.key, onSelected: (_) => setState(() => st = e.key)),
              ]),
              const SizedBox(height: 8),
              Text(me == null ? 'مكانك لسه ما اتحددش — اضغط 📍 فوق عشان يرتّبهم من الأقرب.' : 'مرتّبين من الأقرب لمكانك الحالي. (${l.length} عميل ليهم موقع)',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              if (noLoc > 0) Text('$noLoc عميل غير مسدد لسه ملهمش موقع محدد.', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: me == null || l.isEmpty ? null : () => _tour(l),
                icon: const Icon(Icons.route_rounded),
                label: Text('ابدأ جولة على أقرب ${l.length < 9 ? l.length : 9} عملاء في خرائط جوجل'),
              ),
              const SizedBox(height: 8),
              for (final c in l)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      radius: 8,
                      backgroundColor: c.settled ? C.green : (c.late ? C.red : C.blue),
                    ),
                    title: Text(c.name),
                    subtitle: Text('${c.region.isEmpty ? '' : '${c.region}  •  '}متبقي ${fmtMoney(c.remaining)}${c.late ? '  •  متأخر ${c.lateMonths} شهر' : ''}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (_km(c) != null) Text('${_km(c)!.toStringAsFixed(_km(c)! < 10 ? 1 : 0)} كم', style: const TextStyle(fontWeight: FontWeight.w800)),
                      IconButton(tooltip: 'ملاحة', icon: const Icon(Icons.directions_rounded, color: C.blue), onPressed: () => navigateTo(context, locs[c.code]!)),
                    ]),
                    onTap: () => openInMaps(context, locs[c.code]!),
                  ),
                ),
            ]),
    );
  }
}
