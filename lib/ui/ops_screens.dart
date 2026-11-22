import 'package:flutter/material.dart';
import '../core/security.dart';
import '../core/utils.dart';
import '../data/db.dart';
import '../data/ops.dart';
import '../theme.dart';
import 'customers.dart' show parseNumSafe;
import 'widgets.dart';

class Q {
  Q(this.key, this.label, {this.num = false, this.options, this.init = ''});
  final String key, label, init;
  final bool num;
  final List<String>? options; // لو موجودة: قايمة اختيار
}

/// نموذج صغير بيرجّع Map أو null
Future<Map<String, String>?> askForm(BuildContext c, String title, List<Q> qs) async {
  final ctl = {for (final q in qs) q.key: TextEditingController(text: q.init)};
  final ok = await showModalBottomSheet<bool>(
    context: c, isScrollControlled: true,
    builder: (_) => Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(c).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 12),
          for (final q in qs)
            q.options != null
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: q.options!.contains(q.init) ? q.init : null,
                      decoration: InputDecoration(labelText: q.label),
                      items: [for (final o in q.options!) DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis))],
                      onChanged: (v) => ctl[q.key]!.text = v ?? '',
                    ))
                : Field(q.label, ctl[q.key]!, num: q.num),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ'))),
        ]),
      ),
    ),
  );
  if (ok != true) return null;
  return {for (final e in ctl.entries) e.key: e.value.text.trim()};
}

Future<List<String>> _custOptions() async =>
    [for (final r in await AppDb.i.db.query('customers', columns: ['customer_code', 'name'], orderBy: 'name')) '${r['customer_code']} — ${r['name']}'];
Future<List<String>> _prodOptions() async =>
    [for (final r in await AppDb.i.db.query('products', columns: ['id', 'name'], orderBy: 'name')) '${r['id']} — ${r['name']}'];
String _code(String s) => s.split(' — ').first.trim();
int _pid(String s) => int.tryParse(_code(s)) ?? 0;

class _Shell extends StatefulWidget {
  const _Shell({required this.title, required this.load, required this.tile, required this.onAdd, this.gate = true, this.extraActions = const []});
  final String title;
  final Future<List<Map<String, Object?>>> Function() load;
  final Widget Function(BuildContext, Map<String, Object?>, VoidCallback) tile;
  final Future<void> Function(BuildContext) onAdd;
  final bool gate;
  final List<Widget> extraActions;
  @override
  State<_Shell> createState() => _ShellS();
}

class _ShellS extends State<_Shell> {
  List<Map<String, Object?>> rows = [];
  @override
  void initState() {
    super.initState();
    _l();
  }

  Future<void> _l() async {
    final r = await widget.load();
    if (mounted) setState(() => rows = r);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('${widget.title} (${rows.length})'), actions: widget.extraActions),
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            if (widget.gate && !await adminGate(context)) return;
            if (!context.mounted) return;
            await guard(context, () async {
              await widget.onAdd(context);
              await _l();
            });
          },
          child: const Icon(Icons.add),
        ),
        body: rows.isEmpty
            ? const Empty('مفيش بيانات لسه')
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), itemCount: rows.length,
                itemBuilder: (c, i) => Card(margin: const EdgeInsets.only(bottom: 8), child: widget.tile(c, rows[i], _l)),
              ),
      );
}

String _n(Object? v) => fmtMoney((v ?? 0) as num);

class ReturnsScreen extends StatelessWidget {
  const ReturnsScreen({super.key});
  @override
  Widget build(BuildContext context) => _Shell(
        title: 'المرتجعات',
        load: () => AppDb.i.db.query('returns_log', orderBy: 'id DESC'),
        tile: (c, r, _) => ListTile(
          title: Text('${r['product_name']} × ${r['qty']} — ${_n(r['amount'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${r['customer_code']} • ${r['ret_date']} • ${r['reason'] ?? ''}'),
        ),
        onAdd: (c) async {
          final f = await askForm(c, 'مرتجع جديد', [
            Q('cust', 'العميل', options: await _custOptions()), Q('prod', 'الصنف', options: await _prodOptions()),
            Q('qty', 'الكمية', num: true, init: '1'), Q('amount', 'قيمة المرتجع (بتنقص من إجمالي العميل)', num: true), Q('reason', 'السبب'),
          ]);
          if (f == null) return;
          await AppDb.i.addReturn(_code(f['cust']!), _pid(f['prod']!), parseNum(f['qty']).toInt(), parseNum(f['amount']), f['reason']!);
          if (c.mounted) toast(c, 'اتسجل المرتجع واتحدّث حساب العميل');
        },
      );
}

