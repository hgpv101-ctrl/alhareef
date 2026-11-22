// فرض «القراءة فقط» على مستوى القاعدة نفسها: triggers بتمنع أي INSERT/UPDATE/DELETE لما الترخيص مش شغّال،
// فمفيش شاشة ولا أمر ولا الحريف يقدر يكتب بالغلط. الجداول المستثناة: settings (للتفعيل) و audit_log و lic_state.
import 'package:sqflite/sqflite.dart';

class LicenseSql {
  LicenseSql._();
  static const exempt = {'settings', 'audit_log', 'lic_state'};

  /// قبل _init (الترقيات بتكتب): نفتح القفل مؤقتاً
  static Future<void> relax(Database db) async {
    try {
      await db.execute('UPDATE lic_state SET ro=0');
    } catch (_) {}
  }

  /// بعد _init: نتأكد إن الجدول والـtriggers موجودين (بتتعمل تاني لو ناقصة أو اتمسحت) والقفل مقفول لحد ما الترخيص يتفحص
  static Future<void> install(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS lic_state (id INTEGER PRIMARY KEY CHECK (id=1), ro INTEGER NOT NULL DEFAULT 1)');
    await db.execute('INSERT OR IGNORE INTO lic_state (id, ro) VALUES (1, 1)');
    await db.execute('UPDATE lic_state SET ro=1');
    final tables = [
      for (final r in await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")) r['name'].toString(),
    ]..removeWhere(exempt.contains);
    final have = {for (final r in await db.rawQuery("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'lic_ro_%'")) r['name'].toString()};
    final want = {
      for (final t in tables) ...['i', 'u', 'd'].map((o) => 'lic_ro_${o}_$t'),
    };
    if (have.length == want.length && have.containsAll(want)) return;
    final b = db.batch();
    for (final n in have) {
      b.execute('DROP TRIGGER IF EXISTS "$n"');
    }
    for (final t in tables) {
      const w = "WHEN (SELECT ro FROM lic_state WHERE id=1)=1 BEGIN SELECT RAISE(ABORT, 'LICENSE_READONLY'); END";
      b.execute('CREATE TRIGGER "lic_ro_i_$t" BEFORE INSERT ON "$t" $w');
      b.execute('CREATE TRIGGER "lic_ro_u_$t" BEFORE UPDATE ON "$t" $w');
      b.execute('CREATE TRIGGER "lic_ro_d_$t" BEFORE DELETE ON "$t" $w');
    }
    await b.commit(noResult: true);
  }

  static Future<void> setReadOnly(Database db, bool ro) => db.execute('UPDATE lic_state SET ro=${ro ? 1 : 0}');
}
