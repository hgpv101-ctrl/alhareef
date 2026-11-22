import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../core/utils.dart';
import '../data/db.dart';
import '../data/ops.dart';
import '../data/repfile.dart';
import '../theme.dart';
import 'customers.dart' show openWhatsapp, parseNumSafe, paymentThanksText;
import 'items_editor.dart';
import 'location.dart';
import 'hareef.dart';
import 'widgets.dart';

/// شاشة المندوب/المحصّل: يسجّل اللي باعه واللي حصّله، وفي الآخر يصدّر ملف ويبعته للمالك.
class RepHomeScreen extends StatefulWidget {
  const RepHomeScreen({super.key});
  @override
  State<RepHomeScreen> createState() => _S();
}

class _S extends State<RepHomeScreen> {
  String name = '', role = 'مندوب';
  double sold = 0, got = 0;
  int nNew = 0, nBase = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = AppDb.i;
    final n = await db.repName, r = await db.repRole;
    final rows = await db.repEntries(onlyNew: true);
    final b = await db.db.rawQuery('SELECT COUNT(*) n FROM rep_base');
    if (!mounted) return;
    setState(() {
      name = n; role = r; nNew = rows.length; nBase = (b.first['n'] as num).toInt();
      sold = rows.where((e) => e['kind'] == 'sale').fold<double>(0.0, (s, e) => s + (e['total'] as num));
      got = rows.where((e) => e['kind'] == 'collect').fold<double>(0.0, (s, e) => s + (e['amount'] as num));
    });
  }

  Future<void> _profile() async {
    final n = TextEditingController(text: name);
    String r = role;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('بياناتي'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Field('اسمي', n),
            DropdownButtonFormField<String>(
              value: r, decoration: const InputDecoration(labelText: 'وظيفتي'),
              items: const [DropdownMenuItem(value: 'مندوب', child: Text('مندوب (بيع وتحصيل)')), DropdownMenuItem(value: 'محصل', child: Text('محصّل (تحصيل فقط)'))],
              onChanged: (v) => set(() => r = v ?? 'مندوب'),
            ),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ'))],
        ),
      ),
    );
    if (ok == true) {
      await AppDb.i.setSetting('rep_name', n.text.trim());
      await AppDb.i.setSetting('rep_role', r);
      _load();
    }
  }

  Future<void> _import() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    final path = res?.files.single.path;
    if (path == null || !mounted) return;
    await guard(context, () async {
      final msg = await AppDb.i.importRepPackage(await File(path).readAsString());
      await _load();
      if (mounted) toast(context, msg);
    });
  }

  Future<void> _export() async {
    if (name.isEmpty) {
      await _profile();
      if (name.isEmpty) return;
    }
    if (!await confirm(context, 'هتخلّص الشغل وتصدّر $nNew سجل (بيع ${fmtMoney(sold)} • تحصيل ${fmtMoney(got)}) وتبعتهم للمالك؟')) return;
    if (!mounted) return;
    await guard(context, () async {
      final path = await AppDb.i.exportRepReport();
      await Share.shareXFiles([XFile(path, mimeType: 'application/json')], subject: 'تقرير $role $name', text: 'تقرير $role $name — بيع ${fmtMoney(sold)} • تحصيل ${fmtMoney(got)}');
      await _load();
    });
  }

  Widget tile(IconData i, String t, String s, Color c, VoidCallback f) => Card(
        child: ListTile(
          onTap: f,
          leading: Container(width: 46, height: 46, decoration: BoxDecoration(color: c.withValues(alpha: .13), borderRadius: BorderRadius.circular(14)), child: Icon(i, color: c)),
          title: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(s, style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_left_rounded),
        ),
      );

  @override
  Widget build(BuildContext context) {
    void go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w)).then((_) => _load());
    return Scaffold(
      appBar: AppBar(title: Text('شغل ال$role'), actions: [IconButton(onPressed: _profile, icon: const Icon(Icons.badge_outlined))]),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(gradient: C.grad, borderRadius: BorderRadius.circular(22)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name.isEmpty ? 'اكتب اسمك من زر الهوية فوق' : 'أهلاً يا $name', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _kpi('اللي بعته', fmtMoney(sold))),
              const SizedBox(width: 10),
              Expanded(child: _kpi('اللي حصّلته', fmtMoney(got))),
              const SizedBox(width: 10),
              Expanded(child: _kpi('سجلات', '$nNew')),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        if (role == 'مندوب') tile(Icons.add_shopping_cart_rounded, 'بيع جديد', 'سجّل عميل جديد وعقده', C.purple, () => go(const RepSaleForm())),
        tile(Icons.payments_rounded, 'تحصيل من عميل', 'سجّل اللي دفعه العميل', C.green, () => go(const RepCollectForm())),
        tile(Icons.people_alt_rounded, 'عملائي ($nBase)', 'العملاء اللي المالك بعتهم ليك والمتبقي عليهم', C.blue, () => go(const RepBaseScreen())),
        tile(Icons.list_alt_rounded, 'سجلاتي', 'كل اللي سجّلته وتعديله قبل الإرسال', C.orange, () => go(const RepEntriesScreen())),
        tile(Icons.smart_toy_rounded, 'الحريف', 'سجّل بالكلام: «حصّلت 500 من محمود»', C.pink, () => go(const HareefScreen(repMode: true))),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: nNew == 0 ? null : _export, icon: const Icon(Icons.send_rounded), label: const Text('خلّصت — تصدير وإرسال للمالك')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: _import, icon: const Icon(Icons.download_rounded), label: const Text('استيراد حزمة بيانات من المالك')),
      ]),
    );
  }

  Widget _kpi(String l, String v) => Container(
        padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .15), borderRadius: BorderRadius.circular(14)),
        child: Column(children: [Text(v, style: const TextStyle(color: C.gold, fontWeight: FontWeight.w900, fontSize: 18)), Text(l, style: const TextStyle(color: Colors.white70, fontSize: 11))]),
      );
}