class DamagesScreen extends StatelessWidget {
  const DamagesScreen({super.key});
  @override
  Widget build(BuildContext context) => _Shell(
        title: 'التالف',
        load: () => AppDb.i.db.query('damages', orderBy: 'id DESC'),
        tile: (c, r, _) => ListTile(
          title: Text('${r['product_name']} × ${r['qty']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${r['dmg_date']} • ${r['reason'] ?? ''}'),
          trailing: Text('تكلفة ${_n(r['cost'])}', style: const TextStyle(color: C.red, fontWeight: FontWeight.w700)),
        ),
        onAdd: (c) async {
          final f = await askForm(c, 'تالف جديد', [Q('prod', 'الصنف', options: await _prodOptions()), Q('qty', 'الكمية', num: true, init: '1'), Q('reason', 'السبب')]);
          if (f == null) return;
          final cost = await AppDb.i.addDamage(_pid(f['prod']!), parseNum(f['qty']).toInt(), f['reason']!);
          if (c.mounted) toast(c, 'اتسجل التالف — تكلفة ${fmtMoney(cost)}');
        },
      );
}

class DiscountsScreen extends StatelessWidget {
  const DiscountsScreen({super.key});
  @override
  Widget build(BuildContext context) => _Shell(
        title: 'الخصومات',
        load: () => AppDb.i.db.query('discounts', orderBy: 'id DESC'),
        tile: (c, r, _) => ListTile(
          title: Text('${r['customer_code']} — ${_n(r['amount'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${r['disc_date']} • ${r['reason'] ?? ''}'),
        ),
        onAdd: (c) async {
          final f = await askForm(c, 'خصم لعميل', [Q('cust', 'العميل', options: await _custOptions()), Q('amount', 'قيمة الخصم', num: true), Q('reason', 'السبب')]);
          if (f == null) return;
          await AppDb.i.addDiscount(_code(f['cust']!), parseNum(f['amount']), f['reason']!);
          if (c.mounted) toast(c, 'اتطبّق الخصم');
        },
      );
}

class SupplierInvoicesScreen extends StatelessWidget {
  const SupplierInvoicesScreen({super.key});
  @override
  Widget build(BuildContext context) => _Shell(
        title: 'فواتير الموردين',
        load: () => AppDb.i.supplierInvoices(),
        tile: (c, r, reload) {
          final rem = ((r['total'] as num) - (r['paid0'] as num) - (r['paid_extra'] as num)).toDouble();
          return ListTile(
            title: Text('${r['supplier_name']} — ${_n(r['total'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${r['inv_date']} • مدفوع ${fmtMoney((r['paid0'] as num) + (r['paid_extra'] as num))}'),
            trailing: rem > 0.009
                ? FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
                    onPressed: () async {
                      final f = await askForm(c, 'سداد للمورد (المتبقي ${fmtMoney(rem)})', [Q('amount', 'المبلغ', num: true, init: fmtMoney(rem).replaceAll(',', ''))]);
                      if (f == null || !c.mounted) return;
                      await guard(c, () async {
                        await AppDb.i.addSupplierPayment(r['id'] as int, parseNum(f['amount']));
                        reload();
                      }, ok: 'اتسجل السداد');
                    },
                    child: Text('سدّد ${fmtMoney(rem)}'))
                : const Pill('مسددة', C.green),
          );
        },
        onAdd: (c) async {
          final sup = [for (final r in await AppDb.i.db.query('suppliers', columns: ['name'], orderBy: 'name')) r['name'].toString()];
          final f = await askForm(c, 'فاتورة مورد', [Q('sup', 'المورد (اكتب اسم جديد أو اختار)', options: sup.isEmpty ? null : sup), Q('total', 'الإجمالي', num: true), Q('paid', 'المدفوع', num: true, init: '0'), Q('notes', 'ملاحظات')]);
          if (f == null) return;
          await AppDb.i.addSupplierInvoice(f['sup']!, parseNum(f['total']), parseNum(f['paid']), f['notes']!);
        },
      );
}

