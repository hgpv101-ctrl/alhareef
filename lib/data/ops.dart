// عمليات إضافية منقولة من Database في البرنامج الأصلي: مرتجع/تالف/خصم/فاتورة بيع/فروع/تارجت/موردين/عهدة/مستخدمين...
import 'package:sqflite/sqflite.dart';
import '../core/security.dart';
import '../core/utils.dart';
import 'db.dart';
import 'package:flutter/foundation.dart';

extension Ops on AppDb {
  Future<List<String>> namesOf(String type) async =>
      [for (final r in await db.query('representatives', columns: ['name'], where: 'type=?', whereArgs: [type], orderBy: 'name')) r['name'].toString()];

  /// بيدوّر على الصنف: تطابق تام الأول، وبعدين تطابق جزئي بس لو نتيجة واحدة (عشان ما نخصم من صنف غلط).
  Future<Map<String, Object?>?> productByName(String name, [DatabaseExecutor? ex]) async {
    final n = normAr(name.trim());
    if (n.isEmpty) return null;
    final all = await (ex ?? db).query('products');
    for (final r in all) {
      if (normAr((r['name'] ?? '').toString()).trim() == n) return r;
    }
    final part = <Map<String, Object?>>[];
    for (final r in all) {
      final pn = normAr((r['name'] ?? '').toString()).trim();
      if (pn.isNotEmpty && (pn.contains(n) || n.contains(pn))) part.add(r);
    }
    return part.length == 1 ? part.first : null;
  }

  /// بحث بالكود الأول (P12) وبعدين بالاسم
  Future<Map<String, Object?>?> productByCodeOrName(String code, String name) async {
    final c = code.trim();
    if (c.isNotEmpty) {
      final r = await db.query('products', where: 'code=?', whereArgs: [c]);
      if (r.isNotEmpty) return r.first;
    }
    return productByName(name);
  }

  Future<void> ensureRegion(String name, [DatabaseExecutor? ex]) async {
    name = name.trim();
    if (name.isEmpty) return;
    final e = ex ?? db;
    final r = await e.query('regions', where: 'name=?', whereArgs: [name]);
    if (r.isEmpty) await e.insert('regions', {'name': name, 'sub_name': ''});
  }

  // ------------------------------------------------------------ مرتجع / خصم / تالف
  Future<void> _reduceTotal(DatabaseExecutor ex, String code, double amount) async {
    final cur = await financials(code: code, ex: ex);
    if (cur.isEmpty) throw const FormatException('العميل مش موجود.');
    amount = r2(amount);
    if (amount <= 0) throw const FormatException('المبلغ لازم يكون أكبر من صفر.');
    final nt = r2(cur.first.total - amount);
    if (nt <= 0) throw const FormatException('المبلغ أكبر من أو يساوي إجمالي العميل.');
    await updateCustomerIn(ex, code, {'total': nt});
  }

  /// مرتجع: خصم من إجمالي العميل + رجوع للمخزن + تعليم البند + سجل المرتجعات — عملية واحدة يا تكتمل كلها يا تتلغي كلها
  Future<String> addReturn(String code, int productId, int qty, double amount, [String reason = '']) async {
    if (qty <= 0) throw const FormatException('كمية المرتجع لازم تكون أكبر من صفر.');
    final name = await db.transaction<String>((tx) async {
      final pr = await tx.query('products', columns: ['name'], where: 'id=?', whereArgs: [productId]);
      if (pr.isEmpty) throw const FormatException('الصنف مش موجود.');
      final pname = pr.first['name'].toString();
      await _markReturned(tx, code, productId, qty);
      await _reduceTotal(tx, code, amount);
      if (await trackStockIn(tx)) await stockMoveIn(tx, productId, qty, 'مرتجع', ref: code, notes: reason, allowNeg: true);
      await tx.insert('returns_log', {
        'ret_date': isoDate(today()), 'customer_code': code, 'product_id': productId, 'product_name': pname,
        'qty': qty, 'amount': amount, 'reason': reason,
      });
      await logIn(tx, 'مرتجع', '$code $pname × $qty بمبلغ ${fmtMoney(amount)}');
      return pname;
    });
    bumpData();
    return name;
  }

