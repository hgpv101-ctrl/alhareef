import 'package:flutter/material.dart';
import '../core/utils.dart';
import '../data/db.dart';
import '../theme.dart';
import 'widgets.dart';

class FieldDef {
  const FieldDef(this.col, this.label, {this.num = false, this.options, this.initial});
  final String col, label;
  final bool num;
  final List<String>? options;
  final String? initial;
}

/// شاشة CRUD عامة لأي جدول بسيط (مناطق، منتجات، مناديب، مصروفات...)
class CrudScreen extends StatefulWidget {
  const CrudScreen({super.key, required this.title, required this.table, required this.fields, required this.titleOf,
      this.subOf, this.where, this.args, this.order = 'id DESC', this.defaults = const {}, this.codeLetter, this.gate = true, this.extra});
  final String title, table, order;
  final List<FieldDef> fields;
  final String Function(Map<String, Object?>) titleOf;
  final String Function(Map<String, Object?>)? subOf;
  final String? where;
  final List<Object?>? args;
  final Map<String, Object?> defaults;
  final String? codeLetter;
  final bool gate;
  final Widget Function(Map<String, Object?>, VoidCallback reload)? extra;
  @override
  State<CrudScreen> createState() => _S();
}

class _S extends State<CrudScreen> {
  List<Map<String, Object?>> rows = [];
  String q = '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await AppDb.i.db.query(widget.table, where: widget.where, whereArgs: widget.args, orderBy: widget.order);
    if (mounted) setState(() => rows = r);
  }

  Future<void> _edit([Map<String, Object?>? row]) async {
    if (row != null && widget.gate && !await adminGate(context)) return;
    final ctl = {for (final f in widget.fields) f.col: TextEditingController(text: (row?[f.col] ?? f.initial ?? '').toString())};
    if (!mounted) return;
    final ok = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(row == null ? 'إضافة' : 'تعديل', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 12),
            for (final f in widget.fields)
              f.options != null
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DropdownButtonFormField<String>(
                        value: f.options!.contains(ctl[f.col]!.text) ? ctl[f.col]!.text : null,
                        decoration: InputDecoration(labelText: f.label),
                        items: [for (final o in f.options!) DropdownMenuItem(value: o, child: Text(o))],
                        onChanged: (v) => ctl[f.col]!.text = v ?? '',
                      ))
                  : Field(f.label, ctl[f.col]!, num: f.num),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ'))),
          ]),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await guard(context, () async {
      final data = <String, Object?>{...widget.defaults};
      for (final f in widget.fields) {
        final t = ctl[f.col]!.text.trim();
        data[f.col] = f.num ? parseNum(t) : t;
      }
      if (widget.fields.first.col.isNotEmpty && (data[widget.fields.first.col] ?? '').toString().isEmpty) {
        throw FormatException('اكتب ${widget.fields.first.label}');
      }
      if (row == null) {
        if (widget.codeLetter != null) data['code'] = await AppDb.i.nextCode(widget.codeLetter!, widget.table, 'code');
        await AppDb.i.db.insert(widget.table, data);
        await AppDb.i.log('إضافة ${widget.title}', widget.titleOf(data));
      } else {
        await AppDb.i.db.update(widget.table, data, where: 'id=?', whereArgs: [row['id']]);
        await AppDb.i.log('تعديل ${widget.title}', widget.titleOf(data));
      }
      await _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final nq = normAr(q);
    final list = rows.where((r) => nq.isEmpty || normAr(r.values.join(' ')).contains(nq)).toList();
    return Scaffold(
      appBar: AppBar(title: Text('${widget.title} (${rows.length})')),
      floatingActionButton: FloatingActionButton(onPressed: () => _edit(), child: const Icon(Icons.add)),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(onChanged: (v) => setState(() => q = v), decoration: const InputDecoration(hintText: 'بحث', prefixIcon: Icon(Icons.search)))),
        Expanded(
          child: list.isEmpty
              ? const Empty('مفيش بيانات')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final r = list[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        onTap: () => _edit(r),
                        title: Text(widget.titleOf(r), style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: widget.subOf == null ? null : Text(widget.subOf!(r)),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (widget.extra != null) widget.extra!(r, _load),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: C.red),
                            onPressed: () async {
                              if (await confirm(context, 'تحذف "${widget.titleOf(r)}"؟') && mounted && (!widget.gate || await adminGate(context))) {
                                await AppDb.i.db.delete(widget.table, where: 'id=?', whereArgs: [r['id']]);
                                await AppDb.i.log('حذف ${widget.title}', widget.titleOf(r));
                                _load();
                              }
                            },
                          ),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

String _n(Object? v) => fmtMoney((v ?? 0) as num);

Widget crudRegions() => CrudScreen(title: 'المناطق', table: 'regions', order: 'name', fields: const [FieldDef('name', 'المنطقة'), FieldDef('sub_name', 'القرية / المنطقة الفرعية')],
    titleOf: (r) => '${r['name']}', subOf: (r) => '${r['sub_name'] ?? ''}');

Widget crudProducts() => CrudScreen(
      title: 'الأصناف', table: 'products', order: 'name', codeLetter: 'P',
      fields: const [FieldDef('name', 'اسم الصنف'), FieldDef('category', 'التصنيف'), FieldDef('buy_price', 'سعر الشراء', num: true),
        FieldDef('sell_price', 'سعر البيع', num: true), FieldDef('rep_comm', 'عمولة المندوب (جنيه للقطعة)', num: true), FieldDef('min_qty', 'حد النواقص', num: true, initial: '3'),
        FieldDef('qty', 'الكمية الحالية', num: true, initial: '0'), FieldDef('barcode', 'باركود')],
      titleOf: (r) => '${r['code'] ?? ''}  ${r['name']}', subOf: (r) => 'رصيد ${r['qty'] ?? 0}  •  بيع ${_n(r['sell_price'])}');

Widget crudReps() => CrudScreen(
      title: 'الفريق', table: 'representatives', order: 'type, name', codeLetter: 'R',
      fields: const [FieldDef('name', 'الاسم'), FieldDef('type', 'الوظيفة', options: ['المناديب', 'المحصلين', 'أمناء المخازن']),
        FieldDef('phone', 'الموبايل', num: false), FieldDef('coll_comm', 'عمولة المحصّل (جنيه عن كل 1000 جنيه يحصّلها)', num: true), FieldDef('notes', 'ملاحظات')],
      titleOf: (r) => '${r['name']}', subOf: (r) => '${r['type']}  •  ${r['phone'] ?? ''}');

Widget crudCustody() => CrudScreen(
      title: 'العهدة', table: 'custody', defaults: {'status': custodyOpen},
      fields: [const FieldDef('rep_name', 'المندوب'), const FieldDef('item_name', 'الصنف'), const FieldDef('qty', 'الكمية', num: true),
        FieldDef('date_given', 'التاريخ', initial: isoDate(today())), const FieldDef('status', 'الحالة', options: [custodyOpen, custodyReturned, custodySold])],
      titleOf: (r) => '${r['item_name']} × ${r['qty']}', subOf: (r) => '${r['rep_name']}  •  ${r['date_given']}  •  ${r['status']}');

Widget crudSuppliers() => CrudScreen(
      title: 'الموردين', table: 'suppliers', order: 'name', codeLetter: 'S',
      fields: const [FieldDef('name', 'اسم المورد'), FieldDef('phone', 'الموبايل'), FieldDef('address', 'العنوان'), FieldDef('activity', 'النشاط'), FieldDef('notes', 'ملاحظات')],
      titleOf: (r) => '${r['name']}', subOf: (r) => '${r['phone'] ?? ''}  •  ${r['activity'] ?? ''}');

Widget crudExpenses() => CrudScreen(
      title: 'المصروفات', table: 'expenses',
      fields: [const FieldDef('item_name', 'البند'), const FieldDef('amount', 'المبلغ', num: true), FieldDef('exp_date', 'التاريخ', initial: isoDate(today())), const FieldDef('notes', 'ملاحظات')],
      titleOf: (r) => '${r['item_name']} — ${_n(r['amount'])}', subOf: (r) => '${r['exp_date']}  •  ${r['notes'] ?? ''}');

Widget crudPartners() => CrudScreen(
      title: 'المساهمين', table: 'partners', codeLetter: 'M',
      fields: const [FieldDef('name', 'الاسم'), FieldDef('capital', 'رأس المال', num: true), FieldDef('share_percent', 'النسبة %', num: true), FieldDef('phone', 'الموبايل'), FieldDef('notes', 'ملاحظات')],
      titleOf: (r) => '${r['name']}', subOf: (r) => 'رأس المال ${_n(r['capital'])}  •  نسبة ${r['share_percent']}%');
