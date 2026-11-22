// المخزن: الأصناف، الوارد، المتابعة، وربطها بالعملاء والعهدة
import 'package:sqflite/sqflite.dart';
import '../core/utils.dart';
import 'db.dart';
import 'ops.dart';

/// صنف + إحصائيات حركته (للمتابعة)
class ProdStat {
  ProdStat(this.row, {this.soldAll = 0, this.sold30 = 0, this.inCustody = 0, this.lastSale});
  final Map<String, Object?> row;
  int soldAll, sold30, inCustody;
  DateTime? lastSale;

  int get id => (row['id'] as num).toInt();
  String get name => (row['name'] ?? '').toString();
  String get code => (row['code'] ?? '').toString();
  int get qty => ((row['qty'] ?? 0) as num).toInt();
  int get minQty => ((row['min_qty'] ?? 3) as num).toInt();
  double get buy => ((row['buy_price'] ?? 0) as num).toDouble();
  double get sell => ((row['sell_price'] ?? 0) as num).toDouble();
  bool get low => qty <= minQty;
  bool get out => qty <= 0;

  /// كام يوم الرصيد يكفي بمعدل بيع آخر 30 يوم (null لو مفيش مبيعات)
  double? get daysCover => sold30 <= 0 ? null : qty / (sold30 / 30);
  bool get slow => qty > 0 && (lastSale == null || today().difference(lastSale!).inDays > 60);
}

extension StockOps on AppDb {
  // ------------------------------------------------------------ أصناف
  Future<int> saveProduct({
    int? id, required String name, String category = '', double buy = 0, double sell = 0, double repComm = 0,
    int minQty = 3, String barcode = '', int openingQty = 0, String enName = '',
  }) async {
    name = name.trim();
    if (name.isEmpty) throw const FormatException('اكتب اسم الصنف.');
    if (buy < 0 || sell < 0) throw const FormatException('الأسعار مينفعش تبقى بالسالب.');
    if (repComm < 0) throw const FormatException('عمولة المندوب مينفعش تبقى بالسالب.');
    if (repComm > sell && sell > 0) throw const FormatException('عمولة المندوب أكبر من سعر بيع الصنف، راجع الرقم.');
    if (minQty < 0) throw const FormatException('حد النواقص مينفعش يبقى بالسالب.');
    if (openingQty < 0) throw const FormatException('الرصيد الافتتاحي مينفعش يبقى بالسالب.');
    final data = {
      'name': name, 'category': category.trim(), 'buy_price': buy, 'sell_price': sell, 'rep_comm': repComm,
      'min_qty': minQty, 'barcode': barcode.trim(), 'en_name': enName.trim(),
    };
    // الفحص والحفظ وتحديث الأسماء المرتبطة والسجل: عملية واحدة
    final res = await db.transaction<int>((tx) async {
      for (final r in await tx.query('products')) {
        if (r['id'] != id && normAr((r['name'] ?? '').toString()).trim() == normAr(name).trim()) {
          throw const FormatException('فيه صنف بنفس الاسم قبل كده.');
        }
      }
      if (id == null) {
        final nid = await tx.insert('products', {...data, 'qty': 0, 'code': await nextCode('P', 'products', 'code', tx)});
        if (openingQty > 0) await stockMoveIn(tx, nid, openingQty, 'رصيد افتتاحي', allowNeg: true);
        await logIn(tx, 'إضافة صنف', '$name — بيع ${fmtMoney(sell)} — رصيد $openingQty');
        return nid;
      }
      final old = await tx.query('products', where: 'id=?', whereArgs: [id]);
      if (old.isEmpty) throw const FormatException('الصنف مش موجود.');
      await tx.update('products', data, where: 'id=?', whereArgs: [id]);
      // لو الاسم اتغيّر نحدّث اسمه في الحركات والبنود عشان الربط يفضل شغال
      final oldName = (old.first['name'] ?? '').toString();
      if (oldName != name) {
        await tx.update('stock_moves', {'product_name': name}, where: 'product_id=?', whereArgs: [id]);
        await tx.update('customer_items', {'product_name': name}, where: 'product_id=?', whereArgs: [id]);
        await tx.update('custody', {'item_name': name}, where: 'item_name=?', whereArgs: [oldName]);
      }
      await logIn(tx, 'تعديل صنف', '$name — بيع ${fmtMoney(sell)}');
      return id;
    });
    bumpData();
    return res;
  }