  /// بيعلّم المرتجع على بند العميل عشان تقارير «مين اشترى» تبقى صح.
  /// لو العميل عنده بنود مسجّلة للصنف ده والكمية أكبر من اللي اشتراه فعلاً → بيرفض (العملاء القدام من غير بنود بيعدّوا زي الأول)
  Future<void> _markReturned(DatabaseExecutor ex, String code, int productId, int qty) async {
    final rows = await ex.query('customer_items', where: 'customer_code=? AND product_id=?', whereArgs: [code, productId], orderBy: 'id');
    var avail = 0;
    for (final r in rows) {
      final can = ((r['qty'] ?? 0) as num).toInt() - ((r['returned_qty'] ?? 0) as num).toInt();
      if (can > 0) avail += can;
    }
    if (rows.isNotEmpty && qty > avail) {
      throw FormatException('الكمية المرتجعة ($qty) أكبر من اللي العميل اشتراه ولسه ما رجّعوش ($avail).');
    }
    var left = qty;
    for (final r in rows) {
      if (left <= 0) break;
      final can = ((r['qty'] ?? 0) as num).toInt() - ((r['returned_qty'] ?? 0) as num).toInt();
      if (can <= 0) continue;
      final take = can < left ? can : left;
      await ex.update('customer_items', {'returned_qty': ((r['returned_qty'] ?? 0) as num).toInt() + take}, where: 'id=?', whereArgs: [r['id']]);
      left -= take;
    }
  }

  Future<void> addDiscount(String code, double amount, [String reason = '']) async {
    await db.transaction((tx) async {
      await _reduceTotal(tx, code, amount);
      await tx.insert('discounts', {'disc_date': isoDate(today()), 'customer_code': code, 'amount': amount, 'reason': reason});
      await logIn(tx, 'خصم عميل', '$code ${fmtMoney(amount)}');
    });
    bumpData();
  }

  Future<double> addDamage(int productId, int qty, [String reason = '']) async {
    if (qty <= 0) throw const FormatException('كمية التالف لازم تكون أكبر من صفر.');
    return db.transaction<double>((tx) async {
      final pr = await tx.query('products', columns: ['name', 'buy_price'], where: 'id=?', whereArgs: [productId]);
      if (pr.isEmpty) throw const FormatException('الصنف مش موجود.');
      final tracked = await trackStockIn(tx);
      if (tracked) await stockMoveIn(tx, productId, -qty, 'تالف', notes: reason);
      final cost = r2(((pr.first['buy_price'] ?? 0) as num).toDouble() * qty);
      await tx.insert('damages', {
        'dmg_date': isoDate(today()), 'product_id': productId, 'product_name': pr.first['name'], 'qty': qty,
        'cost': cost, 'reason': reason, 'stock_updated': tracked ? 1 : 0,
      });
      await logIn(tx, 'تالف', '${pr.first['name']} × $qty تكلفة ${fmtMoney(cost)}');
      return cost;
    });
  }

  // ------------------------------------------------------------ فاتورة بيع
  Future<Map<String, Object?>> makeSalesInvoice(String code) => db.transaction<Map<String, Object?>>((tx) async {
        final cur = await financials(code: code, ex: tx);
        if (cur.isEmpty) throw const FormatException('العميل مش موجود.');
        final c = cur.first;
        final br = await tx.query('customers', columns: ['branch'], where: 'customer_code=?', whereArgs: [code]);
        final inv = await nextCode('F', 'sales_invoices', 'inv_code', tx);
        await tx.insert('sales_invoices', {
          'inv_code': inv, 'inv_date': isoDate(today()), 'customer_code': code, 'customer_name': c.name, 'item': c.item,
          'total': c.total, 'down': c.down, 'months': c.months, 'monthly': c.months > 0 ? r2((c.total - c.down) / c.months) : 0,
          'branch': br.isEmpty ? '' : (br.first['branch'] ?? ''),
        });
        await logIn(tx, 'فاتورة بيع', '$inv $code ${fmtMoney(c.total)}');
        return (await tx.query('sales_invoices', where: 'inv_code=?', whereArgs: [inv])).first;
      });

  // ------------------------------------------------------------ فروع
  Future<String> addBranch(String name, [String address = '']) async {
    name = name.trim();
    if (name.isEmpty) throw const FormatException('اسم الفرع مطلوب.');
    if ((await db.query('branches', where: 'name=?', whereArgs: [name])).isNotEmpty) throw const FormatException('الفرع ده موجود قبل كده.');
    final code = await nextCode('B', 'branches', 'code');
    await db.insert('branches', {'code': code, 'name': name, 'address': address.trim(), 'created': isoDate(today())});
    await log('إضافة فرع', name);
    return code;
  }

