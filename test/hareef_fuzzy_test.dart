import 'package:flutter_test/flutter_test.dart';
import 'package:hareef_app/core/ar_numbers.dart';
import 'package:hareef_app/core/fuzzy.dart';
import 'package:hareef_app/core/utils.dart';
import 'package:hareef_app/data/hareef_brain.dart';

String? cls(String text, {bool rep = false}) => HareefBrain.classifyWrite(HareefBrain.prepare(text), repMode: rep);

void main() {
  group('Damerau / تقارب', () {
    test('تبديل حرفين = غلطة واحدة', () {
      expect(Fuzzy.osa('مصورف', 'مصروف'), 1);
      expect(Fuzzy.osa('محمد', 'محمود'), 1);
      expect(Fuzzy.osa('abc', 'abc'), 0);
    });
    test('خروج بدري', () => expect(Fuzzy.osa('abcdefgh', 'zzzzzzzz', 2) > 2, isTrue));
    test('أسماء مختلفة مش متقاربة', () {
      expect(Fuzzy.close('محمود', 'احمد'), isFalse);
      expect(Fuzzy.close('حسن', 'حسين'), isFalse);
    });
    test('طيّ الحروف', () => expect(Fuzzy.close('حسل', 'حصل'), isTrue));
  });

  group('تصحيح كلمات الأوامر', () {
    final cases = <String, String?>{
      'مصورف كهرباء 500': 'expense',
      'حسل 1500 من محمود': 'collect',
      'حصللل 1500 من محمود': 'collect',
      'مصروووف كهرباء 500': 'expense',
      'ضيف 10 غسالة للمخزن': 'stock_in',
      'ملخس النهارده': null,
    };
    cases.forEach((t, want) => test(t, () => expect(cls(t), want)));
    test('ملخس ← ملخص', () => expect(HareefBrain.prepare('ملخس النهارده'), contains('ملخص')));
    test('الأسماء المعروفة ما بتتمسّش', () {
      expect(HareefBrain.prepare('حسل من حسن', known: (w) => w == 'حسل'), contains('حسل'));
    });
  });

  group('محصّل مش حصّل', () {
    for (final t in ['محصل النهارده', 'محصّل النهارده', 'اداء المحصلين', 'المحصلين']) {
      test(t, () => expect(cls(t), isNull, reason: t));
    }
    test('حصّل لسه أمر', () => expect(cls('حصّل 500 من محمود'), 'collect'));
  });

  group('نعم / لا بالأخطاء', () {
    test('موافقة', () {
      for (final t in ['ايووه', 'اوكيه', 'نعم', 'ايو', 'ماشييي', 'اوك', 'تمام يا باشا']) {
        expect(HareefBrain.isYes(normAr(t)), isTrue, reason: t);
      }
    });
    test('رفض', () {
      for (final t in ['لااا', 'لا', 'الغي', 'بلاش']) {
        expect(HareefBrain.isNo(normAr(t)), isTrue, reason: t);
      }
    });
    test('مش موافقة', () {
      for (final t in ['ايوه بس خليها 1000', 'ايوه 500', 'احمد']) {
        expect(HareefBrain.isYes(normAr(t)), isFalse, reason: t);
      }
    });
  });

  group('أسئلة وأوامر إضافية', () {
    test('استعلامات مش أوامر', () {
      for (final x in ['تليفون محمود', 'مين عليه بكره', 'عملاء منطقة طنطا', 'اكتر عميل متاخر', 'كام عميل عندي']) {
        expect(cls(x), isNull, reason: x);
      }
    });
    test('مرادفات', () {
      expect(cls('دفعنا كهرباء 500'), 'expense');
      expect(cls('محمود جابلي 500'), 'collect');
    });
  });

  test('أرقام بالحروف لسه شغّالة', () => expect(wordsToDigits(normAr('حصل الف وخمسميه')), contains('1500')));
}