  Future<void> deleteProduct(int id) async {
    await _deleteProductTx(id);
    bumpData();
  }

  Future<void> _deleteProductTx(int id) => db.transaction((tx) async {
        final r = await tx.query('products', where: 'id=?', whereArgs: [id]);
        if (r.isEmpty) throw const FormatException('الصنف مش موجود.');
        final used = await tx.rawQuery('SELECT COUNT(*) n FROM customer_items WHERE product_id=?', [id]);
        if (((used.first['n'] ?? 0) as num) > 0) throw const FormatException('الصنف ده متباع لعملاء، مينفعش يتحذف (صفّر رصيده بدل كده).');
        final cu = await tx.query('custody', where: 'item_name=? AND status=?', whereArgs: [r.first['name'], custodyOpen]);
        if (cu.isNotEmpty) throw const FormatException('الصنف ده في عهدة مندوب مفتوحة.');
        await tx.delete('stock_moves', where: 'product_id=?', whereArgs: [id]);
        await tx.delete('products', where: 'id=?', whereArgs: [id]);
        await logIn(tx, 'حذف صنف', '${r.first['name']}');
      });

  // ------------------------------------------------------------ وارد / استلام بضاعة
  /// lines: [{pid, qty, price(سعر الشراء، اختياري)}] — بيزوّد الرصيد، وبيحدّث سعر الشراء، وبيعمل فاتورة مورد لو اتحددت.
  Future<void> receiveStock(List<Map<String, dynamic>> lines, {String supplier = '', double paid = 0, bool invoice = false, String notes = ''}) async {
    final ok = lines.where((l) => ((l['qty'] ?? 0) as num) > 0).toList();
    if (ok.isEmpty) throw const FormatException('ضيف صنف واحد على الأقل بكمية أكبر من صفر.');
    var total = 0.0;
    for (final l in ok) {
      total += ((l['qty'] as num).toDouble()) * ((l['price'] ?? 0) as num).toDouble();
    }
    if (invoice) {
      if (supplier.trim().isEmpty) throw const FormatException('اكتب اسم المورد عشان تتسجل الفاتورة.');
      if (total <= 0) throw const FormatException('اكتب أسعار الشراء عشان تتحسب فاتورة المورد.');
      if (paid < 0 || paid > total) throw FormatException('المدفوع لازم يكون من صفر لحد ${fmtMoney(total)}.');
    }
    final ref = supplier.trim().isEmpty ? 'وارد' : 'مورد ${supplier.trim()}';
    // الرصيد + سعر الشراء + فاتورة المورد + السجل: عملية واحدة (مفيش حالة بضاعة دخلت من غير فاتورتها)
    await db.transaction((tx) async {
      for (final l in ok) {
        final pid = (l['pid'] as num).toInt();
        await stockMoveIn(tx, pid, (l['qty'] as num).toInt(), 'وارد', ref: ref, notes: notes, allowNeg: true);
        final pr = ((l['price'] ?? 0) as num).toDouble();
        if (pr > 0) await tx.update('products', {'buy_price': pr}, where: 'id=?', whereArgs: [pid]);
      }
      if (invoice) await addSupplierInvoiceIn(tx, supplier, r2(total), paid, notes.isEmpty ? 'استلام بضاعة' : notes);
      await logIn(tx, 'استلام بضاعة', '$ref — ${ok.length} صنف');
    });
  }

  // ------------------------------------------------------------ ربط العميل
  Future<List<Map<String, Object?>>> customerItems(String code) =>
      db.query('customer_items', where: 'customer_code=?', whereArgs: [code], orderBy: 'id');

