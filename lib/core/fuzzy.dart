// تسامح إملائي للعربي: Damerau (OSA) + طيّ الحروف المتشابهة + بادئات ولواحق + تصحيح كلمات الأوامر
import 'dart:math';

class Fuzzy {
  Fuzzy._();

  static final _wsRe = RegExp(r'\s+');
  static final _nonWordRe = RegExp(r'[^ء-يa-z0-9 ]');
  static final _runRe = RegExp(r'([ء-يa-z])\1+');

  /// يشيل أي تكرار حروف (حصللل ← حصل، ايووه ← ايوه). للمقارنة بس.
  static String collapse(String s) => s.replaceAllMapped(_runRe, (m) => m[1]!);

  /// يطوي الحروف اللي بتتلخبط في الكتابة (ص/س، ذ/ز، ظ/ض، ث/س، ط/ت). للمقارنة بس — مش للعرض.
  static String fold(String s) {
    final b = StringBuffer();
    for (final r in collapse(s).runes) {
      switch (String.fromCharCode(r)) {
        case 'ص':
        case 'ث':
          b.write('س');
        case 'ذ':
          b.write('ز');
        case 'ظ':
          b.write('ض');
        case 'ط':
          b.write('ت');
        case 'ة':
          b.write('ه');
        case 'ى':
          b.write('ي');
        default:
          b.writeCharCode(r);
      }
    }
    return b.toString();
  }

