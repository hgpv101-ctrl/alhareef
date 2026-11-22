// قسم المخزن: الأصناف + استلام بضاعة + متابعة + حركات — وكله مربوط بالعملاء والعهدة والمندوبين
import 'package:flutter/material.dart';
import '../core/utils.dart';
import '../data/db.dart';
import '../data/ops.dart';
import '../data/stock.dart';
import '../theme.dart';
import 'customers.dart' show CustomerDetail;
import 'items_editor.dart';
import 'widgets.dart';

class StockHome extends StatefulWidget {
  const StockHome({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  State<StockHome> createState() => _SH();
}

class _SH extends State<StockHome> {
  int rev = 0;
  void bump() => setState(() => rev++);

  Future<void> _receive() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ReceiveScreen()));
    bump();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 4, initialIndex: widget.initialTab,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('المخزن'),
            actions: [IconButton(tooltip: 'استلام بضاعة', onPressed: _receive, icon: const Icon(Icons.move_to_inbox_rounded))],
            bottom: const TabBar(
              isScrollable: true, tabAlignment: TabAlignment.center, indicatorColor: C.gold, labelColor: Colors.white, unselectedLabelColor: Colors.white60,
              tabs: [Tab(text: 'الأصناف'), Tab(text: 'المتابعة'), Tab(text: 'الحركات'), Tab(text: 'العهدة')],
            ),
          ),
          body: TabBarView(children: [
            _ProductsTab(key: ValueKey('p$rev'), onChanged: bump),
            _FollowTab(key: ValueKey('f$rev')),
            _MovesTab(key: ValueKey('m$rev')),
            _CustodyTab(key: ValueKey('c$rev')),
          ]),
        ),
      );
}

// ============================================================ الأصناف
class _ProductsTab extends StatefulWidget {
  const _ProductsTab({super.key, required this.onChanged});
  final VoidCallback onChanged;
  @override
  State<_ProductsTab> createState() => _PT();
}

class _PT extends State<_ProductsTab> {
  List<ProdStat> rows = [];
  String q = '', filter = 'الكل';
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await AppDb.i.stockStats();
    if (mounted) setState(() { rows = r; loaded = true; });
  }

  Future<void> _new() async {
    if (await showProductForm(context) == true) {
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final nq = normAr(q).trim();
    final list = rows.where((s) {
      if (filter == 'نواقص' && !(s.low && !s.out)) return false;
      if (filter == 'نفد' && !s.out) return false;
      return nq.isEmpty || normAr('${s.name} ${s.code} ${s.row['category']} ${s.row['barcode']}').contains(nq);
    }).toList();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        FloatingActionButton.extended(
          heroTag: 'recv', backgroundColor: C.green, foregroundColor: Colors.white,
          onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const ReceiveScreen()));
            widget.onChanged();
          },
          icon: const Icon(Icons.move_to_inbox_rounded), label: const Text('استلام بضاعة'),
        ),
        const SizedBox(height: 10),
        FloatingActionButton.extended(heroTag: 'newp', onPressed: _new, icon: const Icon(Icons.add), label: const Text('صنف جديد بسعره')),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(onChanged: (v) => setState(() => q = v), decoration: const InputDecoration(hintText: 'بحث بالاسم أو الكود أو الباركود', prefixIcon: Icon(Icons.search))),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final f in const ['الكل', 'نواقص', 'نفد'])
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ChoiceChip(label: Text(f), selected: filter == f, onSelected: (_) => setState(() => filter = f)),
              ),
          ]),
        ),
        Expanded(
          child: !loaded
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? Empty(rows.isEmpty ? 'مفيش أصناف لسه.\nدوس «صنف جديد بسعره» وسجّل الصنف بسعر الشراء والبيع والرصيد، أو «استلام بضاعة» لما توصلك بضاعة جديدة.' : 'مفيش نتايج')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 90), itemCount: list.length,
                      itemBuilder: (_, i) {
                        final s = list[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            onTap: () async {
                              await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetail(id: s.id)));
                              widget.onChanged();
                            },
                            title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text('${s.code} • بيع ${fmtMoney(s.sell)} • شراء ${fmtMoney(s.buy)}${s.inCustody > 0 ? '\nفي عهدة المناديب: ${s.inCustody}' : ''}'),
                            isThreeLine: s.inCustody > 0,
                            trailing: Pill('${s.qty}', s.out ? C.red : (s.low ? C.orange : C.green)),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

