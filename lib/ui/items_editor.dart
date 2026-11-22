// محرّر أصناف العقد: بيختار الصنف من المخزن وسعره بيظهر تلقائي (وتقدر تعدّله)، والإجمالي بيتحسب
import 'package:flutter/material.dart';
import '../core/utils.dart';
import '../theme.dart';
import 'widgets.dart';

class SaleLine {
  SaleLine({this.pid, this.code = '', required this.name, this.enName = '', this.qty = 1, this.price = 0, this.stock});
  int? pid;
  String code, name, enName; // enName = اسم الصنف بالإنجليزي (للإيصال الإنجليزي)
  int qty;
  double price;
  int? stock;
  double get total => qty * price;
  Map<String, dynamic> toMap() => {'pid': pid, 'code': code, 'name': name, 'qty': qty, 'price': price};
}

double sumLines(List<SaleLine> l) => l.fold<double>(0.0, (s, e) => s + e.total);

String _numT(double v) => v == v.truncate() ? '${v.truncate()}' : '$v';

double _num(String s) {
  try {
    return parseNum(s);
  } catch (_) {
    return 0;
  }
}

class ItemsEditor extends StatefulWidget {
  const ItemsEditor({
    super.key, required this.products, required this.lines, required this.onChanged,
    this.priceKey = 'sell_price', this.title = 'الأصناف', this.showStock = true, this.allowManual = true,
  });
  final List<Map<String, Object?>> products;
  final List<SaleLine> lines;
  final VoidCallback onChanged;
  final String priceKey, title;
  final bool showStock, allowManual;
  @override
  State<ItemsEditor> createState() => _IE();
}

class _IE extends State<ItemsEditor> {
  void _changed() {
    setState(() {});
    widget.onChanged();
  }

  Future<void> _add() async {
    final picked = await showModalBottomSheet<Object>(
      context: context, isScrollControlled: true,
      builder: (_) => _PickSheet(products: widget.products, priceKey: widget.priceKey, showStock: widget.showStock, allowManual: widget.allowManual),
    );
    if (picked == null) return;
    // الاختيار المتعدد: قايمة من (صنف، كمية). الصنف اليدوي بييجي كنص.
    final list = picked is List ? picked : [picked];
    for (final pk in list) {
      if (pk is (Map<String, Object?>, int)) {
        final picked = pk.$1;
        final n = pk.$2;
        final pid = (picked['id'] as num).toInt();
        final ex = widget.lines.where((l) => l.pid == pid).toList();
        if (ex.isNotEmpty) {
          ex.first.qty += n;
        } else {
          widget.lines.add(SaleLine(
            pid: pid, code: (picked['code'] ?? '').toString(), name: (picked['name'] ?? '').toString(), enName: (picked['en_name'] ?? '').toString(), qty: n,
            price: ((picked[widget.priceKey] ?? 0) as num).toDouble(), stock: ((picked['qty'] ?? 0) as num).toInt(),
          ));
        }
      } else if (pk is String) {
        widget.lines.add(SaleLine(name: pk));
      }
    }
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final total = sumLines(widget.lines);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const Spacer(),
        TextButton.icon(onPressed: _add, icon: const Icon(Icons.add_circle_rounded), label: const Text('إضافة صنف')),
      ]),
      if (widget.lines.isEmpty)
        InkWell(
          onTap: _add,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity, padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(border: Border.all(color: C.line), borderRadius: BorderRadius.circular(16)),
            child: const Text('اضغط لاختيار الصنف من المخزن — السعر بيظهر تلقائي', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
          ),
        ),
      for (final l in widget.lines)
        _LineRow(
          key: ObjectKey(l), line: l, showStock: widget.showStock, onChanged: _changed,
          onDelete: () {
            widget.lines.remove(l);
            _changed();
          },
        ),
      if (widget.lines.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('مجموع الأصناف', style: TextStyle(color: Colors.grey)),
            Text(fmtMoney(total), style: const TextStyle(fontWeight: FontWeight.w900, color: C.purple, fontSize: 16)),
          ]),
        ),
    ]);
  }
}

class _LineRow extends StatefulWidget {
  const _LineRow({super.key, required this.line, required this.showStock, required this.onChanged, required this.onDelete});
  final SaleLine line;
  final bool showStock;
  final VoidCallback onChanged, onDelete;
  @override
  State<_LineRow> createState() => _LR();
}

class _LR extends State<_LineRow> {
  late final TextEditingController price = TextEditingController(text: widget.line.price == 0 ? '' : _numT(widget.line.price));