  Future<void> setCustomerBranch(String code, String branch) async {
    if ((await db.query('branches', where: 'name=?', whereArgs: [branch])).isEmpty) throw const FormatException('الفرع ده مش موجود.');
    await db.update('customers', {'branch': branch}, where: 'customer_code=?', whereArgs: [code]);
    await log('عميل لفرع', '$code → $branch');
  }

  // ------------------------------------------------------------ تارجت المندوب
  Future<void> setRepTarget(String rep, String ym, double amount) async {
    if ((await db.query('representatives', where: 'type=? AND name=?', whereArgs: ['المناديب', rep])).isEmpty) {
      throw const FormatException('المندوب ده مش موجود في المناديب.');
    }
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(ym)) throw const FormatException('الشهر لازم يكون بالشكل 2026-10.');
    if (amount <= 0) throw const FormatException('الهدف لازم يكون أكبر من صفر.');
    await db.rawInsert(
        'INSERT INTO rep_targets (rep_name, ym, target, created) VALUES (?,?,?,?) ON CONFLICT(rep_name, ym) DO UPDATE SET target=excluded.target',
        [rep, ym, amount, DateTime.now().toIso8601String().substring(0, 16).replaceFirst('T', ' ')]);
    await log('هدف مندوب', '$rep $ym ${fmtMoney(amount)}');
  }

  Future<Map<String, Object?>> repTargetStatus(String rep, [String? ym]) async {
    final n = today();
    ym ??= '${n.year}-${n.month.toString().padLeft(2, '0')}';
    final t = await db.query('rep_targets', where: 'rep_name=? AND ym=?', whereArgs: [rep, ym]);
    final s = await db.rawQuery("SELECT IFNULL(SUM(total_amount),0) s, COUNT(*) n FROM customers WHERE rep_name=? AND substr(start_date,1,7)=?", [rep, ym]);
    final target = t.isEmpty ? null : (t.first['target'] as num).toDouble();
    final sales = (s.first['s'] as num).toDouble();
    return {
      'rep': rep, 'ym': ym, 'target': target, 'sales': sales, 'count': s.first['n'],
      'pct': target == null ? null : sales / target * 100, 'left': target == null ? null : (target - sales < 0 ? 0.0 : target - sales),
    };
  }

  // ------------------------------------------------------------ موردين وفواتيرهم
  Future<void> ensureSupplier(String name, [DatabaseExecutor? ex]) async {
    name = name.trim();
    if (name.isEmpty) return;
    final e = ex ?? db;
    if ((await e.query('suppliers', where: 'name=?', whereArgs: [name])).isEmpty) {
      await e.insert('suppliers', {'name': name, 'code': await nextCode('S', 'suppliers', 'code', e)});
    }
  }

  Future<int> addSupplierInvoice(String supplier, double total, double paid, [String notes = '']) =>
      db.transaction<int>((tx) => addSupplierInvoiceIn(tx, supplier, total, paid, notes));

  /// فاتورة مورد جوه transaction موجودة (بتتستخدم من استلام البضاعة عشان الكل يبقى عملية واحدة)
  Future<int> addSupplierInvoiceIn(DatabaseExecutor ex, String supplier, double total, double paid, [String notes = '']) async {
    if (supplier.trim().isEmpty) throw const FormatException('اكتب اسم المورد.');
    if (total <= 0) throw const FormatException('إجمالي الفاتورة لازم يكون أكبر من صفر.');
    if (paid < 0 || paid > total) throw const FormatException('المدفوع لازم يكون من صفر لحد إجمالي الفاتورة.');
    await ensureSupplier(supplier, ex);
    final id = await ex.insert('suppliers_invoices', {'supplier_name': supplier.trim(), 'inv_date': isoDate(today()), 'total': total, 'paid': paid, 'notes': notes});
    await logIn(ex, 'فاتورة مورد', '$supplier ${fmtMoney(total)} مدفوع ${fmtMoney(paid)}');
    return id;
  }

  Future<List<Map<String, Object?>>> supplierInvoices([DatabaseExecutor? ex]) => (ex ?? db).rawQuery('''
      SELECT i.id, i.supplier_name, i.inv_date, IFNULL(i.total,0) AS total, IFNULL(i.paid,0) AS paid0, i.notes,
             IFNULL((SELECT SUM(p.amount) FROM supplier_payments p WHERE p.invoice_id = i.id),0) AS paid_extra
      FROM suppliers_invoices i ORDER BY i.id DESC''');

  Future<void> addSupplierPayment(int invoiceId, double amount, [String notes = '']) => db.transaction((tx) async {
        final inv = (await supplierInvoices(tx)).where((r) => r['id'] == invoiceId).toList();
        if (inv.isEmpty) throw const FormatException('الفاتورة مش موجودة.');
        final i = inv.first;
        final rem = r2((i['total'] as num).toDouble() - (i['paid0'] as num).toDouble() - (i['paid_extra'] as num).toDouble());
        if (amount <= 0) throw const FormatException('المبلغ لازم يكون أكبر من صفر.');
        if (amount > rem + 0.009) throw FormatException('المبلغ أكبر من المتبقي على الفاتورة (${fmtMoney(rem)}).');
        await tx.insert('supplier_payments', {'invoice_id': invoiceId, 'amount': amount, 'pay_date': isoDate(today()), 'notes': notes});
        await logIn(tx, 'سداد مورد', '${i['supplier_name']} ${fmtMoney(amount)}');
      });

  // ------------------------------------------------------------ عهدة
  Future<void> giveCustody(String rep, String item, int qty, {String notes = '', String? date}) =>
      giveCustodyMulti(rep, [(item, qty)], notes: notes, date: date);

  /// تسليم عهدة بأكتر من صنف في عملية واحدة: يا الكل يتسجّل يا ولا حاجة (مفيش نص عهدة لو صنف رصيده ناقص)
  Future<void> giveCustodyMulti(String rep, List<(String, int)> lines, {String notes = '', String? date}) async {
    if (!(await namesOf('المناديب')).contains(rep)) throw const FormatException('اختار المندوب من القائمة، أو سجّله الأول.');
    if (lines.isEmpty) throw const FormatException('ضيف صنف واحد على الأقل.');
    // نجمّع الأصناف المتكررة عشان فحص الرصيد يبقى على الكمية الكلية
    final merged = <String, int>{};
    for (final l in lines) {
      if (l.$2 <= 0) throw const FormatException('الكمية لازم تكون أكبر من صفر.');
      merged[l.$1] = (merged[l.$1] ?? 0) + l.$2;
    }
    await db.transaction((tx) async {
      final track = await trackStockIn(tx);
      final allowNeg = await allowNegIn(tx);
      for (final e in merged.entries) {
        final p = await productByName(e.key, tx); // الرصيد بيتقرا طازة جوه نفس العملية
        if (p != null && track) {
          final cur = ((p['qty'] ?? 0) as num).toInt();
          if (cur - e.value < 0 && !allowNeg) {
            throw FormatException("رصيد '${p['name']}' في المخزن ($cur) مش كفاية لكمية ${e.value}.");
          }
          await tx.update('products', {'qty': cur - e.value}, where: 'id=?', whereArgs: [p['id']]);
          await tx.insert('stock_moves', {'product_id': p['id'], 'product_name': p['name'], 'kind': 'عهدة', 'qty': -e.value, 'balance_after': cur - e.value, 'move_date': isoDate(today()), 'ref': 'مندوب $rep', 'notes': ''});
        }
        await tx.insert('custody', {'rep_name': rep, 'item_name': e.key, 'qty': e.value, 'date_given': date ?? isoDate(today()), 'status': custodyOpen, 'notes': notes});
      }
      await logIn(tx, 'تسليم عهدة', '$rep ${merged.entries.map((e) => '${e.value} ${e.key}').join(' + ')}');
    });
  }

  Future<void> returnCustody(int id) => returnCustodyMany([id]);

  /// إرجاع أكتر من عهدة في عملية واحدة: لو واحدة فشلت ولا واحدة بتتسجّل
  Future<void> returnCustodyMany(List<int> ids) => db.transaction((tx) async {
        for (final id in ids) {
          final r = await tx.query('custody', where: 'id=?', whereArgs: [id]);
          if (r.isEmpty) throw const FormatException('العهدة مش موجودة.');
          final c = r.first;
          if (c['status'] != custodyOpen) throw const FormatException('العهدة دي اترجّعت قبل كده.');
          final p = await productByName((c['item_name'] ?? '').toString(), tx);
          if (p != null && await trackStockIn(tx)) {
            await stockMoveIn(tx, (p['id'] as num).toInt(), (c['qty'] as num).toInt(), 'مرتجع عهدة', ref: 'مندوب ${c['rep_name']}', allowNeg: true);
          }
          await tx.update('custody', {'status': custodyReturned, 'returned_date': isoDate(today())}, where: 'id=?', whereArgs: [id]);
          await logIn(tx, 'إرجاع عهدة', '${c['rep_name']} ${c['qty']} ${c['item_name']}');
        }
      });

  Future<void> deleteCustody(int id) => db.transaction((tx) async {
        final r = await tx.query('custody', where: 'id=?', whereArgs: [id]);
        if (r.isEmpty) return;
        final c = r.first;
        if (c['status'] == custodyOpen) {
          final p = await productByName((c['item_name'] ?? '').toString(), tx);
          if (p != null && await trackStockIn(tx)) {
            await stockMoveIn(tx, (p['id'] as num).toInt(), (c['qty'] as num).toInt(), 'إلغاء عهدة', ref: 'مندوب ${c['rep_name']}', allowNeg: true);
          }
        }
        await tx.delete('custody', where: 'id=?', whereArgs: [id]);
        await logIn(tx, 'حذف عهدة', '${c['rep_name']} ${c['qty']} ${c['item_name']}');
      });

  // ------------------------------------------------------------ مستخدمين
  Future<void> addUser(String u, String pw, String role) async {
    u = u.trim();
    if (pw.length < 4 || u.isEmpty || u.toLowerCase() == 'admin') throw const FormatException('الاسم مش مقبول أو كلمة السر قصيرة.');
    if (!roles.containsKey(role)) throw const FormatException('الصلاحية غير معروفة.');
    if ((await db.query('users', where: 'user_id=?', whereArgs: [u])).isNotEmpty) throw const FormatException('المستخدم ده موجود.');
    await db.insert('users', {'user_id': u, 'password': await compute(hashPwArg, pw), 'role': role});
    await log('مستخدم جديد', '$u - $role');
  }

  Future<void> setUserPassword(String u, String pw) async {
    if (pw.length < 4) throw const FormatException('كلمة السر قصيرة.');
    await db.update('users', {'password': await compute(hashPwArg, pw)}, where: 'user_id=?', whereArgs: [u]);
    await log('تغيير كلمة سر مستخدم', u);
  }

  Future<void> deleteUser(String u) async {
    if (u == 'admin') throw const FormatException('مينفعش تحذف المدير.');
    await db.delete('users', where: 'user_id=?', whereArgs: [u]);
    await log('حذف مستخدم', u);
  }

  /// دور مستخدم موجود (للدخول السريع المحفوظ) — null لو اتحذف
  Future<String?> roleOf(String user) async {
    final r = await db.query('users', where: 'user_id=?', whereArgs: [user]);
    if (r.isEmpty) return null;
    return r.first['user_id'] == 'admin' ? roleAdmin : (r.first['role'] ?? roleAdmin).toString();
  }

  /// دخول مستخدم (مدير أو محاسب أو أمين مخزن) — بيرجّع الدور أو null
  Future<String?> login(String user, String pw) async {
    final r = await db.query('users', where: 'user_id=?', whereArgs: [user.trim().isEmpty ? 'admin' : user.trim()]);
    if (r.isEmpty) return null;
    final ok = await compute(checkPwArgs, [r.first['password'].toString(), pw]);
    if (!ok) return null;
    who = r.first['user_id'].toString();
    if (needsRehash(r.first['password'].toString())) {
      // نحدّث الكلمة لنسخة أسرع في الخلفية (من غير ما نأخّر الدخول)
      compute(hashPwArg, normPw(pw)).then((h) => db.update('users', {'password': h}, where: 'user_id=?', whereArgs: [who]), onError: (_) => 0);
    }
    return r.first['user_id'] == 'admin' ? roleAdmin : (r.first['role'] ?? roleAdmin).toString();
  }

  // ------------------------------------------------------------ مصروف
  Future<void> addExpense(String item, double amount, {String notes = '', String? date}) async {
    if (item.trim().isEmpty) throw const FormatException('اكتب بند المصروف.');
    if (amount <= 0) throw const FormatException('المبلغ لازم يكون أكبر من صفر.');
    await db.insert('expenses', {'item_name': item.trim(), 'amount': amount, 'exp_date': date ?? isoDate(today()), 'notes': notes});
    await log('مصروف', '${item.trim()} ${fmtMoney(amount)}');
  }

  Future<int> addProduct(String name, {double buy = 0, double sell = 0, int qty = 0, String category = ''}) async {
    final nm = name.trim();
    if (nm.isEmpty) throw const FormatException('اكتب اسم الصنف.');
    if (buy < 0 || sell < 0) throw const FormatException('الأسعار مينفعش تبقى بالسالب.');
    if (qty < 0) throw const FormatException('الرصيد الافتتاحي مينفعش يبقى بالسالب.');
    return db.transaction<int>((tx) async {
      final dup = await productByName(nm, tx);
      if (dup != null && normAr((dup['name'] ?? '').toString()).trim() == normAr(nm).trim()) {
        throw const FormatException('الصنف ده موجود قبل كده.');
      }
      final id = await tx.insert('products', {
        'name': nm, 'category': category, 'buy_price': buy, 'sell_price': sell, 'qty': 0, 'min_qty': 3,
        'code': await nextCode('P', 'products', 'code', tx),
      });
      if (qty > 0) await stockMoveIn(tx, id, qty, 'رصيد افتتاحي', allowNeg: true);
      await logIn(tx, 'إضافة صنف', nm);
      return id;
    });
  }

  Future<int> addRep(String type, String name, {String phone = ''}) async {
    if (name.trim().isEmpty) throw const FormatException('اكتب الاسم.');
    if ((await db.query('representatives', where: 'type=? AND name=?', whereArgs: [type, name.trim()])).isNotEmpty) throw FormatException('$name موجود قبل كده.');
    final id = await db.insert('representatives', {'type': type, 'name': name.trim(), 'phone': phone, 'code': await nextCode('R', 'representatives', 'code')});
    await log('إضافة $type', name.trim());
    return id;
  }

  Future<void> addPartner(String name, double capital, double pct) async {
    if (name.trim().isEmpty) throw const FormatException('اكتب اسم المساهم.');
    await db.insert('partners', {'name': name.trim(), 'capital': capital, 'share_percent': pct, 'code': await nextCode('M', 'partners', 'code')});
    await log('إضافة مساهم', name.trim());
  }

  Future<void> addSupplier(String name, {String phone = ''}) async {
    if (name.trim().isEmpty) throw const FormatException('اكتب اسم المورد.');
    if ((await db.query('suppliers', where: 'name=?', whereArgs: [name.trim()])).isNotEmpty) throw const FormatException('المورد ده موجود قبل كده.');
    await db.insert('suppliers', {'name': name.trim(), 'phone': phone, 'code': await nextCode('S', 'suppliers', 'code')});
    await log('إضافة مورد', name.trim());
  }

  /// أرباح المساهمين: صافي = تحصيلات - مصروفات - تكلفة تالف... مقسّم على النسب
  Future<Map<String, Object?>> profitSummary() async {
    final col = (await db.rawQuery('SELECT IFNULL(SUM(amount_paid),0) s FROM payments')).first['s'] as num;
    final exp = (await db.rawQuery('SELECT IFNULL(SUM(amount),0) s FROM expenses')).first['s'] as num;
    final dmg = (await db.rawQuery('SELECT IFNULL(SUM(cost),0) s FROM damages')).first['s'] as num;
    final sup = (await db.rawQuery('SELECT IFNULL(SUM(paid),0) s FROM suppliers_invoices')).first['s'] as num;
    final sup2 = (await db.rawQuery('SELECT IFNULL(SUM(amount),0) s FROM supplier_payments')).first['s'] as num;
    final net = col.toDouble() - exp.toDouble() - dmg.toDouble() - sup.toDouble() - sup2.toDouble();
    final parts = await db.query('partners');
    return {
      'collected': col, 'expenses': exp, 'damages': dmg, 'suppliers': sup.toDouble() + sup2.toDouble(), 'net': net,
      'partners': [for (final p in parts) {'name': p['name'], 'pct': p['share_percent'], 'capital': p['capital'], 'share': r2(net * ((p['share_percent'] ?? 0) as num).toDouble() / 100)}],
    };
  }
}
