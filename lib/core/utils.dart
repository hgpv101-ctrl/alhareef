// نقل مباشر لدوال المساعدة من sales_system_v61.py
import 'dart:math';

const downLabel = 'مقدم عقد';
const custodyOpen = 'عهدة مستلمة';
const custodyReturned = 'تم الإرجاع';
const custodySold = 'تم البيع';

/// وصف نصي لبنود العقد: «2× غسالة + كبة»
String itemsDesc(List<Map<String, dynamic>> items) => items
    .where((e) => ((e['qty'] ?? 0) as num) > 0)
    .map((e) => (((e['qty'] ?? 1) as num) > 1 ? '${((e['qty']) as num).toInt()}× ' : '') + (e['name'] ?? '').toString())
    .join(' + ');

const _arDigits = '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹٫';
const _enDigits = '01234567890123456789.';

String trDigits(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final i = _arDigits.indexOf(ch);
    b.write(i >= 0 ? _enDigits[i] : ch);
  }
  return b.toString();
}

double parseNum(dynamic text, [double def = 0]) {
  var s = trDigits((text ?? '').toString().trim());
  for (final ch in [',', '،', '٬', ' ']) {
    s = s.replaceAll(ch, '');
  }
  if (s.isEmpty) return def;
  final v = double.tryParse(s);
  if (v == null || v.isNaN || v.isInfinite) {
    throw FormatException("القيمة '$text' مش رقم صحيح");
  }
  return v;
}