class BranchesScreen extends StatelessWidget {
  const BranchesScreen({super.key});
  @override
  Widget build(BuildContext context) => _Shell(
        title: 'الفروع',
        load: () => AppDb.i.db.query('branches', orderBy: 'id'),
        tile: (c, r, _) => ListTile(title: Text('${r['code']}  ${r['name']}', style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('${r['address'] ?? ''}')),
        onAdd: (c) async {
          final f = await askForm(c, 'فرع جديد', [Q('name', 'اسم الفرع'), Q('addr', 'العنوان')]);
          if (f == null) return;
          await AppDb.i.addBranch(f['name']!, f['addr']!);
        },
      );
}

class TargetsScreen extends StatelessWidget {
  const TargetsScreen({super.key});
  @override
  Widget build(BuildContext context) => _Shell(
        title: 'أهداف المناديب',
        load: () async {
          final out = <Map<String, Object?>>[];
          for (final n in await AppDb.i.namesOf('المناديب')) {
            out.add(await AppDb.i.repTargetStatus(n));
          }
          return out;
        },
        tile: (c, r, _) {
          final pct = r['pct'] as double?;
          return ListTile(
            title: Text('${r['rep']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('مبيعات ${r['ym']}: ${_n(r['sales'])} (${r['count']} عقد)'),
              if (pct != null) ...[
                const SizedBox(height: 4),
                LinearProgressIndicator(value: (pct / 100).clamp(0, 1).toDouble(), minHeight: 7, color: pct >= 100 ? C.green : C.purple),
                Text('الهدف ${_n(r['target'])} — ${pct.toStringAsFixed(0)}%'),
              ] else
                const Text('مفيش هدف للشهر ده', style: TextStyle(color: Colors.grey)),
            ]),
          );
        },
        onAdd: (c) async {
          final n = today();
          final f = await askForm(c, 'تحديد هدف', [
            Q('rep', 'المندوب', options: await AppDb.i.namesOf('المناديب')),
            Q('ym', 'الشهر', init: '${n.year}-${n.month.toString().padLeft(2, '0')}'), Q('t', 'الهدف', num: true),
          ]);
          if (f == null) return;
          await AppDb.i.setRepTarget(f['rep']!, trDigits(f['ym']!), parseNum(f['t']));
        },
      );
}

class SalesInvoicesScreen extends StatelessWidget {
  const SalesInvoicesScreen({super.key});
  @override
  Widget build(BuildContext context) => _Shell(
        title: 'فواتير البيع',
        gate: false,
        load: () => AppDb.i.db.query('sales_invoices', orderBy: 'id DESC'),
        tile: (c, r, _) => ListTile(
          title: Text('${r['inv_code']} — ${r['customer_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${r['inv_date']} • ${r['item'] ?? ''} • مقدم ${_n(r['down'])} • ${r['months']} شهر'),
          trailing: Text(_n(r['total']), style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        onAdd: (c) async {
          final f = await askForm(c, 'فاتورة بيع لعميل', [Q('cust', 'العميل', options: await _custOptions())]);
          if (f == null) return;
          await AppDb.i.makeSalesInvoice(_code(f['cust']!));
        },
      );
}

class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});
  @override
  Widget build(BuildContext context) => _Shell(
        title: 'المستخدمين والصلاحيات',
        load: () => AppDb.i.db.query('users', columns: ['user_id', 'role'], orderBy: 'user_id'),
        tile: (c, r, reload) => ListTile(
          title: Text('${r['user_id']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${r['user_id'] == 'admin' ? roleAdmin : r['role']}'),
          trailing: r['user_id'] == 'admin'
              ? null
              : IconButton(
                  icon: const Icon(Icons.delete_outline, color: C.red),
                  onPressed: () async {
                    if (!await confirm(c, 'تحذف المستخدم ${r['user_id']}؟') || !c.mounted) return;
                    await guard(c, () async {
                      await AppDb.i.deleteUser(r['user_id'].toString());
                      reload();
                    });
                  }),
        ),
        onAdd: (c) async {
          final f = await askForm(c, 'مستخدم جديد', [Q('u', 'اسم المستخدم'), Q('p', 'كلمة السر'), Q('r', 'الدور', options: roles.keys.toList(), init: 'محاسب')]);
          if (f == null) return;
          await AppDb.i.addUser(f['u']!, f['p']!, f['r']!);
        },
      );
}
