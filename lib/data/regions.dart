// المناطق: تسجيل، تعديل، وتوزيع على المحصّلين.
// التوزيع بيغيّر «المحصّل» المكتوب على العميل بس — مابيلمسش أي مبلغ أو قسط.
import '../core/engine.dart';
import 'db.dart';

extension RegionOps on AppDb {
  Future<List<Map<String, Object?>>> regionRows() => db.query('regions', orderBy: 'name');

  Future<List<String>> collectorNames() async => [
        for (final r in await db.rawQuery("SELECT DISTINCT name FROM representatives WHERE type='المحصلين' AND IFNULL(name,'')!='' ORDER BY name"))
          r['name'].toString()
      ];

  Future<void> saveRegion({int? id, required String name, String sub = '', String collector = '', String notes = ''}) async {
    name = name.trim();
    if (name.isEmpty) throw const FormatException('اكتب اسم المنطقة.');
    final dup = await db.query('regions', where: 'name=?', whereArgs: [name]);
    if (dup.any((r) => (r['id'] as num).toInt() != id)) throw const FormatException('فيه منطقة بنفس الاسم قبل كده.');
    final data = {'name': name, 'sub_name': sub.trim(), 'collector': collector.trim(), 'notes': notes.trim()};
    if (id == null) {
      await db.insert('regions', data);
      await log('إضافة منطقة', name);
    } else {
      final old = await db.query('regions', where: 'id=?', whereArgs: [id]);
      if (old.isEmpty) throw const FormatException('المنطقة مش موجودة.');
      final oldName = (old.first['name'] ?? '').toString();
      await db.transaction((tx) async {
        await tx.update('regions', data, where: 'id=?', whereArgs: [id]);
        if (oldName != name) {
          // نحدّث اسم المنطقة على العملاء عشان الربط يفضل شغال
          await tx.update('customers', {'region': name}, where: 'region=?', whereArgs: [oldName]);
        }
      });
      await log('تعديل منطقة', oldName == name ? name : '$oldName ← $name');
    }
    bumpData();
  }

  Future<void> deleteRegion(int id) async {
    final r = await db.query('regions', where: 'id=?', whereArgs: [id]);
    if (r.isEmpty) throw const FormatException('المنطقة مش موجودة.');
    final name = (r.first['name'] ?? '').toString();
    final n = _firstCount(await db.rawQuery('SELECT COUNT(*) n FROM customers WHERE region=?', [name]));
    if (n > 0) throw FormatException('فيه $n عميل في منطقة «$name». انقلهم لمنطقة تانية الأول.');
    await db.delete('regions', where: 'id=?', whereArgs: [id]);
    await log('حذف منطقة', name);
    bumpData();
  }

  /// يوزّع عملاء المنطقة على محصّلها المسجّل — بيرجّع عدد العملاء اللي اتحدّثوا
  Future<int> applyRegionCollector(String region) async {
    final r = await db.query('regions', where: 'name=?', whereArgs: [region]);
    final col = r.isEmpty ? '' : (r.first['collector'] ?? '').toString().trim();
    if (col.isEmpty) throw FormatException('مفيش محصّل متسجّل لمنطقة «$region». عدّل المنطقة واختار محصّل الأول.');
    final n = await db.rawUpdate('UPDATE customers SET collector_name=? WHERE region=?', [col, region]);
    await log('توزيع منطقة على محصّل', '$region ← $col ($n عميل)');
    bumpData();
    return n;
  }

  /// عملاء عليهم متبقي، ملهمش محصّل، ولهم مندوب (المرشّحين لخيار «المحصّل = المندوب»)
  Future<List<CustFin>> repCollectorCandidates() async =>
      [for (final c in await financials()) if (c.remaining > 0.004 && c.collector.trim().isEmpty && c.rep.trim().isNotEmpty) c];

  /// بيخلّي المندوب هو المحصّل للعملاء اللي ملهمش محصّل بس — عملية واحدة (يا تكتمل كلها يا تتلغي كلها) وبتتسجّل في السجل
  Future<int> applyRepAsCollector() async {
    final list = await repCollectorCandidates();
    if (list.isEmpty) return 0;
    await db.transaction((tx) async {
      for (final c in list) {
        await tx.update('customers', {'collector_name': c.rep.trim()}, where: 'customer_code=? AND IFNULL(collector_name,\'\')=\'\'', whereArgs: [c.code]);
      }
      await logIn(tx, 'المندوب = المحصّل للعملاء القدام', '${list.length} عميل');
    });
    bumpData();
    return list.length;
  }

  /// يوزّع كل المناطق اللي ليها محصّل. بيرجّع إجمالي العملاء اللي اتحدّثوا
  Future<int> applyAllRegionCollectors() async {
    var total = 0;
    for (final r in await db.query('regions', where: "IFNULL(collector,'')!=''")) {
      total += await db.rawUpdate('UPDATE customers SET collector_name=? WHERE region=?', [r['collector'], r['name']]);
    }
    await log('توزيع كل المناطق على المحصلين', '$total عميل');
    bumpData();
    return total;
  }
}

int _firstCount(List<Map<String, Object?>> rows) => rows.isEmpty ? 0 : ((rows.first['n'] ?? 0) as num).toInt();