/// نموذج إضافة/تعديل صنف. بيرجّع true لو اتحفظ.
Future<bool?> showProductForm(BuildContext context, {Map<String, Object?>? row}) async {
  if (row != null && !await adminGate(context)) return null;
  if (!context.mounted) return null;
  String t(String k, [String d = '']) => (row?[k] ?? d).toString();
  String n(String k, [String d = '']) {
    final v = row?[k];
    if (v == null) return d;
    final x = (v as num).toDouble();
    return x == x.truncate() ? '${x.truncate()}' : '$x';
  }

  final name = TextEditingController(text: t('name')), cat = TextEditingController(text: t('category')),
      buy = TextEditingController(text: n('buy_price')), sell = TextEditingController(text: n('sell_price')),
      ratio = TextEditingController(text: n('rep_comm')), minq = TextEditingController(text: n('min_qty', '3')),
      enName = TextEditingController(text: t('en_name')), barcode = TextEditingController(text: t('barcode')), open = TextEditingController(text: '0');
  String? err;
  return showModalBottomSheet<bool>(
    context: context, isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(row == null ? 'صنف جديد' : 'تعديل ${t('name')}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 12),
            Field('اسم الصنف', name),
            Field('اسم الصنف بالإنجليزي (للإيصال الإنجليزي — اختياري)', enName),
            Field('التصنيف', cat),
            Row(children: [
              Expanded(child: Field('سعر الشراء', buy, num: true)),
              const SizedBox(width: 8),
              Expanded(child: Field('سعر البيع', sell, num: true)),
            ]),
            Row(children: [
              Expanded(child: Field('حد النواقص', minq, num: true)),
              const SizedBox(width: 8),
              Expanded(child: Field('عمولة المندوب (جنيه للقطعة)', ratio, num: true)),
            ]),
            Field('باركود (اختياري)', barcode),
            if (row == null) Field('الرصيد الافتتاحي (اللي في المخزن دلوقتي)', open, num: true),
            if (row != null) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('الرصيد بيتغيّر من الوارد / الصادر / الجرد عشان الحركات تفضل مسجّلة.', style: TextStyle(color: Colors.grey, fontSize: 12))),
            if (err != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(err!, style: const TextStyle(color: C.red, fontWeight: FontWeight.w700))),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  try {
                    double d(TextEditingController c) => c.text.trim().isEmpty ? 0 : parseNum(c.text);
                    await AppDb.i.saveProduct(
                      id: row == null ? null : (row['id'] as num).toInt(), name: name.text, category: cat.text, buy: d(buy), sell: d(sell),
                      repComm: d(ratio), minQty: d(minq).toInt(), barcode: barcode.text, enName: enName.text, openingQty: row == null ? d(open).toInt() : 0,
                    );
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
}

// ============================================================ تفاصيل صنف
class ProductDetail extends StatefulWidget {
  const ProductDetail({super.key, required this.id});
  final int id;
  @override
  State<ProductDetail> createState() => _PD();
}

class _PD extends State<ProductDetail> {
  Map<String, Object?>? p;
  ProdStat? st;
  List<Map<String, Object?>> moves = [], buyers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = AppDb.i;
    final r = await db.db.query('products', where: 'id=?', whereArgs: [widget.id]);
    final all = await db.stockStats();
    final m = await db.productMoves(widget.id);
    final b = await db.productBuyers(widget.id);
    if (!mounted) return;
    setState(() {
      p = r.isEmpty ? null : r.first;
      st = all.where((s) => s.id == widget.id).isEmpty ? null : all.firstWhere((s) => s.id == widget.id);
      moves = m;
      buyers = b;
    });
  }

  Future<void> _adjust(String kind) async {
    final q = TextEditingController(), notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('$kind — ${p!['name']} (رصيد ${p!['qty']})'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Field(kind == 'جرد' ? 'الرصيد الفعلي (اللي عدّيته)' : 'الكمية', q, num: true),
          Field(kind == 'تالف' ? 'سبب التلف' : 'ملاحظات (اختياري)', notes),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تنفيذ'))],
      ),
    );
    if (ok != true || !mounted) return;
    await guard(context, () async {
      await AppDb.i.adjustStock(widget.id, kind, parseNum(q.text).toInt(), notes: notes.text.trim());
      await _load();
    }, ok: 'اتسجلت الحركة');
  }

  @override
  Widget build(BuildContext context) {
    final s = st;
    if (p == null || s == null) return Scaffold(appBar: AppBar(), body: const Empty('الصنف مش موجود'));
    Widget kv(String a, String b, {Color? c}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(a, style: const TextStyle(color: Colors.grey)), Text(b, style: TextStyle(fontWeight: FontWeight.w700, color: c))]),
        );
    return Scaffold(
      appBar: AppBar(title: Text(s.name), actions: [
        IconButton(
          icon: const Icon(Icons.edit_rounded),
          onPressed: () async {
            if (await showProductForm(context, row: p) == true) _load();
          },
        ),
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'del' && await confirm(context, 'تحذف الصنف ${s.name}؟') && mounted && await adminGate(context)) {
              await guard(context, () async {
                await AppDb.i.deleteProduct(widget.id);
                if (mounted) Navigator.pop(context);
              });
            }
          },
          itemBuilder: (_) => const [PopupMenuItem(value: 'del', child: Text('حذف الصنف'))],
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(children: [
                Expanded(child: Text('${s.qty}', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: s.out ? C.red : (s.low ? C.orange : C.green)))),
                if (s.out) const Pill('نفد', C.red) else if (s.low) const Pill('ناقص', C.orange) else const Pill('متوفر', C.green),
              ]),
              const Divider(),
              kv('الكود', s.code),
              if ((p!['category'] ?? '').toString().isNotEmpty) kv('التصنيف', '${p!['category']}'),
              kv('سعر البيع', fmtMoney(s.sell), c: C.purple),
              kv('سعر الشراء', fmtMoney(s.buy)),
              if (s.sell > 0 && s.buy > 0) kv('هامش الربح للقطعة', fmtMoney(s.sell - s.buy), c: s.sell >= s.buy ? C.green : C.red),
              kv('قيمة الرصيد (شراء)', fmtMoney(s.qty > 0 ? s.qty * s.buy : 0)),
              kv('حد النواقص', '${s.minQty}'),
              kv('اتباع (آخر 30 يوم)', '${s.sold30}'),
              kv('إجمالي المباع', '${s.soldAll}'),
              if (s.inCustody > 0) kv('في عهدة المناديب', '${s.inCustody}', c: C.purple),
              if (s.daysCover != null) kv('الرصيد يكفي تقريباً', '${s.daysCover!.floor()} يوم'),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in const [('وارد', Icons.add_box_rounded), ('صادر', Icons.outbox_rounded), ('جرد', Icons.fact_check_rounded), ('تالف', Icons.heart_broken_rounded)])
            OutlinedButton.icon(onPressed: () => _adjust(k.$1), icon: Icon(k.$2), label: Text(k.$1)),
        ]),
        const Padding(padding: EdgeInsets.fromLTRB(4, 16, 4, 6), child: Text('اتباع لمين', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        if (buyers.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('لسه ما اتباعش لعملاء من خلال العقود.', style: TextStyle(color: Colors.grey))),
        for (final b in buyers.take(30))
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetail(code: b['customer_code'].toString()))).then((_) => _load()),
              title: Text('${b['customer_name'] ?? b['customer_code']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${b['sold_at'] ?? ''} • ${b['customer_code']}${(b['rep_name'] ?? '').toString().isEmpty ? '' : ' • مندوب ${b['rep_name']}'}'),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${(b['qty'] as num).toInt() - (b['returned_qty'] as num).toInt()} × ${fmtMoney((b['unit_price'] ?? 0) as num)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                if (((b['returned_qty'] ?? 0) as num) > 0) Text('مرتجع ${b['returned_qty']}', style: const TextStyle(color: C.orange, fontSize: 11)),
              ]),
            ),
          ),
        const Padding(padding: EdgeInsets.fromLTRB(4, 16, 4, 6), child: Text('آخر الحركات', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        if (moves.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('مفيش حركات.', style: TextStyle(color: Colors.grey))),
        for (final m in moves) _moveCard(m, showName: false),
      ]),
    );
  }
}

