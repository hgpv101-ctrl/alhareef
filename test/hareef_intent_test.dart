import 'package:flutter_test/flutter_test.dart';
import 'package:hareef_app/core/ar_numbers.dart';
import 'package:hareef_app/core/utils.dart';
import 'package:hareef_app/data/hareef_brain.dart';

String? cls(String text, {bool rep = false}) => HareefBrain.classifyWrite(wordsToDigits(normAr(text)), repMode: rep);

void main() {
  group('تصنيف الأوامر بالعامية المصرية', () {
    final cases = <String, String?>{
      'حصّل 1500 من محمود': 'collect',
      'حصل الف وخمسميه من محمود': 'collect',
      'محمود دفع 500': 'collect',
      'خدت 300 من احمد': 'collect',
      'سجل عميل جديد محمود السيد اشترى غسالة بـ 24000 مقدم 8000 على 12 شهر': 'add_customer',
      'ضيف عميل احمد علي': 'add_customer',
      'مصروف كهرباء 500': 'expense',
      'ضيف 10 غسالة للمخزن': 'stock_in',
      'اسحب 2 غسالة من المخزن': 'stock_out',
      'عهدة لكريم 3 ثلاجة': 'custody_give',
      'سلم كريم عهدة 3 ثلاجة': 'custody_give',
      'رجّع عهدة كريم': 'custody_return',
      'خصم 200 لمحمود': 'discount',
      'اتلف 2 غسالة': 'damage',
      'مرتجع من محمود غسالة': 'return',
      'احذف دفعة محمود': 'delete_payment',
      'امسح العميل محمود': 'delete_customer',
      'غير تليفون محمود لـ 01012345678': 'edit_customer',
      'مدة السماح 3': 'set_grace',
      'ضيف مندوب جديد كريم': 'new_rep',
      'ضيف صنف جديد كبة': 'new_product',
      // استعلامات: مش أوامر تنفيذ
      'كام على محمود': null,
      'مين المتأخرين': null,
      'مين دفع النهارده': null,
      'حصل كام النهارده': null,
      'ملخص النهارده': null,
      'عايز اشوف كشف حساب محمود': null,
      'سعر الكبة كام': null,
    };
    cases.forEach((text, want) {
      test(text, () => expect(cls(text), want));
    });
  });

  test('وضع المندوب: بيع وتحصيل بس', () {
    expect(cls('حصلت 500 من محمود', rep: true), 'collect');
    expect(cls('احذف عميل محمود', rep: true), 'rep_blocked');
    expect(cls('خلصت', rep: true), 'rep_export');
  });

  group('«أيوه» لازم تكون موافقة صريحة', () {
    test('موافقة', () {
      for (final t in ['ايوه', 'تمام', 'اه', 'ماشي', 'تمام يا باشا', 'ايوه نفذ']) {
        expect(HareefBrain.isYes(normAr(t)), isTrue, reason: t);
      }
    });
    test('مش موافقة (فيها تعديل أو رقم)', () {
      for (final t in ['ايوه بس خليها 1000', 'ايوه 500', 'لا', 'تمام بس غير الاسم', '']) {
        expect(HareefBrain.isYes(normAr(t)), isFalse, reason: t);
      }
    });
    test('رفض', () {
      for (final t in ['لا', 'لأ', 'الغي', 'لا غير المبلغ', 'مش عايز']) {
        expect(HareefBrain.isNo(normAr(t)), isTrue, reason: t);
      }
    });
  });
}