String _group(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

String fmtMoney(num? v) {
  try {
    final f = (((v ?? 0).toDouble()) * 100).round() / 100;
    if (f == f.truncateToDouble()) {
      return (f < 0 ? '-' : '') + _group(f.abs().toInt());
    }
    final neg = f < 0;
    final a = f.abs();
    final ip = a.truncate();
    final dec = ((a - ip) * 100).round().toString().padLeft(2, '0');
    return '${neg ? '-' : ''}${_group(ip)}.$dec';
  } catch (_) {
    return '0';
  }
}

String egp(num? v) => '${fmtMoney(v)} جنيه مصري';

// التشكيل والتطويل (حصّل، مـــحمود) كان بيكسر المطابقة، فبنشيله
final _diacritics = RegExp('[\u064B-\u065F\u0670\u0640]');

final _runRe = RegExp(r'([ء-ي])\1{2,}');

String normAr(String? text) {
  var t = trDigits(text ?? '').toLowerCase().replaceAll(_diacritics, '');
  const m = {'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ى': 'ي', 'ة': 'ه', 'ؤ': 'و', 'ئ': 'ي'};
  m.forEach((a, b) => t = t.replaceAll(a, b));
  // تكرار الحرف 3 مرات فأكتر (حصللل، مصروووف) بيتحوّل لحرف واحد
  return t.replaceAllMapped(_runRe, (x) => x[1]!);
}

const _ones = ['', 'واحد', 'اثنان', 'ثلاثة', 'أربعة', 'خمسة', 'ستة', 'سبعة', 'ثمانية', 'تسعة', 'عشرة', 'أحد عشر', 'اثنا عشر', 'ثلاثة عشر', 'أربعة عشر', 'خمسة عشر', 'ستة عشر', 'سبعة عشر', 'ثمانية عشر', 'تسعة عشر'];
const _tens = ['', '', 'عشرون', 'ثلاثون', 'أربعون', 'خمسون', 'ستون', 'سبعون', 'ثمانون', 'تسعون'];
const _hund = ['', 'مائة', 'مائتان', 'ثلاثمائة', 'أربعمائة', 'خمسمائة', 'ستمائة', 'سبعمائة', 'ثمانمائة', 'تسعمائة'];

String _w999(int n) {
  final parts = <String>[];
  final h = n ~/ 100, r = n % 100;
  if (h > 0) parts.add(_hund[h]);
  if (r > 0) {
    if (r < 20) {
      parts.add(_ones[r]);
    } else {
      final t = r ~/ 10, o = r % 10;
      parts.add((o > 0 ? '${_ones[o]} و' : '') + _tens[t]);
    }
  }
  return parts.join(' و');
}

String numWords(int n) {
  if (n == 0) return 'صفر';
  final scales = [
    [1000000000, 'مليار', 'ملياران', 'مليارات'],
    [1000000, 'مليون', 'مليونان', 'ملايين'],
    [1000, 'ألف', 'ألفان', 'آلاف'],
  ];
  final segs = <String>[];
  for (final sc in scales) {
    final div = sc[0] as int;
    final q = n ~/ div;
    n = n % div;
    if (q > 0) {
      if (q == 1) {
        segs.add(sc[1] as String);
      } else if (q == 2) {
        segs.add(sc[2] as String);
      } else if (q <= 10) {
        segs.add('${_w999(q)} ${sc[3]}');
      } else {
        segs.add('${_w999(q)} ${sc[1]}');
      }
    }
  }
  if (n > 0) segs.add(_w999(n));
  return segs.join(' و');
}

String _unit(int n, String few, String many, String plain) {
  final r = n % 100;
  if (r >= 3 && r <= 10) return few;
  if (r >= 11 && r <= 99) return many;
  return plain;
}

String moneyWords(num v) {
  final val = (v.abs() * 100).round() / 100;
  final pounds = val.truncate();
  final pi = ((val - pounds) * 100).round();
  if (pounds == 0 && pi == 0) return 'صفر جنيه';
  final out = <String>[];
  if (pounds > 0) {
    if (pounds == 1) {
      out.add('جنيه مصري واحد');
    } else if (pounds == 2) {
      out.add('جنيهان مصريان');
    } else {
      out.add('${numWords(pounds)} ${_unit(pounds, 'جنيهات مصرية', 'جنيهاً مصرياً', 'جنيه مصري')}');
    }
  }
  if (pi > 0) {
    if (pi == 1) {
      out.add('قرش واحد');
    } else if (pi == 2) {
      out.add('قرشان');
    } else {
      out.add('${numWords(pi)} ${_unit(pi, 'قروش', 'قرشاً', 'قرش')}');
    }
  }
  return 'فقط ${out.join(' و')} لا غير';
}

DateTime? toDate(dynamic s) {
  if (s == null || s.toString().isEmpty) return null;
  try {
    final t = s.toString();
    return DateTime.parse(t.length >= 10 ? t.substring(0, 10) : t);
  } catch (_) {
    return null;
  }
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

String parseDateText(String text) {
  final s = trDigits(text.trim());
  if (s.isEmpty) throw const FormatException('التاريخ فاضي');
  final a = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})$').firstMatch(s);
  if (a != null) {
    return isoDate(DateTime(int.parse(a[1]!), int.parse(a[2]!), int.parse(a[3]!)));
  }
  final b = RegExp(r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})$').firstMatch(s);
  if (b != null) {
    return isoDate(DateTime(int.parse(b[3]!), int.parse(b[2]!), int.parse(b[1]!)));
  }
  throw FormatException("التاريخ '$text' مش صح (اكتبه بالشكل 2026-10-31)");
}

int daysInMonth(int y, int m) => DateTime(y, m + 1, 0).day;

DateTime addMonths(DateTime d, int n) {
  final y = d.year + (d.month - 1 + n) ~/ 12;
  final m = (d.month - 1 + n) % 12 + 1;
  return DateTime(y, m, min(d.day, daysInMonth(y, m)));
}

int countDue(DateTime? firstDue, int months, DateTime asOf, [int grace = 0]) {
  if (firstDue == null || months <= 0) return 0;
  final ref = asOf.subtract(Duration(days: grace));
  if (ref.isBefore(firstDue)) return 0;
  var n = (ref.year - firstDue.year) * 12 + (ref.month - firstDue.month) + 1;
  n = min(max(n, 0), months);
  while (n > 0 && addMonths(firstDue, n - 1).isAfter(ref)) {
    n--;
  }
  while (n < months && !addMonths(firstDue, n).isAfter(ref)) {
    n++;
  }
  return n;
}