  /// Damerau–Levenshtein (OSA): تبديل حرفين جنب بعض = غلطة واحدة. بيستخدم 3 صفوف بس وبيخرج بدري لو عدّى [maxD].
  static int osa(String a, String b, [int maxD = 99]) {
    if (a == b) return 0;
    final n = a.length, m = b.length;
    if ((n - m).abs() > maxD) return maxD + 1;
    if (n == 0) return m;
    if (m == 0) return n;
    var p2 = List<int>.filled(m + 1, 0);
    var p1 = List<int>.generate(m + 1, (j) => j);
    var cur = List<int>.filled(m + 1, 0);
    for (var i = 1; i <= n; i++) {
      cur[0] = i;
      var rowMin = cur[0];
      for (var j = 1; j <= m; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var v = min(min(cur[j - 1] + 1, p1[j] + 1), p1[j - 1] + cost);
        if (i > 1 && j > 1 && a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) && a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
          v = min(v, p2[j - 2] + 1);
        }
        cur[j] = v;
        if (v < rowMin) rowMin = v;
      }
      if (rowMin > maxD) return maxD + 1;
      final t = p2;
      p2 = p1;
      p1 = cur;
      cur = t;
    }
    return p1[m];
  }

  static int _allow(int len) => len >= 8 ? 2 : (len >= 4 ? 1 : 0);

  /// كلمتين متقاربتين إملائياً؟ (الكلمات القصيرة جداً لازم تتطابق بعد الطيّ)
  static bool close(String a, String b) {
    if (a == b) return true;
    final fa = fold(a), fb = fold(b);
    if (fa == fb) return true;
    if (min(fa.length, fb.length) < 4) return false; // الكلمات القصيرة (حسن/حسين) لازم تتطابق
    final d = _allow(max(fa.length, fb.length));
    return osa(fa, fb, d) <= d;
  }

  /// تقطيع نص لكلمات (بعد normAr من برّه)
  static List<String> toks(String s) => s.replaceAll(_nonWordRe, ' ').split(_wsRe).where((w) => w.isNotEmpty).toList();

  // ----------------------------------------------------------- بادئات ولواحق
  static const _prefixes = ['', 'وال', 'بال', 'لل', 'ال', 'و', 'ب', 'ل', 'ف', 'ت'];

  /// لو الكلمة هي [word] بأي بادئة (والـ/بالـ/ل/ب..) ولاحقة (ه/ها/هم/نا/ت/ين...) — تطابق بالكلمة مش بالـ substring
  static bool wordIs(String tok, String word) {
    for (final p in _prefixes) {
      if (p.isNotEmpty && !tok.startsWith(p)) continue;
      final rest = tok.substring(p.length);
      if (rest.length < word.length) continue;
      if (rest == word) return true;
      if (rest.startsWith(word) && rest.length - word.length <= 3) return true;
    }
    return false;
  }

  /// أي كلمة من الجملة هي واحدة من [words] (بدون ما «محصل» تتفهم «حصل»)
  static bool hasWord(List<String> toks, List<String> words) {
    for (final w in words) {
      for (final t in toks) {
        if (wordIs(t, w)) return true;
      }
    }
    return false;
  }

  // ----------------------------------------------------------- مفردات الأوامر
  static const vocab = <String>[
    'حصل', 'حصلت', 'حصلنا', 'تحصيل', 'محصل', 'المحصلين', 'استلمت', 'استلمنا', 'قبضت', 'قبضنا', 'سدد', 'دفع', 'دفعت', 'دفعه',
    'مصروف', 'مصاريف', 'مصروفات', 'نثريه', 'صرفت', 'ملخص', 'متاخر', 'المتاخرين', 'متاخرين', 'مساعده', 'اوامر',
    'عميل', 'العميل', 'جديد', 'جديده', 'اضف', 'ضيف', 'زود', 'سجل', 'عقد', 'مخزن', 'المخزن', 'للمخزن', 'اسحب', 'قطعه', 'رصيد',
    'عهده', 'مندوب', 'المندوب', 'مناديب', 'مورد', 'مساهم', 'منطقه', 'صنف', 'منتج', 'مرتجع', 'تالف', 'اتلف', 'خصم', 'تخفيض',
    'احذف', 'امسح', 'شيل', 'عدل', 'غير', 'حدث', 'تليفون', 'موبايل', 'عنوان', 'بضاعه', 'اشتري', 'اشتريت', 'مقدم', 'اجمالي',
    'فاتوره', 'اعرض', 'وريني', 'النهارده', 'انهارده', 'اليوم', 'ارباح', 'مبيعات', 'توقع', 'زيارات', 'نواقص', 'ناقص', 'اداء',
    'تارجت', 'هدف', 'كشف', 'حساب', 'تذكير', 'نسخه', 'احتياطيه', 'خلصت', 'صدر', 'شهر', 'اقساط', 'قسط', 'الاقساط', 'سعر',
    'الحمايه', 'السالب', 'السماح', 'وقف', 'اسمح', 'امنع', 'رجع', 'ارجع', 'سلم', 'ادي',
  ];
  static final _vocabFold = {for (final v in vocab) fold(v): v};

  /// بيصحّح كلمة واحدة لأقرب كلمة أمر (أو بيرجّعها زي ما هي). [known] = كلمات أسماء معروفة ما تتغيّرش.
  static String fixWord(String w, bool Function(String) known) {
    if (w.length < 3 || RegExp(r'\d').hasMatch(w)) return w;
    if (_vocabFold.containsValue(w) || vocab.contains(w)) return w;
    for (final p in _prefixes) {
      if (p.isNotEmpty && !w.startsWith(p)) continue;
      final rest = w.substring(p.length);
      if (rest.length < 3) continue;
      if (vocab.contains(rest)) return w;
      final fr = fold(rest);
      final direct = _vocabFold[fr];
      if (direct != null && !known(rest)) return p + direct;
      if (rest.length >= 4 && !known(rest)) {
        String? best;
        var bd = 99;
        for (final e in _vocabFold.entries) {
          if (e.key.length < 4) continue;
          final d = _allow(max(fr.length, e.key.length));
          if (d == 0) continue;
          final x = osa(fr, e.key, d);
          if (x <= d && x < bd) {
            bd = x;
            best = e.value;
          }
        }
        if (best != null) return p + best;
      }
    }
    return w;
  }

  /// بيصحّح الأخطاء الإملائية في كلمات الأوامر بس (الأسماء المعروفة ما بتتمسّش)
  static String fixCommand(String q, {bool Function(String)? known}) {
    final k = known ?? (_) => false;
    return toks(q).isEmpty ? q : q.split(_wsRe).map((w) => w.isEmpty ? w : fixWord(w, k)).join(' ');
  }
}