Widget _moveCard(Map<String, Object?> m, {bool showName = true}) {
  final q = (m['qty'] as num).toInt();
  return Card(
    margin: const EdgeInsets.only(bottom: 6),
    child: ListTile(
      dense: true,
      title: Text(showName ? '${m['product_name']}' : '${m['kind']}', style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${m['move_date']}${showName ? ' • ${m['kind']}' : ''}${(m['ref'] ?? '').toString().isEmpty ? '' : ' • ${m['ref']}'}${(m['notes'] ?? '').toString().isEmpty ? '' : '\n${m['notes']}'}'),
      trailing: Text('${q > 0 ? '+' : ''}$q  (رصيد ${m['balance_after']})', style: TextStyle(color: q > 0 ? C.green : (q < 0 ? C.red : Colors.grey), fontWeight: FontWeight.w800)),
    ),
  );
}

// ============================================================ استلام بضاعة
class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});
  @override
  State<ReceiveScreen> createState() => _RS();
}

class _RS extends State<ReceiveScreen> {
  List<Map<String, Object?>> prods = [];
  List<String> suppliers = [];
  final lines = <SaleLine>[];
  final supplier = TextEditingController(), paid = TextEditingController(), notes = TextEditingController();
  bool invoice = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await AppDb.i.db.query('products', orderBy: 'name');
    final s = [for (final r in await AppDb.i.db.query('suppliers', orderBy: 'name')) r['name'].toString()];
    if (mounted) setState(() { prods = p; suppliers = s; });
  }

  @override
  Widget build(BuildContext context) {
    final total = sumLines(lines);
    return Scaffold(
      appBar: AppBar(title: const Text('استلام بضاعة')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Autocomplete<String>(
          optionsBuilder: (t) => suppliers.where((o) => normAr(o).contains(normAr(t.text))),
          onSelected: (v) => supplier.text = v,
          fieldViewBuilder: (_, ctl, fn, __) => TextField(controller: ctl, focusNode: fn, onChanged: (v) => setState(() => supplier.text = v), decoration: const InputDecoration(labelText: 'المورد (اختياري)')),
        ),
        const SizedBox(height: 12),
        ItemsEditor(
          products: prods, lines: lines, title: 'الأصناف المستلمة (سعر الشراء)', priceKey: 'buy_price', showStock: false, allowManual: false,
          onChanged: () => setState(() {}),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: OutlinedButton.icon(
            onPressed: () async {
              if (await showProductForm(context) == true) _load();
            },
            icon: const Icon(Icons.new_label_rounded),
            label: const Text('بضاعة جديدة مش متسجلة؟ سجّل الصنف وسعره الأول'),
          ),
        ),
        const SizedBox(height: 6),
        Field('ملاحظات', notes),
        SwitchListTile(
          value: invoice, onChanged: (v) => setState(() => invoice = v), contentPadding: EdgeInsets.zero,
          title: const Text('سجّل فاتورة للمورد'), subtitle: const Text('بتتحسب من أسعار الشراء وبتظهر في فواتير الموردين'),
        ),
        if (invoice) Field('المدفوع للمورد دلوقتي (0 لو لسه)', paid, num: true),
        if (invoice && total > 0) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('إجمالي الفاتورة ${fmtMoney(total)}', style: const TextStyle(fontWeight: FontWeight.w800, color: C.purple))),
        FilledButton.icon(
          icon: const Icon(Icons.check_rounded), label: const Text('تسجيل الاستلام'),
          onPressed: () => guard(context, () async {
            if (lines.any((l) => l.pid == null)) throw const FormatException('اختار الأصناف من المخزن.');
            await AppDb.i.receiveStock(
              [for (final l in lines) {'pid': l.pid, 'qty': l.qty, 'price': l.price}],
              supplier: supplier.text, paid: paid.text.trim().isEmpty ? 0 : parseNum(paid.text), invoice: invoice, notes: notes.text.trim(),
            );
            if (mounted) {
              toast(context, 'اتضافت البضاعة للمخزن');
              Navigator.pop(context);
            }
          }),
        ),
      ]),
    );
  }
}