/// تقسيط متدرّج "4×100 + 8×300"
List<List<num>> parsePlan(String? text) {
  final t = trDigits(text ?? '').trim();
  if (t.isEmpty) return [];
  final out = <List<num>>[];
  for (var part in t.split(RegExp(r'[+,،;\n]+'))) {
    part = part.trim();
    if (part.isEmpty) continue;
    final m = RegExp(r'^(\d+)\s*[x×*X]\s*(\d+(?:\.\d+)?)$').firstMatch(part);
    if (m == null || int.parse(m[1]!) <= 0 || double.parse(m[2]!) <= 0) {
      throw const FormatException('التقسيط المتدرّج اكتبه كده: 4×100 + 8×300 (عدد الشهور × قيمة القسط)، وتفصل بين المراحل بـ +');
    }
    out.add([int.parse(m[1]!), double.parse(m[2]!)]);
  }
  if (out.fold<int>(0, (s, e) => s + (e[0] as int)) > 120) {
    throw const FormatException('مجموع شهور التقسيط المتدرّج لازم ما يزيدش عن 120 شهر.');
  }
  return out;
}

String planText(List<List<num>> plan) => plan
    .map((e) => '${e[0]}×${e[1] == e[1].truncate() ? e[1].truncate() : e[1]}')
    .join(' + ');

List<double> planSched(String? planTxt, double monthly, int months) {
  List<List<num>> plan;
  try {
    plan = parsePlan(planTxt);
  } catch (_) {
    plan = [];
  }
  if (plan.isNotEmpty) {
    return [for (final e in plan) for (var i = 0; i < (e[0] as int); i++) (e[1] as num).toDouble()];
  }
  return List.filled(max(months, 0), monthly);
}

int bisectRight(List<double> a, double x) {
  var lo = 0, hi = a.length;
  while (lo < hi) {
    final mid = (lo + hi) ~/ 2;
    if (x < a[mid]) {
      hi = mid;
    } else {
      lo = mid + 1;
    }
  }
  return lo;
}

double r2(double v) => (v * 100).round() / 100;

const _ar2lat = {
  'ا': 'A', 'أ': 'A', 'إ': 'A', 'آ': 'A', 'ب': 'B', 'ت': 'T', 'ث': 'T', 'ج': 'G', 'ح': 'H', 'خ': 'K', 'د': 'D', 'ذ': 'Z',
  'ر': 'R', 'ز': 'Z', 'س': 'S', 'ش': 'S', 'ص': 'S', 'ض': 'D', 'ط': 'T', 'ظ': 'Z', 'ع': 'A', 'غ': 'G', 'ف': 'F', 'ق': 'Q',
  'ك': 'K', 'ل': 'L', 'م': 'M', 'ن': 'N', 'ه': 'H', 'ة': 'H', 'و': 'W', 'ي': 'Y', 'ى': 'Y', 'ء': 'A', 'ئ': 'Y', 'ؤ': 'W',
};

String regionPrefix(String? name) {
  var t = (name ?? '').replaceAll(RegExp(r'[ً-ْٰ\s]'), '');
  if (t.startsWith('ال') && t.length > 3) t = t.substring(2);
  final pre = t.split('').map((c) => _ar2lat[c] ?? '').join();
  final p = pre.length > 3 ? pre.substring(0, 3) : pre;
  return p.length >= 2 ? p : 'C';
}

int? codeNum(String? code, String letter) {
  final m = RegExp('^${RegExp.escape(letter)}-?0*(\\d+)\$', caseSensitive: false).firstMatch((code ?? '').trim());
  return m == null ? null : int.parse(m[1]!);
}

/// أرقام عربية-هندية (٠١٢٣) زي الإيصال الورقي
String arDigits(Object? v) => (v ?? '').toString().replaceAllMapped(RegExp(r'\d'), (m) => String.fromCharCode(0x0660 + int.parse(m[0]!)));

/// تاريخ بشكل 2026/04/01
String slashDate(DateTime d) => isoDate(d).replaceAll('-', '/');

/// فرق مسموح بين مجموع التقسيط المتدرّج والمتبقي (1% أو 5 جنيه على الأقل)
bool planTotalOk(double planTotal, double remaining) {
  final tol = remaining * 0.01 > 5 ? remaining * 0.01 : 5.0;
  return (planTotal - remaining).abs() <= tol;
}
