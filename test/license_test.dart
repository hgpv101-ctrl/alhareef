import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareef_app/data/license_codec.dart';
import 'package:hareef_app/data/license_sql.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// مفتاح اختبار منفصل (مش مفتاح الإنتاج)
const testPub = 'JeMhBfbq1Y6iFI0p3hUkv8kzBFYtnxXAPd7UylWFOp4=';
const good = 'HRF1-AEAQEA-YEAUDA-OCAJWQ-FSCAAA-AADW2R-WLI56L-QGNCQ2-VGLQ3H-JHPASS-VTP76A-RBL5GC-G4OK4N-4LJRHP-HOQPVY-W5N4NW-UGP2IY-S7PYYA-O7LL4X-DBTIC5-YAN2TE-XTVJR3-5HBY';
const forged = 'HRF1-AEAQEA-YEAUDA-OCAJWQ-MWGAAA-AAEHVY-DJXMM7-43H4MS-NZRQ6A-XDMNVH-LI7IA5-5SA4RG-MISCNN-SYSBFM-JWAICE-UTM3VZ-LSDPT3-HDO5Q6-IOEC7X-Z6PWJ2-AKJAU3-J75J5W-R2A4';
const tampered = 'AEAQEAYEAUDAOCAJWQFSBAAAAADW2RWLI56LQGNCQ2VGLQ3HJHPASSVTP76ARBL5GCG4OK4N4LJRHPHOQPVYW5N4NWUGP2IYS7PYYAO7LL4XDBTIC5YAN2TEXTVJR35HBY';
const fixToken = 'HRF1-AIAQEA-YEAUDA-OCAJWU-AAAAAA-AAB3MO-3WDP36-L6NOHO-5OIA77-PHIFN4-7NRVFT-6POPIG-6HB2RV-MGAWX4-6SYZEJ-GCNVGO-Y7FF2W-3GTOYU-L67YRP-AHUVOT-TBCOEN-MN6YQS-SPB4';

void main() {
  final dev = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

  group('كود الترخيص', () {
    test('ترخيص سليم', () {
      final p = LicenseCodec.parse(good, pubB64: testPub)!;
      expect(p.sigOk, isTrue);
      expect(p.type, 1);
      expect(LicenseCodec.sameBytes(p.device, dev), isTrue);
      expect(p.issueDay, 2484);
      expect(p.expiryDay, 2849);
      expect(p.serial, 7);
    });
    test('بتتقبل بمسافات وحروف صغيرة ومن غير البادئة', () {
      final p = LicenseCodec.parse(' ${good.toLowerCase()} ', pubB64: testPub)!;
      expect(p.sigOk, isTrue);
      expect(LicenseCodec.parse(good.substring(5), pubB64: testPub)!.sigOk, isTrue);
    });
    test('ترخيص متوقّع بمفتاح تاني مرفوض', () => expect(LicenseCodec.parse(forged, pubB64: testPub)!.sigOk, isFalse));
    test('تعديل حرف واحد يبوّظ التوقيع', () => expect(LicenseCodec.parse(tampered, pubB64: testPub)?.sigOk ?? false, isFalse));
    test('كلام عشوائي', () {
      expect(LicenseCodec.parse('hello', pubB64: testPub), isNull);
      expect(LicenseCodec.parse('', pubB64: testPub), isNull);
    });
    test('كود تصحيح الوقت', () {
      final p = LicenseCodec.parse(fixToken, pubB64: testPub)!;
      expect(p.sigOk && p.type == 2, isTrue);
    });
    test('حساب الأيام', () {
      expect(LicenseCodec.dayOfMs(DateTime.utc(2020, 1, 1).millisecondsSinceEpoch), 0);
      expect(LicenseCodec.dateOfDay(2849), DateTime.utc(2027, 10, 20));
    });
  });

  group('القراءة فقط على مستوى القاعدة', () {
    sqfliteFfiInit();
    test('triggers بتمنع الكتابة وبتسمح بالقراءة والتفعيل', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT)');
      await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
      await db.execute('CREATE TABLE audit_log (id INTEGER PRIMARY KEY, ts TEXT)');
      await LicenseSql.install(db); // بيبدأ مقفول
      await expectLater(db.insert('customers', {'name': 'a'}), throwsA(predicate((e) => e.toString().contains('LICENSE_READONLY'))));
      await db.insert('settings', {'key': 'k', 'value': 'v'}); // مستثناة
      await db.insert('audit_log', {'ts': 'x'}); // مستثناة
      await LicenseSql.setReadOnly(db, false);
      final id = await db.insert('customers', {'name': 'a'});
      await LicenseSql.setReadOnly(db, true);
      await expectLater(db.update('customers', {'name': 'b'}), throwsA(anything));
      await expectLater(db.delete('customers'), throwsA(anything));
      await expectLater(db.transaction((tx) async {
        await tx.insert('customers', {'name': 'c'});
      }), throwsA(anything));
      expect((await db.query('customers')).length, 1); // القراءة شغّالة والبيانات زي ما هي
      expect(id, 1);
      await db.close();
    });
    test('التثبيت مرتين مش بيكرّر ولا بيبوّظ', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('CREATE TABLE t1 (id INTEGER PRIMARY KEY)');
      await LicenseSql.install(db);
      await LicenseSql.install(db);
      final n = (await db.rawQuery("SELECT COUNT(*) c FROM sqlite_master WHERE type='trigger'")).first['c'];
      expect(n, 3);
      await db.close();
    });
  });
}
