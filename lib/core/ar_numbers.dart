// تحويل الأرقام المكتوبة بالحروف بالعامية المصرية لأرقام: «الف وخمسميه» ← 1500 • «خمسين جنيه» ← 50 جنيه
// الدالة بتشتغل على نص اتعمله normAr قبل كده (من غير همزات ولا تشكيل ولا تاء مربوطة).
// الأرقام الصغيرة لوحدها (واحد، خمسه...) بتفضل زي ما هي عشان ما نبوّظش كلام زي «ضيف خمسه غساله».

const _units = <String, int>{
  'واحد': 1, 'واحده': 1, 'اتنين': 2, 'اثنين': 2, 'اثنان': 2, 'تلاته': 3, 'ثلاثه': 3, 'تلات': 3, 'ثلاث': 3, 'تلت': 3,
  'اربعه': 4, 'اربع': 4, 'خمسه': 5, 'خمس': 5, 'سته': 6, 'ست': 6, 'سبعه': 7, 'سبع': 7, 'تمانيه': 8, 'ثمانيه': 8,
  'تمان': 8, 'ثمان': 8, 'تمنيه': 8, 'تمن': 8, 'تسعه': 9, 'تسع': 9, 'عشره': 10, 'عشر': 10,
};
const _teens = <String, int>{
  'حداشر': 11, 'احداشر': 11, 'اتناشر': 12, 'اثناعشر': 12, 'تلتاشر': 13, 'تلاتاشر': 13, 'اربعتاشر': 14, 'خمستاشر': 15,
  'ستاشر': 16, 'سبعتاشر': 17, 'تمنتاشر': 18, 'تسعتاشر': 19,
};
const _tens = <String, int>{
  'عشرين': 20, 'تلاتين': 30, 'ثلاثين': 30, 'اربعين': 40, 'خمسين': 50, 'ستين': 60, 'سبعين': 70, 'تمانين': 80, 'ثمانين': 80, 'تسعين': 90,
};
const _hund = <String, int>{
  'ميه': 100, 'مايه': 100, 'مئه': 100, 'مائه': 100, 'ميت': 100, 'ميتين': 200, 'مئتين': 200, 'مائتين': 200,
  'تلتميه': 300, 'تلاتميه': 300, 'ثلاثمائه': 300, 'ثلثمائه': 300, 'ربعميه': 400, 'اربعميه': 400, 'اربعمائه': 400,
  'خمسميه': 500, 'خمسمائه': 500, 'ستميه': 600, 'ستمائه': 600, 'سبعميه': 700, 'سبعمائه': 700,
  'تمنميه': 800, 'ثمانميه': 800, 'ثمانمائه': 800, 'تسعميه': 900, 'تسعمائه': 900,
};
const _scale = <String, int>{'الف': 1000, 'الاف': 1000, 'تلاف': 1000, 'مليون': 1000000, 'ملايين': 1000000};
const _dual = <String, int>{'الفين': 2000, 'مليونين': 2000000};
const _half = <String, double>{'نص': 0.5, 'نصف': 0.5, 'ربع': 0.25};
const _money = <String>{'جنيه', 'جنيها', 'جنية', 'ج', 'جنيهات', 'جم'};
// كلمات ليها معنى تاني (ميه = مياه، ميت = اسم مكان): ما بنحوّلهاش غير لو بعدها «جنيه»
const _ambig = <String>{'ميه', 'مايه', 'ميت', 'مئه', 'مائه'};

bool _isNum(String t) =>
    _units.containsKey(t) || _teens.containsKey(t) || _tens.containsKey(t) || _hund.containsKey(t) || _scale.containsKey(t) || _dual.containsKey(t);

String _stripAnd(String t) {
  if (_isNum(t) || _half.containsKey(t)) return t;
  if (t.length > 1 && t.startsWith('و')) {
    final r = t.substring(1);
    if (_isNum(r) || _half.containsKey(r)) return r;
  }
  return t;
}

/// قيمة مجموعة كلمات أرقام متتالية + هل فيها كلمة «قوية» (عشرات/مئات/ألف...) تخلّي التحويل آمن
({double value, bool strong}) _runValue(List<String> run) {
  var total = 0.0, cur = 0.0, lastScale = 1.0;
  var strong = false;
  for (final t in run) {
    if (_units.containsKey(t)) {
      cur += _units[t]!;
    } else if (_teens.containsKey(t)) {
      cur += _teens[t]!;
      strong = true;
    } else if (_tens.containsKey(t)) {
      cur += _tens[t]!;
      strong = true;
    } else if (_hund.containsKey(t)) {
      final v = _hund[t]!;
      strong = true;
      if (v == 100 && cur > 0 && cur < 10) {
        cur = cur * 100;
      } else {
        cur += v;
      }
    } else if (_dual.containsKey(t)) {
      final v = _dual[t]!;
      total += v;
      lastScale = v / 2;
      strong = true;
    } else if (_scale.containsKey(t)) {
      final m = _scale[t]!;
      total += (cur > 0 ? cur : 1) * m;
      cur = 0;
      lastScale = m.toDouble();
      strong = true;
    } else if (_half.containsKey(t)) {
      final f = _half[t]!;
      if (cur == 0 && lastScale >= 1000) {
        total += lastScale * f;
      } else if (cur >= 100 && cur % 100 == 0) {
        cur += 100 * f;
      } else {
        cur += f;
      }
    }
  }
  return (value: total + cur, strong: strong);
}

String _fmt(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

/// بيحوّل كلمات الأرقام في الجملة لأرقام (الباقي بيفضل زي ما هو)
String wordsToDigits(String q) {
  final toks = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final out = <String>[];
  var i = 0;
  while (i < toks.length) {
    final t = _stripAnd(toks[i]);
    if (!_isNum(t)) {
      out.add(toks[i]);
      i++;
      continue;
    }
    var j = i;
    final run = <String>[];
    while (j < toks.length) {
      final u = _stripAnd(toks[j]);
      if (_isNum(u)) {
        run.add(u);
        j++;
      } else if (_half.containsKey(u) && run.isNotEmpty) {
        run.add(u);
        j++;
      } else if (u == 'و' && run.isNotEmpty && j + 1 < toks.length) {
        final nx = _stripAnd(toks[j + 1]);
        if (_isNum(nx) || _half.containsKey(nx)) {
          j++;
        } else {
          break;
        }
      } else {
        break;
      }
    }
    final r = _runValue(run);
    final next = j < toks.length ? toks[j] : '';
    var ok = r.strong;
    if (run.length == 1 && _ambig.contains(run.first)) ok = _money.contains(next);
    if (ok) {
      out.add(_fmt(r.value));
    } else {
      out.addAll(toks.sublist(i, j));
    }
    i = j;
  }
  return out.join(' ');
}