class RepSaleForm extends StatefulWidget {
  const RepSaleForm({super.key});
  @override
  State<RepSaleForm> createState() => _SF();
}

class _SF extends State<RepSaleForm> {
  final name = TextEditingController(), phone = TextEditingController(), addr = TextEditingController(), region = TextEditingController(),
      item = TextEditingController(), total = TextEditingController(), down = TextEditingController(), months = TextEditingController(text: '12'),
      plan = TextEditingController();
  List<String> regions = [];
  List<Map<String, Object?>> prods = [];
  final lines = <SaleLine>[];
  bool totalTouched = false;
  GeoPt? geo;

  @override
  void initState() {
    super.initState();
    AppDb.i.getSetting('default_months').then((v) => months.text = v.isEmpty ? '12' : v);
    () async {
      regions = [for (final r in await AppDb.i.db.query('regions', orderBy: 'name')) r['name'].toString()];
      prods = await AppDb.i.db.query('products', orderBy: 'name');
      if (mounted) setState(() {});
    }();
  }

  Widget ac(String label, TextEditingController c, List<String> opts) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Autocomplete<String>(
          optionsBuilder: (t) => opts.where((o) => normAr(o).contains(normAr(t.text))),
          initialValue: TextEditingValue(text: c.text),
          onSelected: (v) => c.text = v,
          fieldViewBuilder: (_, ctl, fn, __) => TextField(controller: ctl, focusNode: fn, onChanged: (v) => c.text = v, decoration: InputDecoration(labelText: label)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = parseNumSafe(total.text), d = parseNumSafe(down.text), m = int.tryParse(trDigits(months.text)) ?? 0;
    final monthly = (m > 0 && t > d) ? (t - d) / m : 0.0;
    return Scaffold(
      appBar: AppBar(title: const Text('بيع جديد')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Field('اسم العميل', name), Field('الموبايل', phone, num: true), Field('العنوان', addr),
        LocationField(addr: addr, point: geo, onChanged: (p) => setState(() => geo = p)),
        ac('المنطقة', region, regions),
        ItemsEditor(
          products: prods, lines: lines, title: 'البضاعة (السعر بيظهر تلقائي)',
          onChanged: () => setState(() {
            if (lines.isNotEmpty && (!totalTouched || total.text.trim().isEmpty)) total.text = sumLines(lines) == sumLines(lines).truncate() ? '${sumLines(lines).truncate()}' : '${sumLines(lines)}';
            if (lines.isNotEmpty) item.text = itemsDesc([for (final l in lines) l.toMap()]);
          }),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: total, onChanged: (_) => setState(() => totalTouched = true), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'إجمالي البيع'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: down, onChanged: (_) => setState(() {}), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المقدم اللي استلمته'))),
        ]),
        const SizedBox(height: 10),
        TextField(controller: months, onChanged: (_) => setState(() {}), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'عدد الشهور')),
        const SizedBox(height: 10),
        Field('تقسيط متدرّج (اختياري)', plan, hint: '4×100 + 8×300'),
        Container(
          padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: C.purple.withValues(alpha: .1), borderRadius: BorderRadius.circular(14)),
          child: Text(plan.text.trim().isNotEmpty ? 'القسط بحسب الخطة المتدرّجة' : 'القسط الشهري: ${fmtMoney(monthly)} جنيه'),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.save_rounded), label: const Text('حفظ البيع'),
          onPressed: () => guard(context, () async {
            await AppDb.i.addRepSale(
              name: name.text, phone: phone.text, address: addr.text, region: region.text, item: item.text, total: parseNum(total.text), down: parseNum(down.text),
              months: parseNum(months.text).toInt(), plan: plan.text, lat: geo?.lat, lng: geo?.lng,
              items: [for (final l in lines) l.toMap()],
            );
            if (mounted) {
              toast(context, 'اتسجّل البيع');
              Navigator.pop(context);
            }
          }),
        ),
      ]),
    );
  }
}