  /// مين اشترى الصنف ده (صافي بعد المرتجع)
  Future<List<Map<String, Object?>>> productBuyers(int pid) => db.rawQuery('''
      SELECT i.id, i.customer_code, c.name AS customer_name, i.qty, IFNULL(i.returned_qty,0) AS returned_qty, i.unit_price, i.line_total,
             i.sold_at, i.rep_name, i.stock_qty
      FROM customer_items i LEFT JOIN customers c ON c.customer_code = i.customer_code
      WHERE i.product_id = ? ORDER BY i.sold_at DESC, i.id DESC''', [pid]);

  // ------------------------------------------------------------ متابعة
  Future<List<ProdStat>> stockStats() async {
    final prods = await db.query('products', orderBy: 'name');
    final cutoff = today().subtract(const Duration(days: 30));
    final sales = await db.rawQuery('SELECT product_id, qty, IFNULL(returned_qty,0) rq, sold_at FROM customer_items WHERE product_id IS NOT NULL');
    final cust = await db.query('custody', where: 'status=?', whereArgs: [custodyOpen]);
    final custByName = <String, int>{};
    for (final c in cust) {
      final k = normAr((c['item_name'] ?? '').toString()).trim();
      custByName[k] = (custByName[k] ?? 0) + ((c['qty'] ?? 0) as num).toInt();
    }
    final by = <int, ProdStat>{
      for (final p in prods)
        (p['id'] as num).toInt(): ProdStat(p, inCustody: custByName[normAr((p['name'] ?? '').toString()).trim()] ?? 0),
    };
    for (final s in sales) {
      final st = by[(s['product_id'] as num).toInt()];
      if (st == null) continue;
      final net = ((s['qty'] ?? 0) as num).toInt() - ((s['rq'] ?? 0) as num).toInt();
      st.soldAll += net;
      final d = toDate(s['sold_at']);
      if (d != null) {
        if (!d.isBefore(cutoff)) st.sold30 += net;
        if (st.lastSale == null || d.isAfter(st.lastSale!)) st.lastSale = d;
      }
    }
    return by.values.toList();
  }

  Future<Map<String, num>> stockSummary() async {
    final st = await stockStats();
    var buyVal = 0.0, sellVal = 0.0;
    for (final s in st) {
      if (s.qty > 0) {
        buyVal += s.qty * s.buy;
        sellVal += s.qty * s.sell;
      }
    }
    final custQty = st.fold<int>(0, (a, s) => a + s.inCustody);
    return {
      'count': st.length, 'low': st.where((s) => s.low && !s.out).length, 'out': st.where((s) => s.out).length,
      'buyVal': buyVal, 'sellVal': sellVal, 'custody': custQty,
    };
  }

  /// العهدة المفتوحة مجمّعة بالمندوب
  Future<List<Map<String, Object?>>> openCustody() =>
      db.query('custody', where: 'status=? AND qty>0', whereArgs: [custodyOpen], orderBy: 'rep_name, item_name');

  Future<List<Map<String, Object?>>> productMoves(int pid, {int limit = 40}) =>
      db.query('stock_moves', where: 'product_id=?', whereArgs: [pid], orderBy: 'id DESC', limit: limit);

  Future<void> adjustStock(int pid, String kind, int n, {String notes = ''}) async {
    if (n < 0) throw const FormatException('الكمية مينفعش تبقى بالسالب.');
    if (kind == 'تالف') {
      if (n == 0) throw const FormatException('اكتب كمية التالف.');
      await addDamage(pid, n, notes);
      return;
    }
    await db.transaction((tx) async {
      final r = await tx.query('products', columns: ['qty'], where: 'id=?', whereArgs: [pid]);
      if (r.isEmpty) throw const FormatException('الصنف مش موجود.');
      final cur = ((r.first['qty'] ?? 0) as num).toInt();
      final delta = kind == 'وارد' ? n : (kind == 'صادر' ? -n : n - cur);
      if (delta == 0) throw const FormatException('مفيش فرق يتسجّل.');
      await stockMoveIn(tx, pid, delta, kind == 'جرد' ? 'جرد' : kind, notes: notes);
      await logIn(tx, 'حركة مخزن', 'صنف $pid $kind $delta');
    });
  }
}