// ============================================================ المتابعة
class _FollowTab extends StatefulWidget {
  const _FollowTab({super.key});
  @override
  State<_FollowTab> createState() => _FT();
}

class _FT extends State<_FollowTab> {
  List<ProdStat> st = [];
  Map<String, num> sum = {};
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    () async {
      final a = await AppDb.i.stockStats();
      final b = await AppDb.i.stockSummary();
      if (mounted) setState(() { st = a; sum = b; loaded = true; });
    }();
  }

  Widget _kpi(String l, String v, Color c) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(16)),
          child: Column(children: [Text(v, style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 16)), const SizedBox(height: 2), Text(l, style: const TextStyle(fontSize: 11), textAlign: TextAlign.center)]),
        ),
      );

  Widget _sec(String title, List<ProdStat> list, String Function(ProdStat) trail, Color c, {String emptyText = 'مفيش'}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(4, 16, 4, 6), child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
        if (list.isEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(emptyText, style: const TextStyle(color: Colors.grey))),
        for (final s in list.take(12))
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetail(id: s.id))),
              title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: Pill(trail(s), c),
            ),
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    final low = st.where((s) => s.low).toList()..sort((a, b) => a.qty.compareTo(b.qty));
    final top = st.where((s) => s.sold30 > 0).toList()..sort((a, b) => b.sold30.compareTo(a.sold30));
    final slow = st.where((s) => s.slow).toList()..sort((a, b) => (b.qty * b.buy).compareTo(a.qty * a.buy));
    final soon = st.where((s) => s.daysCover != null && s.daysCover! < 15 && s.qty > 0).toList()..sort((a, b) => a.daysCover!.compareTo(b.daysCover!));
    return ListView(padding: const EdgeInsets.all(14), children: [
      Row(children: [
        _kpi('أصناف', '${sum['count']}', C.blue), const SizedBox(width: 8),
        _kpi('ناقص', '${sum['low']}', C.orange), const SizedBox(width: 8),
        _kpi('نفد', '${sum['out']}', C.red), const SizedBox(width: 8),
        _kpi('في العهدة', '${sum['custody']}', C.purple),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        _kpi('قيمة المخزن (شراء)', fmtMoney(sum['buyVal']), C.green), const SizedBox(width: 8),
        _kpi('قيمته بسعر البيع', fmtMoney(sum['sellVal']), C.navy),
      ]),
      _sec('🔴 نواقص ونفد — محتاجة طلب', low, (s) => '${s.qty} / ${s.minQty}', C.red, emptyText: 'كل الأصناف رصيدها تمام ✅'),
      _sec('⏳ هتخلص قريب (أقل من 15 يوم)', soon, (s) => '${s.daysCover!.floor()} يوم', C.orange, emptyText: 'مفيش'),
      _sec('🔥 الأكتر مبيعاً (آخر 30 يوم)', top, (s) => '${s.sold30} قطعة', C.green, emptyText: 'لسه مفيش مبيعات مربوطة بالأصناف'),
      _sec('🐌 راكد (ما اتباعش من 60 يوم)', slow, (s) => '${s.qty} قطعة', C.purple, emptyText: 'مفيش بضاعة راكدة 🎉'),
    ]);
  }
}