class RepCollectForm extends StatefulWidget {
  const RepCollectForm({super.key, this.presetCode});
  final String? presetCode;
  @override
  State<RepCollectForm> createState() => _CF();
}

class _CF extends State<RepCollectForm> {
  final q = TextEditingController(), amt = TextEditingController(), notes = TextEditingController();
  List<Map<String, Object?>> found = [];
  Map<String, Object?>? sel;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    final base = await AppDb.i.repBaseSearch(q.text);
    // عقود النهارده اللي سجّلها المندوب (لسه ما اتبعتتش)
    final nq = normAr(q.text);
    final sales = (await AppDb.i.repEntries(onlyNew: true)).where((e) => e['kind'] == 'sale' && (nq.isEmpty || normAr('${e['name']}').contains(nq))).toList();
    final list = <Map<String, Object?>>[
      for (final s in sales) {'code': 'NEW:${s['uid']}', 'name': s['name'], 'phone': s['phone'], 'region': s['region'], 'remaining': null, 'monthly': null, 'next_due': 'عقد جديد'},
      ...base,
    ];
    if (!mounted) return;
    setState(() {
      found = list;
      if (widget.presetCode != null && sel == null) {
        final m = list.where((e) => e['code'] == widget.presetCode).toList();
        if (m.isNotEmpty) pick(m.first);
      }
    });
  }

  void pick(Map<String, Object?> c) {
    sel = c;
    final m = (c['due_amt'] is num && (c['due_amt'] as num) > 0) ? c['due_amt'] : c['monthly'];
    if (amt.text.isEmpty && m is num && m > 0) amt.text = m == m.truncate() ? '${m.truncate()}' : '$m';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('تحصيل من عميل')),
        body: ListView(padding: const EdgeInsets.all(14), children: [
          TextField(controller: q, onChanged: (_) => _search(), decoration: const InputDecoration(hintText: 'ابحث باسم العميل أو الكود أو الموبايل', prefixIcon: Icon(Icons.search))),
          const SizedBox(height: 10),
          if (sel != null)
            Card(
              color: C.green.withValues(alpha: .1),
              child: ListTile(
                title: Text('${sel!['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(sel!['remaining'] == null ? 'عقد جديد سجّلته النهارده' : 'المتبقي ${fmtMoney(sel!['remaining'] as num)} • القسط ${fmtMoney((sel!['monthly'] ?? 0) as num)} • ${sel!['region'] ?? ''}'),
                trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => sel = null)),
              ),
            )
          else
            for (final c in found.take(30))
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  onTap: () => setState(() => pick(c)),
                  title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${c['code']} • ${c['region'] ?? ''} • ${c['remaining'] == null ? 'عقد جديد' : 'متبقي ${fmtMoney(c['remaining'] as num)}'}${(c['due_amt'] is num && (c['due_amt'] as num) > 0) ? '\nمطلوب منه: ${fmtMoney(c['due_amt'] as num)}' : ''}'),
                  trailing: (c['arrears'] is num && (c['arrears'] as num) > 0) ? Pill('متأخر ${fmtMoney(c['arrears'] as num)}', C.red) : null,
                ),
              ),
          if (found.isEmpty && sel == null) const Empty('مفيش عملاء. استورد حزمة من المالك أو سجّل بيع جديد.'),
          if (sel != null) ...[
            const SizedBox(height: 12),
            Field('المبلغ اللي استلمته', amt, num: true),
            Field('ملاحظات', notes),
            FilledButton.icon(
              icon: const Icon(Icons.check_rounded), label: const Text('تسجيل التحصيل'),
              onPressed: () => guard(context, () async {
                final a = parseNum(amt.text);
                await AppDb.i.addRepCollect(custRef: sel!['code'].toString(), name: sel!['name'].toString(), phone: (sel!['phone'] ?? '').toString(), amount: a, notes: notes.text);
                if (!mounted) return;
                final phone = (sel!['phone'] ?? '').toString();
                final nm = sel!['name'];
                toast(context, 'اتسجّل ${fmtMoney(a)} جنيه من $nm');
                if (phone.isNotEmpty && await confirm(context, 'تبعت للعميل رسالة تأكيد على واتساب؟')) {
                  await openWhatsapp(phone, paymentThanksText(nm.toString(), a));
                }
                if (mounted) Navigator.pop(context);
              }),
            ),
          ],
        ]),
      );
}

