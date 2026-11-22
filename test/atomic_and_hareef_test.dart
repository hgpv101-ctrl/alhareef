// اختبارات على قاعدة بيانات حقيقية (sqlite عن طريق ffi). التشغيل: flutter test
// على ويندوز/لينكس لازم sqlite3 يكون متاح لـ sqflite_common_ffi.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareef_app/core/utils.dart';
import 'package:hareef_app/data/db.dart';
import 'package:hareef_app/data/hareef_brain.dart';
import 'package:hareef_app/data/ops.dart';
import 'package:hareef_app/data/stock.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

late Directory tmp;
late AppDb db;

Future<double> paidSum(String code) async =>
    ((await db.db.rawQuery('SELECT IFNULL(SUM(amount_paid),0) s FROM payments WHERE customer_code=?', [code])).first['s'] as num).toDouble();

Future<int> count(String table) async => (await db.db.rawQuery('SELECT COUNT(*) n FROM $table')).first['n'] as int;

Future<String> newCustomer({double total = 24000, double down = 8000, int months = 12, String name = 'محمود السيد'}) =>
    db.addCustomer({'name': name, 'item': 'غسالة', 'total': total, 'down': down, 'months': months});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hareef_t');
    AppDb.licenseEnforced = false;
    db = await AppDb.open('${tmp.path}/t.db');
    await db.warmSettings();
  });
  tearDown(() async {
    await db.db.close();
    await tmp.delete(recursive: true);
  });

  group('العمليات ذرّية', () {
    test('تحصيل: بيتسجّل ويتحدّث المتبقي ومش بيتعلّق', () async {
      final c = await newCustomer();
      await db.addPayment(c, 1500).timeout(const Duration(seconds: 5));
      expect(await paidSum(c), 8000 + 1500);
      final f = (await db.financials(code: c)).first;
      expect(f.remaining, 14500);
    });

    test('تحصيل أكبر من المتبقي بيترفض ومفيش حاجة بتتسجّل', () async {
      final c = await newCustomer();
      await expectLater(db.addPayment(c, 99999), throwsA(isA<FormatException>()));
      expect(await paidSum(c), 8000);
    });

    test('مرتجع بكمية أكبر من المشتراة بيتلغي كله (الإجمالي والمخزن زي ما هم)', () async {
      final pid = await db.addProduct('غسالة', buy: 100, sell: 200, qty: 5);
      final c = await db.addCustomer({
        'name': 'احمد', 'total': 1000, 'down': 0, 'months': 4,
        'items': [{'pid': pid, 'name': 'غسالة', 'qty': 1, 'price': 1000}],
      });
      final before = (await db.financials(code: c)).first.total;
      final qtyBefore = (await db.db.query('products')).first['qty'];
      await expectLater(db.addReturn(c, pid, 3, 100), throwsA(isA<FormatException>()));
      expect((await db.financials(code: c)).first.total, before);
      expect((await db.db.query('products')).first['qty'], qtyBefore);
      expect(await count('returns_log'), 0);
    });

    test('مرتجع سليم: الإجمالي والمخزن وسجل المرتجعات مع بعض', () async {
      final pid = await db.addProduct('غسالة', buy: 100, sell: 200, qty: 5);
      final c = await db.addCustomer({
        'name': 'احمد', 'total': 1000, 'down': 0, 'months': 4,
        'items': [{'pid': pid, 'name': 'غسالة', 'qty': 1, 'price': 1000}],
      });
      await db.addReturn(c, pid, 1, 300);
      expect((await db.financials(code: c)).first.total, 700);
      expect(await count('returns_log'), 1);
    });

    test('خصم أكبر من الإجمالي بيتلغي ومفيش سجل خصم', () async {
      final c = await newCustomer();
      await expectLater(db.addDiscount(c, 999999), throwsA(isA<FormatException>()));
      expect(await count('discounts'), 0);
    });

    test('حذف عميل بيمسح العميل ودفعاته وبنود عقده', () async {
      final c = await newCustomer();
      await db.addPayment(c, 500);
      await db.deleteCustomer(c);
      expect(await count('customers'), 0);
      expect(await count('payments'), 0);
    });

    test('استلام بضاعة بفاتورة: لو فاتورة المورد مرفوضة الرصيد ما يتغيّرش', () async {
      final pid = await db.addProduct('كبة', buy: 10, sell: 20, qty: 1);
      await expectLater(
        db.receiveStock([{'pid': pid, 'qty': 5, 'price': 10}], supplier: 'مورد', invoice: true, paid: 9999),
        throwsA(isA<FormatException>()),
      );
      expect((await db.db.query('products')).first['qty'], 1);
      expect(await count('suppliers_invoices'), 0);
    });

    test('عهدة بصنفين وواحد رصيده ناقص: ولا واحد بيتسجّل', () async {
      await db.addRep('المناديب', 'كريم');
      await db.addProduct('ثلاجة', qty: 10);
      await db.addProduct('تلفزيون', qty: 1);
      await expectLater(
        db.giveCustodyMulti('كريم', [('ثلاجة', 2), ('تلفزيون', 5)]),
        throwsA(isA<FormatException>()),
      );
      expect(await count('custody'), 0);
      final q = {for (final r in await db.db.query('products')) r['name']: r['qty']};
      expect(q['ثلاجة'], 10);
    });

    test('الكاش بيتحدّث بعد أي عملية', () async {
      final c = await newCustomer();
      expect((await db.financials()).first.remaining, 16000);
      await db.addPayment(c, 1000);
      expect((await db.financials()).first.remaining, 15000);
      await db.updateCustomer(c, {'total': 23000});
      expect((await db.financials()).first.remaining, 14000);
    });
  });

  group('الحريف', () {
    Future<String> say(HareefBrain b, String t) async => (await b.handle(t)).text;

    test('تسجيل عميل بالكلام من الجملة الأولى ثم تحصيل', () async {
      final b = HareefBrain();
      var r = await say(b, 'سجل عميل جديد محمود السيد اشترى غسالة بـ 24000 مقدم 8000 على 12 شهر');
      if (r.contains('تليفون')) r = await say(b, 'لأ'); // سؤال الإضافات
      expect(r, contains('أنفّذ'));
      r = await say(b, 'ايوه');
      expect(r, contains('اتسجّل'));
      expect(await count('customers'), 1);

      r = await say(b, 'حصّل 1500 من محمود');
      expect(r, contains('أنفّذ'));
      await say(b, 'ايوه');
      expect(await paidSum((await db.db.query('customers')).first['customer_code'].toString()), 9500);
    });

    test('«أيوه» تانية ما بتكررش التحصيل', () async {
      final c = await newCustomer();
      final b = HareefBrain();
      await say(b, 'حصل 1000 من محمود');
      await say(b, 'ايوه');
      await say(b, 'ايوه');
      expect(await paidSum(c), 9000);
    });

    test('مبلغ أكبر من المتبقي بيتقفل قبل التأكيد', () async {
      await newCustomer();
      final b = HareefBrain();
      final r = await say(b, 'حصل 99999 من محمود');
      expect(r, contains('أكبر من المتبقي'));
      expect(await count('payments'), 1); // المقدم بس
    });

    test('الحذف من غير كلمة سر (الباسورد بس عند الفتح)', () async {
      await newCustomer();
      final b = HareefBrain();
      await say(b, 'احذف العميل محمود');
      final r = await say(b, 'ايوه');
      expect(r, isNot(contains('باسورد')));
      expect(await count('customers'), 0);
    });

    test('الخصم بيتنفّذ من غير كلمة سر', () async {
      await newCustomer();
      final b = HareefBrain();
      await say(b, 'خصم 200 لمحمود');
      final r = await say(b, 'ايوه');
      expect(r, isNot(contains('كلمة سر')));
    });

    test('المحاسب مش بيقدر يحذف عميل', () async {
      await newCustomer();
      final b = HareefBrain(role: 'محاسب');
      final r = await say(b, 'احذف العميل محمود');
      expect(r, contains('صلاحياتك'));
      expect(await count('customers'), 1);
    });
  });
}
