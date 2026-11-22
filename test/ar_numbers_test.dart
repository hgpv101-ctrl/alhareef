import 'package:flutter_test/flutter_test.dart';
import 'package:hareef_app/core/ar_numbers.dart';
import 'package:hareef_app/core/utils.dart';

String n(String s) => wordsToDigits(normAr(s));

void main() {
  test('تشكيل وتطويل', () {
    expect(normAr('حصّل'), 'حصل');
    expect(normAr('بـ'), 'ب');
  });

  group('أرقام بالحروف', () {
    test('ألوف ومئات', () {
      expect(n('حصل الف وخمسميه من محمود'), 'حصل 1500 من محمود');
      expect(n('الفين وخمسميه'), '2500');
      expect(n('تلات تلاف جنيه'), '3000 جنيه');
      expect(n('مقدم تلتميه وخمسين'), 'مقدم 350');
      expect(n('تلت ميه'), '300');
    });
    test('عشرات وأحداشر', () {
      expect(n('حصل خمسين جنيه من احمد'), 'حصل 50 جنيه من احمد');
      expect(n('على اتناشر شهر'), 'علي 12 شهر');
    });
    test('نص وربع', () {
      expect(n('الف ونص'), '1500');
      expect(n('الفين ونص'), '2500');
      expect(n('مليون ونص'), '1500000');
    });
    test('كلمات عادية ما تتغيرش', () {
      expect(n('مصروف فاتورة ميه'), 'مصروف فاتوره ميه');
      expect(n('عميل في ميت غمر'), 'عميل في ميت غمر');
      expect(n('ضيف خمسه غساله'), 'ضيف خمسه غساله');
    });
    test('ميه + جنيه', () {
      expect(n('حصل ميه جنيه'), 'حصل 100 جنيه');
    });
  });
}