class RepBaseScreen extends StatefulWidget {
  const RepBaseScreen({super.key});
  @override
  State<RepBaseScreen> createState() => _BS();
}

class _BS extends State<RepBaseScreen> {
  List<Map<String, Object?>> rows = [];
  String q = '';
  @override
  void initState() {
    super.initState();
    _l();
  }

  Future<void> _l() async {
    final r = await AppDb.i.repBaseSearch(q);
    if (mounted) setState(() => rows = r);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('عملائي (${rows.length})')),
        body: Column(children: [
          Padding(padding: const EdgeInsets.all(12), child: TextField(onChanged: (v) { q = v; _l(); }, decoration: const InputDecoration(hintText: 'بحث', prefixIcon: Icon(Icons.search)))),
          Expanded(
            child: rows.isEmpty
                ? const Empty('مفيش عملاء — استورد حزمة من المالك')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 20), itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      final ar = ((r['arrears'] ?? 0) as num).toDouble();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RepCollectForm(presetCode: r['code'].toString()))).then((_) => _l()),
                          title: Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${(r['due_amt'] is num && (r['due_amt'] as num) > 0) ? 'مطلوب منه ${fmtMoney(r['due_amt'] as num)}\n' : ''}${r['code']} • ${r['region']} • ${r['phone']}\nمتبقي ${fmtMoney(r['remaining'] as num)} • قسط ${fmtMoney((r['monthly'] ?? 0) as num)}${(r['next_due'] ?? '').toString().isEmpty ? '' : ' • الجاي ${r['next_due']}'}'),
                          isThreeLine: true,
                          trailing: ar > 0 ? Pill('متأخر ${fmtMoney(ar)}', C.red) : null,
                        ),
                      );
                    },
                  ),
          ),
        ]),
      );
}

class RepEntriesScreen extends StatefulWidget {
  const RepEntriesScreen({super.key});
  @override
  State<RepEntriesScreen> createState() => _ES();
}

class _ES extends State<RepEntriesScreen> {
  List<Map<String, Object?>> rows = [];
  @override
  void initState() {
    super.initState();
    _l();
  }

  Future<void> _l() async {
    final r = await AppDb.i.repEntries();
    if (mounted) setState(() => rows = r);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('سجلاتي (${rows.length})')),
        body: rows.isEmpty
            ? const Empty('مفيش سجلات')
            : ListView.builder(
                padding: const EdgeInsets.all(12), itemCount: rows.length,
                itemBuilder: (_, i) {
                  final r = rows[i];
                  final sale = r['kind'] == 'sale';
                  final sent = r['exported'] == 1;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: (sale ? C.purple : C.green).withValues(alpha: .15), child: Icon(sale ? Icons.shopping_bag_rounded : Icons.payments_rounded, color: sale ? C.purple : C.green)),
                      title: Text(RepEntry.fromRow(r).title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${r['ts']}${sale ? ' • مقدم ${fmtMoney(r['down'] as num)} • ${r['months']} شهر' : ''}'),
                      trailing: sent
                          ? const Pill('اتبعت', C.blue)
                          : IconButton(
                              icon: const Icon(Icons.delete_outline, color: C.red),
                              onPressed: () async {
                                if (await confirm(context, 'تحذف السجل ده؟')) {
                                  await AppDb.i.deleteRepEntry(r['uid'].toString());
                                  _l();
                                }
                              }),
                    ),
                  );
                },
              ),
      );
}