// ============================================================ الحركات
class _MovesTab extends StatefulWidget {
  const _MovesTab({super.key});
  @override
  State<_MovesTab> createState() => _MT();
}

class _MT extends State<_MovesTab> {
  List<Map<String, Object?>> rows = [];
  String kind = 'الكل';
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await AppDb.i.db.query('stock_moves', where: kind == 'الكل' ? null : 'kind LIKE ?', whereArgs: kind == 'الكل' ? null : ['%$kind%'], orderBy: 'id DESC', limit: 300);
    if (mounted) setState(() { rows = r; loaded = true; });
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), children: [
            for (final k in const ['الكل', 'وارد', 'بيع', 'عهدة', 'مرتجع', 'تالف', 'جرد'])
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ChoiceChip(label: Text(k), selected: kind == k, onSelected: (_) { kind = k; _load(); }),
              ),
          ]),
        ),
        Expanded(
          child: !loaded
              ? const Center(child: CircularProgressIndicator())
              : rows.isEmpty ? const Empty('مفيش حركات') : ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 20), children: [for (final m in rows) _moveCard(m)]),
        ),
      ]);
}

// ============================================================ العهدة (بضاعة المناديب)
class _CustodyTab extends StatefulWidget {
  const _CustodyTab({super.key});
  @override
  State<_CustodyTab> createState() => _CT();
}