  @override
  void dispose() {
    price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.line;
    final short = widget.showStock && l.stock != null && l.qty > l.stock!;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Column(children: [
          Row(children: [
            Expanded(child: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w800))),
            if (widget.showStock && l.stock != null) Pill('رصيد ${l.stock}', short ? C.red : C.green),
            if (l.pid == null) const Padding(padding: EdgeInsets.only(right: 6), child: Pill('يدوي', C.orange)),
            IconButton(onPressed: widget.onDelete, icon: const Icon(Icons.close_rounded, color: C.red, size: 20)),
          ]),
          Row(children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: l.qty > 1 ? () { l.qty -= 1; widget.onChanged(); } : null,
              icon: const Icon(Icons.remove_circle_outline_rounded),
            ),
            Text('${l.qty}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            IconButton(visualDensity: VisualDensity.compact, onPressed: () { l.qty += 1; widget.onChanged(); }, icon: const Icon(Icons.add_circle_outline_rounded)),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (v) { l.price = _num(v); widget.onChanged(); },
                decoration: const InputDecoration(labelText: 'سعر القطعة', isDense: true),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(width: 78, child: Text(fmtMoney(l.total), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800))),
          ]),
          if (short) const Align(alignment: Alignment.centerRight, child: Text('الكمية أكبر من رصيد المخزن', style: TextStyle(color: C.red, fontSize: 11))),
        ]),
      ),
    );
  }
}

class _PickSheet extends StatefulWidget {
  const _PickSheet({required this.products, required this.priceKey, required this.showStock, required this.allowManual});
  final List<Map<String, Object?>> products;
  final String priceKey;
  final bool showStock, allowManual;
  @override
  State<_PickSheet> createState() => _PS();
}

class _PS extends State<_PickSheet> {
  String q = '';
  final picks = <int, (Map<String, Object?>, int)>{}; // id → (الصنف، العدد اللي اتضاف)
  int get _n => picks.values.fold(0, (a, e) => a + e.$2);
  double get _sum => picks.values.fold(0.0, (a, e) => a + e.$2 * ((e.$1[widget.priceKey] ?? 0) as num).toDouble());
  @override
  Widget build(BuildContext context) {
    final nq = normAr(q).trim();
    final list = widget.products.where((p) => nq.isEmpty || normAr('${p['name']} ${p['code']} ${p['category']} ${p['barcode']}').contains(nq)).toList();
    final exact = widget.products.any((p) => normAr((p['name'] ?? '').toString()).trim() == nq);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: TextField(autofocus: true, onChanged: (v) => setState(() => q = v), decoration: const InputDecoration(hintText: 'ابحث باسم الصنف أو الكود', prefixIcon: Icon(Icons.search))),
          ),
          if (widget.allowManual && q.trim().isNotEmpty && !exact)
            ListTile(
              leading: const Icon(Icons.edit_note_rounded, color: C.orange),
              title: Text('إضافة «${q.trim()}» كصنف يدوي'),
              subtitle: const Text('مش من المخزن — مش هيتخصم من رصيد (وبيتضاف مع اللي اخترته)'),
              onTap: () => Navigator.pop(context, [...picks.values, q.trim()]),
            ),
          Expanded(
            child: list.isEmpty
                ? const Empty('مفيش أصناف بالاسم ده')
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final p = list[i];
                      final qty = ((p['qty'] ?? 0) as num).toInt();
                      final pr = ((p[widget.priceKey] ?? 0) as num).toDouble();
                      return ListTile(
                        onTap: () => setState(() {
                          final id = (p['id'] as num).toInt();
                          picks[id] = (p, (picks[id]?.$2 ?? 0) + 1);
                        }),
                        leading: picks[(p['id'] as num).toInt()] == null
                            ? const Icon(Icons.add_circle_outline_rounded, color: C.purple)
                            : CircleAvatar(radius: 14, backgroundColor: C.purple, child: Text('${picks[(p['id'] as num).toInt()]!.$2}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800))),
                        title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${p['code'] ?? ''}${(p['category'] ?? '').toString().isEmpty ? '' : ' • ${p['category']}'}'),
                        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(pr > 0 ? fmtMoney(pr) : 'بدون سعر', style: TextStyle(fontWeight: FontWeight.w800, color: pr > 0 ? C.purple : Colors.grey)),
                          if (widget.showStock) Text('رصيد $qty', style: TextStyle(fontSize: 11, color: qty <= 0 ? C.red : C.green)),
                        ]),
                      );
                    },
                  ),
          ),
          if (picks.isNotEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                child: Row(children: [
                  Expanded(child: Text('اخترت $_n قطعة — ${fmtMoney(_sum)} جنيه', style: const TextStyle(fontWeight: FontWeight.w800))),
                  TextButton(onPressed: () => setState(picks.clear), child: const Text('مسح')),
                  const SizedBox(width: 6),
                  FilledButton.icon(onPressed: () => Navigator.pop(context, picks.values.toList()), icon: const Icon(Icons.check_rounded), label: const Text('تم')),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