class _CT extends State<_CustodyTab> {
  List<Map<String, Object?>> rows = [];
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await AppDb.i.openCustody();
    if (mounted) setState(() { rows = r; loaded = true; });
  }

  Future<void> _give() async {
    final prods = await AppDb.i.db.query('products', orderBy: 'name');
    final reps = await AppDb.i.namesOf('المناديب');
    if (!mounted) return;
    String? rep;
    final lines = <SaleLine>[];
    String? err;
    final ok = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('تسليم عهدة لمندوب', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                isExpanded: true, decoration: const InputDecoration(labelText: 'المندوب'),
                items: [for (final r in reps) DropdownMenuItem(value: r, child: Text(r))], onChanged: (v) => rep = v,
              ),
              const SizedBox(height: 10),
              ItemsEditor(products: prods, lines: lines, title: 'البضاعة', showStock: true, allowManual: false, onChanged: () => set(() {})),
              if (err != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(err!, style: const TextStyle(color: C.red, fontWeight: FontWeight.w700))),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    try {
                      if (rep == null) throw const FormatException('اختار المندوب.');
                      if (lines.isEmpty) throw const FormatException('ضيف صنف واحد على الأقل.');
                      await AppDb.i.giveCustodyMulti(rep!, [for (final l in lines) (l.name, l.qty)]);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      set(() => err = errText(e));
                    }
                  },
                  child: const Text('تسليم'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final byRep = <String, List<Map<String, Object?>>>{};
    for (final r in rows) {
      byRep.putIfAbsent((r['rep_name'] ?? '').toString(), () => []).add(r);
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(onPressed: _give, icon: const Icon(Icons.local_shipping_rounded), label: const Text('تسليم عهدة')),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
              ? const Empty('مفيش عهدة مفتوحة عند المناديب')
              : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
                  for (final e in byRep.entries)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('🚚 ${e.key}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          const Divider(),
                          for (final r in e.value)
                            Row(children: [
                              Expanded(child: Text('${r['item_name']}')),
                              Text('× ${r['qty']}', style: const TextStyle(fontWeight: FontWeight.w800, color: C.purple)),
                              IconButton(
                                visualDensity: VisualDensity.compact, tooltip: 'إرجاع للمخزن',
                                icon: const Icon(Icons.undo_rounded, color: C.orange, size: 20),
                                onPressed: () async {
                                  if (await confirm(context, 'ترجّع ${r['qty']} × ${r['item_name']} للمخزن؟') && mounted && await adminGate(context)) {
                                    await guard(context, () async {
                                      await AppDb.i.returnCustody((r['id'] as num).toInt());
                                      await _load();
                                    }, ok: 'اترجعت للمخزن');
                                  }
                                },
                              ),
                            ]),
                        ]),
                      ),
                    ),
                ]),
    );
  }
}
