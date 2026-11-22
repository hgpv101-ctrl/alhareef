// عقل الحريف: بيفهم الكلام بالعامية، بيسأل عن الناقص، بيطلب تأكيد، وبينفّذ فعلاً (إضافة/تحصيل/مصروف/مخزن/عهدة/...)
import 'dart:async';
import '../core/ar_numbers.dart';
import '../core/engine.dart';
import '../core/followup.dart';
import '../core/receipt_data.dart';
import '../core/fuzzy.dart';
import 'license.dart';
import '../core/security.dart';
import '../core/utils.dart';
import 'db.dart';
import 'ops.dart';
import 'stock.dart';
import 'regions.dart';
import 'repfile.dart';

class HAct {
  const HAct(this.label, this.kind, [this.a = '', this.b = '']);
  final String label, kind, a, b;
}

/// زرار اختيار باللمس: [label] اللي بيظهر، و[send] النص اللي بيتبعت للحريف لما تضغط عليه. kind: yes / no / opt
class HChoice {
  const HChoice(this.label, this.send, [this.kind = 'opt']);
  final String label, send, kind;
}

class HReply {
  const HReply(this.text, {this.acts = const [], this.secret = false, this.choices = const []});
  final String text;
  final List<HAct> acts;
  final List<HChoice> choices; // أزرار اللمس (تأكيد / تخطى / اختيار)
  final bool secret; // الرسالة الجاية باسورد (تتخبّى)
}

class CRef {
  CRef(this.code, this.name, this.phone, this.remaining, this.monthly, this.region, [this.fin]);
  final String code, name, phone, region;
  final double? remaining, monthly;
  final CustFin? fin;
}

class _Ambig implements Exception {
  _Ambig(this.list);
  final List<CRef> list;
}

class _Sp {
  const _Sp(this.key, this.type, this.ask);
  final String key, type, ask;
}

class _Flow {
  _Flow(this.kind);
  final String kind;
  final Map<String, dynamic> v = {};
  String? waiting;
  List<CRef>? choice;
  String? choiceKey;
}

class _Confirm {
  _Confirm(this.text, this.exec, {this.needPw = false});
  final String text;
  final Future<HReply> Function() exec;
  final bool needPw;
  bool used = false; // التنفيذ مرة واحدة بس مهما اتبعت «أيوه» تاني
}

const _yes = ['ايوه', 'ايوا', 'ايو', 'اه', 'آه', 'نعم', 'تمام', 'ماشي', 'نفذ', 'اكد', 'اوكي', 'اوك', 'اوكيه', 'اوكى', 'ok', 'okay', 'yes', 'موافق', 'اكيد', 'يلا', 'ايوة', 'طيب'];
const _no = ['تخطي', 'تخطى', 'skip', 'لا', 'لأ', 'لاء', 'لاه', 'الغي', 'كنسل', 'بلاش', 'سيب', 'لغي', 'no', 'مش عايز', 'متنفذش', 'وقف', 'مش موافق'];

final _specs = <String, List<_Sp>>{
  'add_customer': [
    _Sp('name', 'text', 'اسم العميل إيه؟'),
    _Sp('item', 'text', 'اشترى إيه؟'),
    _Sp('total', 'num', 'إجمالي البضاعة كام؟'),
    _Sp('down', 'num', 'المقدم كام؟ (اكتب 0 لو مفيش)'),
    _Sp('months', 'months', 'على كام شهر؟ (أو اكتب خطة متدرّجة زي: 4×100 + 8×300)'),
    _Sp('extras', 'extras', 'تحب تضيف تليفون أو منطقة أو مندوب أو محصّل؟ اكتبهم (مثلاً: تليفون 0100.. منطقة طنطا) أو قول «لأ».'),
  ],
  'collect': [_Sp('customer', 'customer', 'تحصّل من مين؟'), _Sp('amount', 'num', 'كام جنيه؟')],
  'expense': [_Sp('item', 'text', 'المصروف ده على إيه؟'), _Sp('amount', 'num', 'كام جنيه؟')],
  'stock_in': [_Sp('product', 'product', 'أي صنف؟'), _Sp('qty', 'int', 'كام قطعة؟')],
  'stock_out': [_Sp('product', 'product', 'أي صنف؟'), _Sp('qty', 'int', 'كام قطعة؟')],
  'new_product': [_Sp('name', 'text', 'اسم الصنف إيه؟'), _Sp('buy', 'num', 'سعر الشراء كام؟ (0 لو مش عارف)'), _Sp('sell', 'num', 'سعر البيع كام؟ (0 لو مش عارف)'), _Sp('qty', 'int', 'الرصيد الافتتاحي كام؟ (0 لو مفيش)')],
  'custody_give': [_Sp('rep', 'rep', 'العهدة لأنهي مندوب؟'), _Sp('product', 'productAny', 'أي صنف؟'), _Sp('qty', 'int', 'كام قطعة؟')],
  'custody_return': [_Sp('rep', 'rep', 'العهدة بتاعة أنهي مندوب؟')],
  'new_region': [_Sp('name', 'text', 'اسم المنطقة إيه؟'), _Sp('subq', 'yn', 'عايز تضيف المنطقة الفرعية (القرية)؟ اضغط نعم أو تخطّي.'), _Sp('sub', 'text', 'اسم المنطقة الفرعية إيه؟')],
  'new_rep': [_Sp('name', 'text', 'اسم المندوب إيه؟')],
  'new_collector': [_Sp('name', 'text', 'اسم المحصّل إيه؟')],
  'new_supplier': [_Sp('name', 'text', 'اسم المورد إيه؟')],
  'new_partner': [_Sp('name', 'text', 'اسم المساهم إيه؟'), _Sp('capital', 'num', 'رأس ماله كام؟'), _Sp('pct', 'num', 'نسبته من الأرباح كام %؟')],
  'supplier_invoice': [_Sp('supplier', 'text', 'فاتورة من أي مورد؟'), _Sp('total', 'num', 'إجمالي الفاتورة كام؟'), _Sp('paid', 'num', 'دفعت منها كام؟ (0 لو لسه)')],
  'supplier_pay': [_Sp('supplier', 'supplier', 'هتسدد لأنهي مورد؟'), _Sp('amount', 'num', 'كام جنيه؟')],
  'return': [_Sp('customer', 'customer', 'المرتجع من أنهي عميل؟'), _Sp('product', 'product', 'أي صنف؟'), _Sp('qty', 'int', 'كام قطعة؟'), _Sp('amount', 'num', 'قيمة المرتجع كام جنيه (هتتخصم من إجمالي العميل)؟')],
  'damage': [_Sp('product', 'product', 'أي صنف اتلف؟'), _Sp('qty', 'int', 'كام قطعة؟')],
  'discount': [_Sp('customer', 'customer', 'الخصم لأنهي عميل؟'), _Sp('amount', 'num', 'قيمة الخصم كام؟')],
  'delete_payment': [_Sp('customer', 'customer', 'أحذف آخر دفعة لأنهي عميل؟')],
  'delete_customer': [_Sp('customer', 'customer', 'أحذف أنهي عميل؟')],
  'edit_customer': [_Sp('customer', 'customer', 'أعدّل بيانات أنهي عميل؟'), _Sp('field', 'field', 'أعدّل إيه؟ (تليفون / عنوان / منطقة / مندوب / محصل / بضاعة)'), _Sp('value', 'text', 'القيمة الجديدة إيه؟')],
  'rep_target': [_Sp('rep', 'rep', 'الهدف لأنهي مندوب؟'), _Sp('amount', 'num', 'الهدف الشهري كام جنيه؟')],
  'sales_invoice': [_Sp('customer', 'customer', 'فاتورة بيع لأنهي عميل؟')],
};

// كلمة السر الوحيدة جوه البرنامج: إعطاء خصم لعميل (غير كده كلمة السر عند فتح التطبيق بس)
const _pwKinds = <String>{};

// كل أمر بيحتاج صلاحية أنهي شاشة (غير كده للمدير بس): الحريف ما بيدّيش حد صلاحية أكبر من صلاحيته في التطبيق
const _kindScreen = <String, String>{
  'add_customer': 'customers', 'edit_customer': 'customers', 'delete_customer': 'customers', 'discount': 'customers',
  'return': 'customers', 'sales_invoice': 'customers', 'collect': 'collection', 'delete_payment': 'collection',
  'expense': 'expenses', 'stock_in': 'products', 'stock_out': 'products', 'new_product': 'products', 'damage': 'products',
  'custody_give': 'custody', 'custody_return': 'custody', 'new_region': 'regions', 'new_supplier': 'suppliers',
  'supplier_invoice': 'suppliers', 'supplier_pay': 'suppliers', 'new_partner': 'partners', 'reminder': 'whatsapp',
};

class HareefBrain {
  HareefBrain({this.repMode = false, this.role = roleAdmin});
  final bool repMode;
  final String role;
  bool _running = false;
  CRef? _last; // آخر عميل اتكلمنا عنه (للأسئلة المتتابعة: «والمتبقي؟» «وتليفونه؟»)
  int _epoch = 0; // بيتغيّر مع الإلغاء عشان أي عملية قديمة علّقت ما تقفلش الشات
  _Flow? _flow;
  _Confirm? _conf;
  _Confirm? _pw;

  bool get busy => _flow != null || _conf != null || _pw != null;
  bool get awaitingSecret => _pw != null;

  static const greeting = 'أهلاً يا باشا 🦅 أنا بنفّذ الأوامر بنفسي. جرّب:\n'
      '• «سجل عميل جديد محمود السيد اشترى غسالة بـ 24000 مقدم 8000 على 12 شهر»\n'
      '• «حصّل 1500 من محمود» • «مصروف كهرباء 500» • «ضيف 10 غسالة للمخزن»\n'
      '• «عهدة لكريم 3 ثلاجة» • «مين المتأخرين» • «كام على أحمد» • «ملخص النهارده»\n'
      'وقول «مساعدة» عشان تشوف كل اللي أعرف أعمله.';

  void cancel() {
    _flow = null;
    _conf = null;
    _pw = null;
    _running = false; // فك القفل: الشات ما يفضلش واقف لو عملية علّقت
    _epoch++;
    _invalidate();
  }

  // ===================================================================== أدوات
  static final _stop = {
    'كام', 'علي', 'على', 'عميل', 'حساب', 'مين', 'ايه', 'اللي', 'ده', 'دي', 'في', 'من', 'الي', 'عن', 'لي', 'ليا', 'يا', 'باشا', 'حصل', 'حصلت',
    'دفع', 'سجل', 'اضف', 'ضيف', 'جديد', 'عايز', 'عاوز', 'اعمل', 'لو', 'سمحت', 'بتاع', 'بتاعه', 'مبلغ', 'جنيه', 'قسط', 'استلمت', 'استلمنا',
    'للعميل', 'مني', 'منه', 'ابعت', 'تذكير', 'رساله', 'كشف', 'الاستاذ', 'استاذ', 'الحاج', 'حاج', 'عم', 'الست', 'ست', 'مستر', 'دكتور', 'ال',
  };

  /// تقارب إملائي بين كلمتين (Damerau + طيّ الحروف المتشابهة). بيتستخدم بس لو مفيش تطابق تام.
  static bool _tokEq(String a, String b) => a == b || (a.length >= 4 && b.length >= 4 && Fuzzy.close(a, b));

  static final _wsRe = RegExp(r'\s+');
  static final _nonWordRe = RegExp(r'[^ء-يa-z0-9 ]');
  static List<String> _toks(String s) => normAr(s).replaceAll(_nonWordRe, ' ').split(_wsRe).where((w) => w.isNotEmpty).toList();

  // أسماء العملاء/الأصناف بتتقطّع لكلمات مرة واحدة بس بدل مع كل رسالة (ده كان بطّأ البحث مع آلاف العملاء)
  static final Map<String, List<String>> _tokCache = {};
  static List<String> _nameToks(String name) {
    if (_tokCache.length > 20000) _tokCache.clear();
    return _tokCache[name] ??= _toks(name);
  }

  /// أقرب أسماء من قايمة لنص. التطابق التام يكسب دايماً، والتقريبي (أخطاء إملائية) بيشتغل بس لو مفيش تطابق تام.
  List<String> _matchNames(String text, List<String> names) {
    final qt = _toks(text).where((w) => !_stop.contains(w)).toList();
    if (qt.isEmpty || names.isEmpty) return [];
    List<String> pick(bool Function(String w, String t) eq) {
      final scored = <(String, int)>[];
      for (final n in names) {
        var sc = 0;
        for (final t in _nameToks(n)) {
          if (qt.any((w) => eq(w, t))) sc++;
        }
        if (sc > 0) scored.add((n, sc));
      }
      if (scored.isEmpty) return [];
      var top = 0;
      for (final e in scored) {
        if (e.$2 > top) top = e.$2;
      }
      return [for (final e in scored) if (e.$2 == top) e.$1];
    }

    final exact = pick((w, t) => w == t);
    return exact.isNotEmpty ? exact : pick(_tokEq);
  }

  // ---- كاش بيانات الحريف (بيتجدد مع أي تغيير في البيانات أو بعد أي تنفيذ أو كل 5 ثواني)
  List<CRef>? _custCache;
  Map<String, List<int>>? _custIdx;
  int _custVer = -1, _custAt = 0;
  final Map<String, (int, int, List<String>)> _listCache = {};

  void _invalidate() {
    _custCache = null;
    _custIdx = null;
    _listCache.clear();
  }

  static int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  Future<List<String>> _cached(String key, Future<List<String>> Function() load) async {
    final c = _listCache[key];
    if (c != null && c.$1 == dataVersion && _nowMs() - c.$2 < 5000) return c.$3;
    final v = await load();
    _listCache[key] = (dataVersion, _nowMs(), v);
    return v;
  }

  Future<List<String>> _prodNames() => _cached('products', () async => [for (final p in await AppDb.i.db.query('products', columns: ['name'])) p['name'].toString()]);
  Future<List<String>> _regionNames() => _cached('regions', () async => [for (final r in await AppDb.i.db.query('regions', columns: ['name'])) r['name'].toString()]);

  Future<List<CRef>> _customers() async {
    final c = _custCache;
    if (c != null && _custVer == dataVersion && _nowMs() - _custAt < 5000) return c;
    final v = await _loadCustomers();
    _custCache = v;
    _custIdx = null;
    _custVer = dataVersion;
    _custAt = _nowMs();
    return v;
  }

  /// فهرس كلمات: كلمة ← أرقام العملاء اللي فيهم الكلمة دي (بيتبني مرة ويتجدد مع البيانات)
  Future<Map<String, List<int>>> _index() async {
    final all = await _customers();
    final ix = _custIdx;
    if (ix != null) return ix;
    final m = <String, List<int>>{};
    for (var i = 0; i < all.length; i++) {
      for (final t in _nameToks(all[i].name)) {
        (m[t] ??= <int>[]).add(i);
      }
    }
    return _custIdx = m;
  }

  Future<List<CRef>> _loadCustomers() async {
    if (repMode) {
      final base = await AppDb.i.db.query('rep_base');
      final news = (await AppDb.i.repEntries(onlyNew: true)).where((e) => e['kind'] == 'sale');
      return [
        for (final s in news) CRef('NEW:${s['uid']}', (s['name'] ?? '').toString(), (s['phone'] ?? '').toString(), null, null, (s['region'] ?? '').toString()),
        for (final b in base) CRef(b['code'].toString(), (b['name'] ?? '').toString(), (b['phone'] ?? '').toString(), (b['remaining'] as num?)?.toDouble(), (b['monthly'] as num?)?.toDouble(), (b['region'] ?? '').toString()),
      ];
    }
    return [for (final c in await AppDb.i.financials()) CRef(c.code, c.name, c.phone, c.remaining, c.monthly, c.region, c)];
  }

  Future<List<CRef>> _findCustomers(String text) async {
    final all = await _customers();
    final ix = await _index();
    // كود مباشر: C12
    final code = RegExp(r'\b([cC])-?0*(\d+)\b').firstMatch(text);
    if (code != null) {
      final m = all.where((c) => codeNum(c.code, 'C') == int.parse(code.group(2)!)).toList();
      if (m.isNotEmpty) return m;
    }
    final qt = <String>{
      for (final w in _toks(text)) ix.containsKey(w) ? w : Fuzzy.fixWord(w, ix.containsKey),
    }.where((w) => !_stop.contains(w)).toList();
    final score = <int, int>{};
    void add(Iterable<int> ids) {
      for (final i in ids) {
        score[i] = (score[i] ?? 0) + 1;
      }
    }

    for (final w in qt) {
      // 1) تطابق تام للكلمة (أو بعد «ال») — لو موجود مبنقرّبش لأي اسم تاني
      final ex = ix[w] ?? (w.startsWith('ال') && w.length > 4 ? ix[w.substring(2)] : null);
      if (ex != null) {
        add(ex);
        continue;
      }
      // 2) تقريبي (غلطة إملائية) بس لو الكلمة مش اسم موجود أصلاً
      if (w.length < 4) continue;
      for (final e in ix.entries) {
        if (_tokEq(w, e.key)) add(e.value);
      }
    }
    if (score.isEmpty) return [];
    var top = 0;
    for (final v in score.values) {
      if (v > top) top = v;
    }
    return [for (final e in score.entries) if (e.value == top) all[e.key]];
  }

  static List<double> _nums(String q) {
    final s = q.replaceAllMapped(RegExp(r'(\d),(\d{3})'), (m) => '${m[1]}${m[2]}');
    return RegExp(r'\d+(?:\.\d+)?').allMatches(s).map((m) => double.parse(m[0]!)).toList();
  }

  static double? _numAfter(String q, List<String> words, {int gap = 14}) {
    final s = q.replaceAllMapped(RegExp(r'(\d),(\d{3})'), (m) => '${m[1]}${m[2]}');
    for (final w in words) {
      final m = RegExp('(?:^|\\s)${RegExp.escape(w)}\\s*(?:[^\\d\\s]{0,$gap}\\s*)?(\\d+(?:\\.\\d+)?)').firstMatch(s);
      if (m != null) return double.parse(m.group(1)!);
    }
    return null;
  }

  static final _kw = ['اشتري', 'اشتريت', 'اشترت', 'اشتروا', 'ب', 'بسعر', 'باجمالي', 'اجمالي', 'الاجمالي', 'مقدم', 'المقدم', 'علي', 'على', 'تليفون', 'موبايل', 'رقم', 'منطقه', 'مندوب', 'محصل', 'عنوان', 'ساكن', 'في'];

  static String _after(String q, List<String> starts, {List<String>? stops}) {
    final tk = q.split(RegExp(r'\s+'));
    final st = (stops ?? _kw).toSet();
    for (var i = 0; i < tk.length; i++) {
      if (starts.contains(tk[i])) {
        final out = <String>[];
        for (var j = i + 1; j < tk.length; j++) {
          if (st.contains(tk[j]) || RegExp(r'^\d').hasMatch(tk[j])) break;
          out.add(tk[j]);
        }
        if (out.isNotEmpty) return out.join(' ');
      }
    }
    return '';
  }

  /// الكلمات القصيرة (حرف أو حرفين زي «ل») لازم تكون كلمة لوحدها، وإلا كانت بتطابق أي جملة فيها الحرف ده
  static bool hasAny(String q, List<String> w) {
    List<String>? toks;
    for (final x in w) {
      final n = normAr(x);
      if (n.length <= 2) {
        toks ??= q.split(_wsRe);
        if (toks.contains(n)) return true;
      } else if (q.contains(n)) {
        return true;
      }
    }
    return false;
  }

  bool _has(String q, List<String> w) => hasAny(q, w);

  static final _yesN = _yes.map((e) => Fuzzy.collapse(normAr(e))).toSet();
  static final _noN = _no.map((e) => Fuzzy.collapse(normAr(e))).toSet();
  static final _yesFiller = {'يا', 'باشا', 'كده', 'دلوقتي', 'بسرعه', 'كمان', 'تمام', 'ايوه', 'نفذ', 'اه'};

  static bool _isYesWord(String w) {
    final c = Fuzzy.collapse(w);
    if (_yesN.contains(c)) return true;
    return c.length >= 4 && _yesN.any((y) => y.length >= 4 && Fuzzy.close(c, y));
  }

  /// «أيوه» لازم تكون موافقة صريحة وقصيرة (مع تسامح إملائي: ايووه، ماشيي، اوكيه). أي جملة فيها رقم أو كلام زيادة («ايوه بس خليها 1000») مش موافقة — بنسأل تاني بدل ما ننفّذ حاجة مختلفة
  static bool isYes(String q) {
    final words = q.split(_wsRe).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty || words.length > 3) return false;
    if (RegExp(r'\d').hasMatch(q)) return false;
    if (!_isYesWord(words.first)) return false;
    return words.skip(1).every((w) => _isYesWord(w) || _yesFiller.contains(Fuzzy.collapse(w)));
  }

  static bool isNo(String q) {
    final c = Fuzzy.collapse(q.trim());
    if (_noN.any((y) => c == y || c.startsWith('$y '))) return true;
    final first = c.split(_wsRe).first;
    return first.length >= 4 && _noN.any((y) => y.length >= 4 && !y.contains(' ') && Fuzzy.close(first, y));
  }

  bool _isYes(String q) => isYes(q);
  static bool _isCancelWord(String q) => const {'الغي', 'كنسل', 'لغي', 'وقف'}.contains(Fuzzy.collapse(q.trim()));
  bool _isNo(String q) => isNo(q);

  // ===================================================================== المدخل
  Future<HReply> handle(String raw) async {
    // مفيش عمليتين في نفس الوقت (ده اللي كان بيعمل تكرار لو المستخدم بعت تاني والأولى لسه شغّالة)
    if (_running) return const HReply('⏳ لسه بنفّذ اللي قبل كده، استنى لحظة (أو اضغط زرار الإلغاء فوق).');
    _running = true;
    final ep = ++_epoch;
    try {
      final r = await _handle(raw);
      if (ep != _epoch) {
        // اتلغت وإحنا شغّالين: منسيبش أي حالة معلّقة
        _flow = null;
        _conf = null;
        _pw = null;
        return const HReply('العملية دي كنت لغيتها — لو كانت تسجيل راجع الحالة الأول قبل ما تعيد الأمر.');
      }
      return await _attachChoices(r);
    } finally {
      if (ep == _epoch) _running = false;
    }
  }

  /// أزرار اللمس حسب حالة المحادثة: تأكيد/إلغاء، تخطّي، اختيار منطقة/مندوب/محصّل/صنف، أرقام جاهزة...
  Future<HReply> _attachChoices(HReply r) async {
    if (r.choices.isNotEmpty || _pw != null) return r;
    List<HChoice> ch = const [];
    try {
      if (_conf != null && !_conf!.used) {
        ch = const [HChoice('✅ أيوه نفّذ', 'ايوه', 'yes'), HChoice('❌ لأ ألغي', 'لا', 'no')];
      } else if (_flow != null) {
        final f = _flow!;
        if (f.choice != null) {
          ch = [for (var i = 0; i < f.choice!.length && i < 8; i++) HChoice('${f.choice![i].name}${f.choice![i].remaining == null ? '' : ' — ${fmtMoney(f.choice![i].remaining)}'}', '${i + 1}')];
        } else {
          final sp = f.waiting == null ? null : _specs[f.kind]?.where((e) => e.key == f.waiting).firstOrNull;
          if (sp != null) ch = await _optionsFor(f, sp);
        }
        if (ch.isNotEmpty || f.choice != null) ch = [...ch, const HChoice('✖️ إلغاء', 'الغي', 'no')];
      }
    } catch (_) {}
    return ch.isEmpty ? r : HReply(r.text, acts: r.acts, secret: r.secret, choices: ch);
  }

  Future<List<HChoice>> _optionsFor(_Flow f, _Sp sp) async {
    List<HChoice> names(List<String> l, String prefix, [int max = 10]) => [for (final n in l.take(max)) HChoice(n, '$prefix$n')];
    switch (sp.type) {
      case 'extras':
        final rg = await _regionNames();
        return [
          const HChoice('⏭️ تخطّي', 'لا', 'no'),
          ...names(rg, 'منطقة ', 6),
          ...names(await _names('المناديب'), 'مندوب ', 4),
          ...names(await _names('المحصلين'), 'محصل ', 4),
        ];
      case 'yn':
        return const [HChoice('نعم', 'ايوه', 'yes'), HChoice('⏭️ تخطّي', 'لا', 'no')];
      case 'opt':
        return const [HChoice('⏭️ تخطّي', 'لا', 'no')];
      case 'months':
        return [for (final m in const [3, 6, 10, 12, 18, 24]) HChoice('$m شهر', '$m')];
      case 'int':
        return [for (final n in const [1, 2, 3, 5, 10]) HChoice('$n', '$n')];
      case 'product':
      case 'productAny':
        return names(await _prodNames(), '', 12);
      case 'rep':
        return names(await _names('المناديب'), '');
      case 'supplier':
        return names(await _names('الموردين'), '');
      case 'field':
        return [for (final x in const ['تليفون', 'عنوان', 'منطقة', 'مندوب', 'محصل', 'بضاعة']) HChoice(x, x)];
      case 'num':
        if (sp.key == 'total' && f.v['_listPrice'] != null) return const [HChoice('💡 بسعر المخزن', 'بسعر المخزن')];
        if (sp.key == 'down' || sp.key == 'buy' || sp.key == 'sell' || sp.key == 'paid') return const [HChoice('0', '0')];
        return const [];
    }
    return const [];
  }

  /// بيجهّز الجملة للفهم: تطبيع + أرقام بالحروف + تصحيح إملائي لكلمات الأوامر (الأسماء المعروفة ما بتتمسّش)
  static String prepare(String raw, {bool Function(String)? known}) =>
      Fuzzy.fixCommand(wordsToDigits(normAr(raw.trim())).trim(), known: known).trim();

  Future<HReply> _handle(String raw) async {
    final text = raw.trim();
    // الأرقام المكتوبة بالحروف («الف وخمسميه») بتتحوّل لأرقام قبل الفهم
    final q = wordsToDigits(normAr(text)).trim();
    try {
      if (_pw != null) return _handlePw(text);
      if (_conf != null) return _handleConfirm(q);
      if (_flow != null) {
        if (_isNo(q) && (!const {'extras', 'subq'}.contains(_flow!.waiting) || _isCancelWord(q))) {
          _flow = null;
          return const HReply('تمام، لغيت العملية ✅');
        }
        return _continueFlow(text, q);
      }
      // جملة جديدة: نصحّح أخطاء كلمات الأوامر (مصورف ← مصروف، حسل ← حصل، ملخس ← ملخص)
      final ix = await _index();
      final fq = Fuzzy.fixCommand(q, known: ix.containsKey);
      if (_has(fq, ['مساعده', 'تعرف تعمل', 'ايه اللي تعرفه', 'ايه الاوامر', 'اوامر'])) return _help();
      final w = await _tryWrite(text, fq);
      if (w != null) return w;
      // الاستعلامات للقراءة بس فمهلتها آمنة (مفيش حاجة بتتكرر لو قطعناها)
      return await _query(text, fq).timeout(const Duration(seconds: 25));
    } on TimeoutException {
      return const HReply('⏳ الاستعلام اتأخر أوي. جرّب تاني، ولو فضل كده اقفل التطبيق وافتحه.');
    } on FormatException catch (e) {
      _flow = null;
      _conf = null;
      return HReply('⚠️ ${e.message}');
    } catch (e) {
      cancel();
      return HReply('حصلت مشكلة: $e');
    }
  }

  HReply _help() => HReply(repMode
      ? 'في وضع ${'المندوب'} أقدر:\n• «سجل عميل جديد ...» (بيع)\n• «حصّلت 500 من محمود»\n• «ملخص شغلي» / «كام بعت وكام حصّلت»\n• «خلصت» أو «صدّر الملف» عشان أجهّز الملف وتبعته للمالك'
      : 'أقدر أنفّذ:\n'
          '👤 سجل عميل جديد • عدّل بيانات عميل • احذف عميل/دفعة\n'
          '💰 حصّل X من فلان • خصم لعميل • مرتجع\n'
          '📦 ضيف/اسحب كمية • صنف جديد • تالف\n'
          '🚚 عهدة لمندوب • رجّع عهدة • مندوب/محصل/مورد/مساهم/منطقة جديدة\n'
          '💸 مصروف • فاتورة مورد • سدد مورد • هدف مندوب\n'
          '📊 كام على فلان • مين المتأخرين • ملخص • توقع • خطة الزيارات • أداء مندوب • تحصيل محصل • أرباح • رصيد صنف\n'
          '📅 تحصيل الشهر / تحصيل السنة كلها / تحصيل الشهر لفلان / تحصيل الشهر منطقة طنطا\n'
          '📍 عملاء منطقة طنطا • عملاء المندوب فلان • تليفون/عنوان فلان • مبيعات/مصروفات النهارده • مين عليه بكره\n'
          '🗂️ افتح المخزن / المناطق / المصروفات / الموردين / المساهمين / العهدة\n'
          '💬 ابعت تذكير لفلان • فاتورة بيع لفلان • نسخة احتياطية\n'
          '👆 كل الأسئلة والتأكيدات ليها أزرار تلمسها (نعم / لأ / تخطّي / اختيار) من غير ما تكتب.\n'
          '⚙️ اسمح بالسالب / مدة السماح 3\n'
          'وأي حاجة ناقصة بسألك عليها، وقبل التنفيذ بطلب تأكيد .');

  // ===================================================================== أوامر التنفيذ
  /// بيحدّد نوع الأمر من الجملة (من غير أي وصول لقاعدة البيانات) — static عشان نقدر نختبره بجمل كتير.
  /// بيرجّع null لو الجملة مش أمر تنفيذ (يعني استعلام أو كلام عادي).
  static String? classifyWrite(String q, {bool repMode = false}) {
    bool a(List<String> w) => hasAny(q, w);
    final isQ = a(['مين ', 'كام ', 'ايه ', 'اعرض', 'وريني', 'هات ', 'مين?']) && !a(['سجل', 'اضف', 'ضيف', 'زود']);
    if (repMode) {
      if (a(['خلصت', 'صدر', 'ابعت الملف', 'ارسل الملف', 'جهز الملف'])) return 'rep_export';
      if (a(['عميل جديد', 'بيع جديد', 'بعت ل', 'اشتري', 'سجل عميل', 'اضف عميل']) && !isQ) return 'add_customer';
      if (Fuzzy.hasWord(Fuzzy.toks(q), ['حصلت', 'حصل', 'استلمت', 'قبضت', 'دفع', 'سدد']) && !isQ) return 'collect';
      if (a(['مصروف', 'مخزن', 'عهده', 'مورد', 'مساهم', 'احذف', 'امسح', 'خصم', 'مرتجع'])) return 'rep_blocked';
      return null;
    }
    if (a(['نسخه احتياطيه', 'باك اب', 'backup'])) return 'backup';
    if (a(['اسمح بالسالب', 'امنع السالب', 'السالب'])) return 'set_neg';
    if (RegExp(r'(?:مده|مدت|ايام) السماح\D*(\d+)').hasMatch(q)) return 'set_grace';
    if (a(['ابعت تذكير', 'ذكر', 'تذكير ل', 'ارسل تذكير'])) return 'reminder';
    if (a(['فاتوره بيع'])) return 'sales_invoice';
    if (a(['عميل جديد', 'سجل عميل', 'اضف عميل', 'ضيف عميل', 'عقد جديد', 'بيع جديد']) && !isQ) return 'add_customer';
    if (a(['منطقه جديده', 'اضف منطقه', 'ضيف منطقه', 'سجل منطقه'])) return 'new_region';
    if (a(['مندوب جديد', 'اضف مندوب', 'ضيف مندوب', 'سجل مندوب'])) return 'new_rep';
    if (a(['محصل جديد', 'اضف محصل', 'ضيف محصل', 'سجل محصل'])) return 'new_collector';
    if (a(['مورد جديد', 'اضف مورد', 'ضيف مورد', 'سجل مورد'])) return 'new_supplier';
    if (a(['مساهم جديد', 'اضف مساهم', 'ضيف مساهم', 'سجل مساهم'])) return 'new_partner';
    if (a(['صنف جديد', 'منتج جديد', 'اضف صنف', 'ضيف صنف', 'سجل صنف'])) return 'new_product';
    if (a(['فاتوره مورد', 'فاتوره من مورد', 'فاتوره من'])) return 'supplier_invoice';
    if (a(['سدد مورد', 'سداد مورد', 'ادفع للمورد', 'دفعت للمورد', 'سددت للمورد'])) return 'supplier_pay';
    if (a(['رجع عهده', 'ارجع عهده', 'ارجاع عهده', 'استلمت عهده'])) return 'custody_return';
    // «عهدة لكريم 3 ثلاجة» (من غير فعل) بتتفهم برضه لو فيها رقم
    if (a(['عهده']) && (a(['ادي', 'اديت', 'سلم', 'سلمت', 'اعطي', 'سجل', 'ضيف', 'اضف']) || RegExp(r'\d').hasMatch(q)) && !isQ) return 'custody_give';
    if (a(['هدف', 'تارجت']) && a(['مندوب', 'حدد', 'سجل', 'ضيف', 'اضف', 'خلي']) && !isQ) return 'rep_target';
    if (a(['مرتجع', 'رجع بضاعه', 'رجعلي', 'ارجاع بضاعه']) && !isQ) return 'return';
    if (a(['تالف', 'اتلف', 'اتلفت', 'تلف']) && !isQ) return 'damage';
    if (a(['خصم', 'تخفيض']) && !isQ) return 'discount';
    if (a(['احذف', 'امسح', 'شيل']) && a(['دفعه', 'قسط', 'تحصيل'])) return 'delete_payment';
    if (a(['احذف', 'امسح', 'شيل']) && a(['عميل'])) return 'delete_customer';
    if (a(['عدل', 'غير', 'حدث']) && a(['تليفون', 'موبايل', 'رقم', 'عنوان', 'منطقه', 'مندوب', 'محصل', 'بضاعه']) && !isQ) return 'edit_customer';
    if (a(['مصروف', 'مصاريف', 'نثريه', 'صرفت', 'صرفنا', 'دفعنا', 'دفعت فاتوره', 'دفعت ايجار']) && !isQ) return 'expense';
    if (a(['ضيف', 'زود', 'اضف', 'وارد', 'دخل']) && a(['مخزن', 'للمخزن', 'رصيد', 'قطعه', 'قطع'])) return 'stock_in';
    if (a(['اسحب', 'نزل', 'اخصم', 'صرف من المخزن', 'خرج']) && a(['مخزن', 'من المخزن', 'قطعه', 'قطع', 'رصيد'])) return 'stock_out';
    // «حصل/دفع» لازم تكون كلمة (بأي بادئة/لاحقة) مش جزء من «محصّل/المحصلين» — ده كان بيفتح التحصيل غلط
    final tk = Fuzzy.toks(q);
    if ((Fuzzy.hasWord(tk, ['حصل', 'حصلت', 'استلمت', 'استلمنا', 'قبضت', 'قبضنا', 'سدد', 'دفع', 'دفعلي', 'دفعوا']) ||
            a(['سجل دفعه', 'دفعه من', 'خدت من', 'خدنا من', 'جابلي', 'جابلنا', 'اداني', 'ادالي', 'ادانا']) ||
            RegExp(r'(?:خدت|خدنا|اخدت)\s+\d+').hasMatch(q)) &&
        !isQ &&
        !a(['مين'])) {
      return 'collect';
    }
    return null;
  }

  bool _allowed(String kind) {
    if (repMode) return true;
    if (role == roleAdmin) return true;
    final scr = _kindScreen[kind];
    return scr != null && canOpen(role, scr);
  }

  Future<HReply?> _tryWrite(String text, String q) async {
    final kind = classifyWrite(q, repMode: repMode);
    if (kind == null) return null;
    // الترخيص مش شغّال (منتهي/غير مفعّل/وقت متلاعب فيه): قراءة فقط — النسخة الاحتياطية بس مسموحة
    if (kind != 'backup' && kind != 'rep_blocked' && !LicenseGuard.i.canWrite) return const HReply('🔒 ${LicenseGuard.readOnlyText}');
    switch (kind) {
      case 'rep_export':
        return const HReply('اضغط الزرار تحت وأنا أجهّز الملف وأفتح المشاركة 👇', acts: [HAct('📤 تصدير وإرسال للمالك', 'rep_export')]);
      case 'rep_blocked':
        return const HReply('الأمر ده من صلاحيات المالك — في وضع المندوب أقدر أسجّل بيع وتحصيل بس.');
    }
    // أوامر الإعدادات والنسخ الاحتياطي: للمدير بس
    if (const {'backup', 'set_neg', 'set_grace'}.contains(kind)) {
      if (role != roleAdmin) return const HReply('الأمر ده للمدير بس.');
      switch (kind) {
        case 'backup':
          return _doBackup();
        case 'set_neg':
          return _setSetting('allow_negative_stock', !_has(q, ['امنع', 'وقف', 'اقفل']), 'السماح بالرصيد السالب');
        default:
          final gr = RegExp(r'(?:مده|مدت|ايام) السماح\D*(\d+)').firstMatch(q)!;
          return _confirmSimple('أغيّر مدة السماح لـ ${gr.group(1)} يوم؟', () async {
            await AppDb.i.setSetting('grace_days', gr.group(1)!);
            return const HReply('اتغيّرت مدة السماح ✅');
          });
      }
    }
    if (!_allowed(kind)) return const HReply('الأمر ده مش من صلاحياتك في التطبيق 🔒 اطلب من المدير ينفّذه.');
    if (kind == 'reminder') return _reminder(text, q);

    final f = _Flow(kind);
    await _prefill(f, text, q);
    _flow = f;
    return _advance(f);
  }

  /// بيلقط أي معلومة موجودة في الجملة الأولى
  Future<void> _prefill(_Flow f, String text, String q) async {
    final v = f.v;
    final nums = _nums(q);
    switch (f.kind) {
      case 'add_customer': {
        var name = _after(q, ['جديد', 'عميل', 'اسمه', 'اسمها', 'باسم', 'لعميل'],
            stops: ['اشتري', 'اشتريت', 'اشترت', 'اشتروا', 'بسعر', 'باجمالي', 'اجمالي', 'الاجمالي', 'مقدم', 'المقدم', 'تليفون', 'موبايل', 'رقم', 'منطقه', 'مندوب', 'محصل', 'عنوان', 'ساكن', 'ب', 'بمبلغ', 'مبلغ']);
        // شيل كلمات زي "جديد"
        name = name.split(' ').where((w) => !['جديد', 'عميل', 'اسمه', 'اسمها'].contains(w)).join(' ');
        if (name.isNotEmpty) v['name'] = name;
        final item = _after(q, ['اشتري', 'اشتريت', 'اشترت', 'اشتروا', 'بضاعه', 'صنف']);
        if (item.isNotEmpty) v['item'] = item;
        final tot = _numAfter(q, ['ب', 'بسعر', 'باجمالي', 'اجمالي', 'الاجمالي', 'اجماليه', 'مبلغ', 'بمبلغ']);
        if (tot != null) v['total'] = tot;
        final down = _numAfter(q, ['مقدم', 'المقدم', 'بمقدم']);
        if (down != null) v['down'] = down;
        final pm = RegExp(r'(\d+\s*[x×*]\s*\d+(?:\s*\+\s*\d+\s*[x×*]\s*\d+)*)').firstMatch(q);
        if (pm != null) {
          v['plan'] = pm.group(1)!.replaceAll(RegExp(r'\s+'), '');
          v['months'] = parsePlan(v['plan']).fold<int>(0, (s, e) => s + (e[0] as int));
        } else {
          final mm = RegExp(r'(\d+)\s*(?:شهر|شهور|قسط|اقساط)').firstMatch(q) ?? RegExp(r'علي\s*(\d+)').firstMatch(q);
          if (mm != null) v['months'] = int.parse(mm.group(1)!);
        }
        _extras(v, q, await _names('المناديب'), await _names('المحصلين'), await _regionNames());
        break;
      }
      case 'collect': {
        final cs = await _findCustomers(text);
        if (cs.length == 1) v['customer'] = cs.first;
        else if (cs.length > 1) {
          f.choice = cs;
          f.choiceKey = 'customer';
        }
        final amt = _numAfter(q, ['مبلغ', 'بمبلغ', 'حصل', 'حصلت', 'استلمت', 'استلمنا', 'قبضت', 'دفع', 'سدد']) ?? (nums.isNotEmpty ? nums.first : null);
        if (amt != null && amt > 0) v['amount'] = amt;
        break;
      }
      case 'expense': {
        var item = _after(q, ['مصروف', 'مصاريف', 'نثريه', 'صرفت', 'صرفنا', 'علي', 'على', 'دفعت'], stops: ['ب', 'بمبلغ', 'مبلغ', 'جنيه']);
        item = item.split(' ').where((w) => !['جديد', 'سجل', 'اضف', 'ضيف'].contains(w)).join(' ');
        if (item.isNotEmpty) v['item'] = item;
        if (nums.isNotEmpty) v['amount'] = nums.first;
        break;
      }
      case 'stock_in':
      case 'stock_out': {
        final prods = await _prodNames();
        final m = _matchNames(text, prods);
        if (m.length == 1) v['product'] = await AppDb.i.productByName(m.first);
        if (nums.isNotEmpty) v['qty'] = nums.first.toInt();
        break;
      }
      case 'new_product': {
        final n = _after(q, ['جديد', 'صنف', 'منتج'], stops: ['سعر', 'بسعر', 'شراء', 'بيع', 'رصيد', 'كميه']);
        if (n.isNotEmpty) v['name'] = n.split(' ').where((w) => w != 'جديد').join(' ');
        final b = _numAfter(q, ['شراء', 'الشراء']);
        if (b != null) v['buy'] = b;
        final s = _numAfter(q, ['بيع', 'البيع', 'بسعر']);
        if (s != null) v['sell'] = s;
        final qt = _numAfter(q, ['رصيد', 'كميه', 'الكميه']);
        if (qt != null) v['qty'] = qt.toInt();
        break;
      }
      case 'custody_give': {
        final reps = await _names('المناديب');
        final r = _matchNames(text, reps);
        if (r.length == 1) v['rep'] = r.first;
        final prods = await _prodNames();
        final pm = _matchNames(text, prods);
        if (pm.length == 1) v['product'] = pm.first;
        if (nums.isNotEmpty) v['qty'] = nums.first.toInt();
        break;
      }
      case 'custody_return': {
        final r = _matchNames(text, await _names('المناديب'));
        if (r.length == 1) v['rep'] = r.first;
        break;
      }
      case 'new_region':
      case 'new_rep':
      case 'new_collector':
      case 'new_supplier': {
        final n = _after(q, ['جديد', 'جديده', 'منطقه', 'مندوب', 'محصل', 'مورد'], stops: ['تليفون', 'موبايل', 'رقم']);
        if (n.isNotEmpty) v['name'] = n.split(' ').where((w) => w != 'جديد' && w != 'جديده').join(' ');
        break;
      }
      case 'new_partner': {
        final n = _after(q, ['جديد', 'مساهم'], stops: ['رأس', 'راس', 'نسبه', 'نسبته']);
        if (n.isNotEmpty) v['name'] = n.split(' ').where((w) => w != 'جديد').join(' ');
        final c = _numAfter(q, ['راس', 'رأس', 'ماله', 'المال']);
        if (c != null) v['capital'] = c;
        final p = _numAfter(q, ['نسبه', 'نسبته']);
        if (p != null) v['pct'] = p;
        break;
      }
      case 'supplier_invoice': {
        final sup = [for (final s in await AppDb.i.db.query('suppliers')) s['name'].toString()];
        final m = _matchNames(text, sup);
        if (m.length == 1) v['supplier'] = m.first;
        else {
          final n = _after(q, ['مورد', 'من'], stops: ['اجمالي', 'بمبلغ', 'مبلغ', 'ب', 'دفعت', 'مدفوع']);
          if (n.isNotEmpty) v['supplier'] = n;
        }
        final t = _numAfter(q, ['اجمالي', 'الاجمالي', 'بمبلغ', 'مبلغ', 'ب']);
        if (t != null) v['total'] = t;
        final pd = _numAfter(q, ['دفعت', 'مدفوع', 'كاش']);
        if (pd != null) v['paid'] = pd;
        break;
      }
      case 'supplier_pay': {
        final sup = [for (final s in await AppDb.i.db.query('suppliers')) s['name'].toString()];
        final m = _matchNames(text, sup);
        if (m.length == 1) v['supplier'] = m.first;
        if (nums.isNotEmpty) v['amount'] = nums.first;
        break;
      }
      case 'return':
      case 'discount':
      case 'delete_payment':
      case 'delete_customer':
      case 'edit_customer':
      case 'sales_invoice': {
        final cs = await _findCustomers(text);
        if (cs.length == 1) v['customer'] = cs.first;
        else if (cs.length > 1) {
          f.choice = cs;
          f.choiceKey = 'customer';
        }
        if (f.kind == 'discount' && nums.isNotEmpty) v['amount'] = nums.first;
        if (f.kind == 'return') {
          final prods = await _prodNames();
          final pm = _matchNames(text, prods);
          if (pm.length == 1) v['product'] = await AppDb.i.productByName(pm.first);
          final amt = _numAfter(q, ['بمبلغ', 'مبلغ', 'قيمه', 'قيمته', 'بقيمه']);
          if (amt != null) v['amount'] = amt;
          final qt = _numAfter(q, ['كميه', 'عدد']) ?? (nums.isNotEmpty && nums.first != amt ? nums.first : null);
          if (qt != null) v['qty'] = qt.toInt();
        }
        if (f.kind == 'edit_customer') {
          const fm = {'تليفون': 'phone', 'موبايل': 'phone', 'رقم': 'phone', 'عنوان': 'address', 'منطقه': 'region', 'مندوب': 'rep', 'محصل': 'collector', 'بضاعه': 'item'};
          for (final e in fm.entries) {
            if (q.contains(e.key)) {
              v['field'] = e.value;
              break;
            }
          }
          final pm = RegExp(r'(?:ل|الي|الى|ب)\s*(0?\d{7,14})').firstMatch(q);
          if (v['field'] == 'phone' && pm != null) v['value'] = pm.group(1);
        }
        break;
      }
      case 'damage': {
        final prods = await _prodNames();
        final pm = _matchNames(text, prods);
        if (pm.length == 1) v['product'] = await AppDb.i.productByName(pm.first);
        if (nums.isNotEmpty) v['qty'] = nums.first.toInt();
        break;
      }
      case 'rep_target': {
        final r = _matchNames(text, await _names('المناديب'));
        if (r.length == 1) v['rep'] = r.first;
        if (nums.isNotEmpty) v['amount'] = nums.last;
        break;
      }
    }
  }

  Future<List<String>> _names(String t) => repMode ? Future.value(<String>[]) : _cached('names:$t', () => AppDb.i.namesOf(t));

  void _extras(Map<String, dynamic> v, String q, List<String> reps, List<String> colls, List<String> regions) {
    final ph = RegExp(r'(?:تليفون|موبايل|رقم|تلفون)\D{0,6}(\d{7,15})').firstMatch(q) ?? RegExp(r'\b(0\d{9,11})\b').firstMatch(q);
    if (ph != null) v['phone'] = ph.group(1);
    // المنطقة بتتدوّر عليها بعد «منطقة/في» أو بعد حرف «ب» ملزوق في الاسم (بطنطا) — مش في الجملة كلها (كان بيخلط الاسم بالمنطقة)
    final qk = Fuzzy.toks(q);
    final mi = qk.indexWhere((w) => w == 'منطقه' || w == 'في');
    final regionText = [
      if (mi >= 0) ...qk.skip(mi + 1),
      for (final w in qk) if (w.length > 3 && w.startsWith('ب') && !w.startsWith('بال')) w.substring(1),
    ].join(' ');
    final rg = regionText.isEmpty ? <String>[] : _matchNames(regionText, regions);
    if (rg.length == 1) v['region'] = rg.first;
    else {
      final r = _after(q, ['منطقه'], stops: _kw.where((k) => k != 'في').toList());
      if (r.isNotEmpty) v['region'] = r;
    }
    final rp = _matchNames(q.contains('مندوب') ? q.substring(q.indexOf('مندوب')) : '', reps);
    if (rp.length == 1) v['rep'] = rp.first;
    else {
      final r = _after(q, ['مندوب']);
      if (r.isNotEmpty) v['rep'] = r;
    }
    final cl = _matchNames(q.contains('محصل') ? q.substring(q.indexOf('محصل')) : '', colls);
    if (cl.length == 1) v['collector'] = cl.first;
    else {
      final r = _after(q, ['محصل']);
      if (r.isNotEmpty) v['collector'] = r;
    }
    final ad = _after(q, ['عنوان', 'ساكن'], stops: ['تليفون', 'موبايل', 'منطقه', 'مندوب', 'محصل']);
    if (ad.isNotEmpty) v['address'] = ad;
  }

  Future<HReply> _continueFlow(String text, String q) async {
    final f = _flow!;
    // اختيار من أكثر من عميل
    if (f.choice != null) {
      final ch = f.choice!;
      CRef? pick;
      final n = int.tryParse(q.replaceAll(RegExp(r'\D'), ''));
      if (n != null && n >= 1 && n <= ch.length) pick = ch[n - 1];
      pick ??= () {
        final m = _matchNames(text, [for (final c in ch) c.name]);
        return m.length == 1 ? ch.firstWhere((c) => c.name == m.first) : null;
      }();
      if (pick == null) return HReply('اختار رقم من القايمة:\n${_list(ch)}');
      f.v[f.choiceKey!] = pick;
      f.choice = null;
      f.waiting = null;
      return _advance(f);
    }
    final w = f.waiting;
    if (w != null) {
      final sp = _specs[f.kind]!.firstWhere((s) => s.key == w);
      try {
        f.v[w] = await _parse(sp.type, text, q, f);
      } on _Ambig catch (a) {
        f.choice = a.list;
        f.choiceKey = w;
        return HReply('تقصد مين؟\n${_list(a.list)}');
      } on FormatException catch (e) {
        return HReply('${e.message}\n${sp.ask}');
      }
    }
    return _advance(f);
  }

  String _list(List<CRef> l) => [for (var i = 0; i < l.length && i < 8; i++) '${i + 1}) ${l[i].name} (${l[i].code})${l[i].remaining == null ? '' : ' — متبقي ${fmtMoney(l[i].remaining)}'}'].join('\n');

  Future<HReply> _advance(_Flow f) async {
    if (f.choice != null) return HReply('تقصد مين؟\n${_list(f.choice!)}');
    for (final sp in _specs[f.kind]!) {
      if (!f.v.containsKey(sp.key)) {
        f.waiting = sp.key;
        if (f.kind == 'add_customer' && sp.key == 'total') {
          // سعر الصنف من المخزن يظهر تلقائي
          final p = await AppDb.i.productByName((f.v['item'] ?? '').toString());
          final pr = p == null ? 0.0 : ((p['sell_price'] ?? 0) as num).toDouble();
          if (p != null && pr > 0) {
            f.v['_listPrice'] = pr;
            return HReply('${sp.ask}\n💡 سعر ${p['name']} في المخزن ${fmtMoney(pr)} — اكتب «بسعر المخزن» أو الرقم اللي اتفقتوا عليه.');
          }
        }
        return HReply(sp.ask);
      }
    }
    f.waiting = null;
    return _buildConfirm(f);
  }

  Future<dynamic> _parse(String type, String raw, String q, _Flow f) async {
    switch (type) {
      case 'text': {
        final t = raw.trim();
        if (t.isEmpty) throw const FormatException('اكتب قيمة.');
        return t;
      }
      case 'num': {
        if (f.waiting == 'total' && f.v['_listPrice'] != null && _has(q, ['سعر المخزن', 'بسعر المخزن', 'زي المخزن', 'نفس السعر', 'بنفس السعر'])) {
          return (f.v['_listPrice'] as num).toDouble();
        }
        final n = _nums(q);
        if (n.isEmpty) throw const FormatException('مفهمتش الرقم.');
        return n.first;
      }
      case 'int': {
        final n = _nums(q);
        if (n.isEmpty) throw const FormatException('مفهمتش العدد.');
        return n.first.toInt();
      }
      case 'months': {
        final pm = RegExp(r'(\d+\s*[x×*]\s*\d+(?:\s*\+\s*\d+\s*[x×*]\s*\d+)*)').firstMatch(q);
        if (pm != null) {
          f.v['plan'] = pm.group(1)!.replaceAll(RegExp(r'\s+'), '');
          return parsePlan(f.v['plan']).fold<int>(0, (s, e) => s + (e[0] as int));
        }
        final n = _nums(q);
        if (n.isEmpty) throw const FormatException('مفهمتش عدد الشهور.');
        return n.first.toInt();
      }
      case 'yn': {
        if (isYes(q)) return 'yes';
        if (!_isNo(q) && raw.trim().isNotEmpty) {
          f.v['sub'] = raw.trim(); // كتب اسم الفرعية على طول
          return 'yes';
        }
        f.v['sub'] = ''; // تخطّي: مفيش منطقة فرعية
        return 'no';
      }
      case 'extras': {
        if (_isNo(q) || q.isEmpty) return 'no';
        _extras(f.v, q, await _names('المناديب'), await _names('المحصلين'), await _regionNames());
        return 'done';
      }
      case 'customer': {
        final cs = await _findCustomers(raw);
        if (cs.isEmpty) throw const FormatException('مش لاقي عميل بالاسم ده. اكتب الاسم أو الكود تاني.');
        if (cs.length > 1) throw _Ambig(cs);
        return cs.first;
      }
      case 'product':
      case 'productAny': {
        final prods = await _prodNames();
        final m = _matchNames(raw, prods);
        if (m.isEmpty) {
          if (type == 'productAny' && raw.trim().isNotEmpty) return raw.trim();
          throw const FormatException('الصنف ده مش موجود في المخزن. اكتب اسمه تاني أو أضفه الأول بـ «صنف جديد».');
        }
        if (m.length > 1) throw FormatException('تقصد أنهي صنف: ${m.take(5).join(' • ')}؟');
        final row = await AppDb.i.productByName(m.first);
        return type == 'productAny' ? m.first : row;
      }
      case 'rep': {
        final names = await _names('المناديب');
        final m = _matchNames(raw, names);
        if (m.isEmpty) throw FormatException('المندوب ده مش مسجّل${names.isEmpty ? '' : '. المسجّلين: ${names.take(6).join('، ')}'}.');
        if (m.length > 1) throw FormatException('تقصد مين: ${m.join(' • ')}؟');
        return m.first;
      }
      case 'supplier': {
        final sup = [for (final s in await AppDb.i.db.query('suppliers')) s['name'].toString()];
        final m = _matchNames(raw, sup);
        if (m.isEmpty) throw const FormatException('المورد ده مش مسجّل.');
        return m.first;
      }
      case 'field': {
        const fm = {'تليفون': 'phone', 'موبايل': 'phone', 'رقم': 'phone', 'عنوان': 'address', 'منطقه': 'region', 'مندوب': 'rep', 'محصل': 'collector', 'بضاعه': 'item'};
        for (final e in fm.entries) {
          if (q.contains(e.key)) return e.value;
        }
        throw const FormatException('اختار: تليفون / عنوان / منطقة / مندوب / محصل / بضاعة.');
      }
    }
    return raw;
  }

  /// سطر تأكيد مقروء من القاعدة بعد التنفيذ (عشان تتأكد إن الداتا اتحفظت فعلاً)
  Future<String> _custLine(String code) async {
    final l = await AppDb.i.financials(code: code);
    if (l.isEmpty) return '⚠️ مش لاقي العميل في القاعدة، راجع شاشة العملاء.';
    final f = l.first;
    return '🔎 من القاعدة: ${f.name} (${f.code})${f.phone.isEmpty ? '' : ' • ${f.phone}'}${f.region.isEmpty ? '' : ' • ${f.region}'}${f.rep.isEmpty ? '' : ' • مندوب ${f.rep}'}${f.collector.isEmpty ? '' : ' • محصّل ${f.collector}'}\nإجمالي ${fmtMoney(f.total)} • مدفوع ${fmtMoney(f.paidTotal)} • متبقي ${fmtMoney(f.remaining)}\n${f.instDesc}';
  }

  // ===================================================================== التأكيد والتنفيذ
  static const _fieldAr = {'phone': 'التليفون', 'address': 'العنوان', 'region': 'المنطقة', 'rep': 'المندوب', 'collector': 'المحصّل', 'item': 'البضاعة'};

  Future<HReply> _buildConfirm(_Flow f) async {
    final v = f.v;
    final db = AppDb.i;
    String text;
    Future<HReply> Function() exec;
    switch (f.kind) {
      case 'add_customer': {
        final total = (v['total'] as num).toDouble(), down = (v['down'] as num).toDouble();
        final months = (v['months'] as num).toInt();
        final plan = (v['plan'] ?? '').toString();
        // خيار «المحصّل = المندوب»: بنعرضه في التأكيد قبل الحفظ
        final autoColl = !repMode && v['collector'] == null && v['rep'] != null && await db.getSetting('rep_is_collector') == 'نعم';
        final monthly = (months > 0 && total > down) ? (total - down) / months : 0.0;
        text = 'هسجّل العميل:\n👤 ${v['name']}\n🛒 ${v['item']}\n💰 إجمالي ${fmtMoney(total)} • مقدم ${fmtMoney(down)}\n📅 ${plan.isNotEmpty ? 'خطة $plan' : '$months شهر × ${fmtMoney(monthly)}'}'
            '${v['phone'] != null ? '\n📞 ${v['phone']}' : ''}${v['region'] != null ? '\n📍 ${v['region']}' : ''}${v['rep'] != null ? '\n🚚 مندوب ${v['rep']}' : ''}${v['collector'] != null ? '\n💼 محصّل ${v['collector']}' : ''}${autoColl ? '\n💼 محصّل ${v['rep']} (المندوب هو المحصّل)' : ''}';
        exec = () async {
          if (repMode) {
            final rp = await db.productByName((v['item'] ?? '').toString());
            await db.addRepSale(
              name: v['name'], phone: (v['phone'] ?? '').toString(), address: (v['address'] ?? '').toString(), region: (v['region'] ?? '').toString(),
              item: (v['item'] ?? '').toString(), total: total, down: down, months: months, plan: plan,
              items: rp == null ? const [] : [{'code': (rp['code'] ?? '').toString(), 'name': rp['name'], 'qty': 1, 'price': total}],
            );
            return const HReply('اتسجّل البيع في شغلك ✅ (هيروح للمالك مع الملف)');
          }
          await db.ensureRegion((v['region'] ?? '').toString());
          final p = await db.productByName((v['item'] ?? '').toString());
          final inStock = p != null && await db.trackStock() && ((p['qty'] ?? 0) as num) > 0;
          final code = await db.addCustomer({
            'name': v['name'], 'phone': v['phone'] ?? '', 'address': v['address'] ?? '', 'region': v['region'] ?? '', 'rep': v['rep'] ?? '', 'collector': v['collector'] ?? '',
            'item': v['item'], 'total': total, 'down': down, 'months': months, 'plan': plan,
            // الصنف بيترتبط بالعقد، والخصم من المخزن بس لو فيه رصيد
            if (p != null) 'items': [{'pid': p['id'], 'name': p['name'], 'qty': 1, 'price': total, 'stock_qty': inStock ? 1 : 0}],
          });
          return HReply('اتسجّل العميل ${v['name']} بكود $code ✅\n${await _custLine(code)}', acts: [HAct('📂 افتح ملف العميل', 'customer', code)]);
        };
        break;
      }
      case 'collect': {
        final c = v['customer'] as CRef;
        final amt = (v['amount'] as num).toDouble();
        if (amt <= 0) throw const FormatException('المبلغ لازم يكون أكبر من صفر.');
        final rem0 = c.remaining;
        if (rem0 != null) {
          if (rem0 <= 0) throw FormatException('${c.name} مسدد بالكامل، مفيش عليه متبقي.');
          if (amt > rem0 + 0.009) throw FormatException('المبلغ (${fmtMoney(amt)}) أكبر من المتبقي على ${c.name} (${fmtMoney(rem0)}). اكتب الأمر تاني بالمبلغ الصح.');
        }
        text = 'هسجّل تحصيل ${fmtMoney(amt)} جنيه من ${c.name} (${c.code})${c.remaining == null ? '' : '\nالمتبقي دلوقتي ${fmtMoney(c.remaining)}'}\n${moneyWords(amt)}';
        exec = () async {
          if (repMode) {
            await db.addRepCollect(custRef: c.code, name: c.name, phone: c.phone, amount: amt);
            return const HReply('اتسجّل التحصيل في شغلك ✅');
          }
          final col = (c.fin?.collector.isNotEmpty ?? false) ? c.fin!.collector : '';
          await db.addPayment(c.code, amt, collector: col);
          final nf = (await db.financials(code: c.code)).first;
          return HReply('اتحصّل ${fmtMoney(amt)} من ${c.name} ✅\nالمتبقي ${fmtMoney(nf.remaining)}${nf.arrears > 0 ? ' • متأخر ${fmtMoney(nf.arrears)}' : ''}', acts: [
            HAct('🧾 إيصال PDF', 'receipt', c.code, amt.toString()),
            if (c.phone.isNotEmpty) HAct('💬 واتساب للعميل', 'wa', c.phone, 'أهلاً ${c.name} 🌹\nاستلمنا منك ${fmtMoney(amt)} جنيه.\n${moneyWords(amt)}\nالمتبقي ${fmtMoney(nf.remaining)} جنيه.\nشكراً لتعاملكم معنا.'),
          ]);
        };
        break;
      }
      case 'expense': {
        final amt = (v['amount'] as num).toDouble();
        text = 'هسجّل مصروف «${v['item']}» بمبلغ ${fmtMoney(amt)} جنيه';
        exec = () async {
          await db.addExpense(v['item'], amt);
          final r = await db.db.query('expenses', orderBy: 'id DESC', limit: 1);
          final ok = r.isNotEmpty && ((r.first['amount'] ?? 0) as num).toDouble() == amt;
          return HReply(ok ? 'اتسجّل المصروف ✅\n🔎 من القاعدة: ${r.first['item_name']} — ${fmtMoney(amt)} جنيه بتاريخ ${r.first['exp_date']}' : '⚠️ المصروف اتسجّل بس مقدرتش أتأكد منه، راجع شاشة المصروفات.', acts: const [HAct('📂 افتح المصروفات', 'screen', 'expenses')]);
        };
        break;
      }
      case 'stock_in':
      case 'stock_out': {
        final p = v['product'] as Map<String, Object?>;
        final qty = (v['qty'] as num).toInt();
        final inn = f.kind == 'stock_in';
        text = '${inn ? 'هضيف' : 'هسحب'} $qty × ${p['name']} ${inn ? 'للمخزن' : 'من المخزن'} (الرصيد الحالي ${p['qty']})';
        exec = () async {
          final nb = await db.stockMove(p['id'] as int, inn ? qty : -qty, inn ? 'وارد' : 'صرف', notes: 'بواسطة الحريف');
          return HReply('تمام ✅ رصيد ${p['name']} بقى $nb', acts: [HAct('📂 افتح الصنف', 'product', '${p['id']}')]);
        };
        break;
      }
      case 'new_product': {
        text = 'هضيف صنف «${v['name']}» — شراء ${fmtMoney(v['buy'])} • بيع ${fmtMoney(v['sell'])} • رصيد ${v['qty']}';
        exec = () async {
          final pid = await db.addProduct(v['name'], buy: (v['buy'] as num).toDouble(), sell: (v['sell'] as num).toDouble(), qty: (v['qty'] as num).toInt());
          final r = await db.db.query('products', where: 'id=?', whereArgs: [pid]);
          final pr = r.isEmpty ? null : r.first;
          return HReply(pr == null ? '⚠️ مقدرتش أتأكد من الصنف، راجع شاشة المخزن.' : 'اتضاف الصنف ✅\n🔎 من القاعدة: ${pr['name']} (${pr['code']}) — شراء ${fmtMoney((pr['buy_price'] ?? 0) as num)} • بيع ${fmtMoney((pr['sell_price'] ?? 0) as num)} • رصيد ${pr['qty'] ?? 0}', acts: [HAct('📂 افتح الصنف', 'product', '$pid')]);
        };
        break;
      }
      case 'custody_give': {
        text = 'هسلّم عهدة: ${v['qty']} × ${v['product']} للمندوب ${v['rep']}';
        exec = () async {
          await db.giveCustody(v['rep'], v['product'].toString(), (v['qty'] as num).toInt());
          final r = await db.db.query('custody', where: 'rep_name=? AND status=?', whereArgs: [v['rep'], custodyOpen]);
          return HReply('اتسجّلت العهدة ✅\n🔎 عهدة ${v['rep']} المفتوحة:\n${r.map((x) => '• ${x['qty']} × ${x['item_name']}').join('\n')}', acts: const [HAct('📂 افتح العهدة', 'screen', 'custody')]);
        };
        break;
      }
      case 'custody_return': {
        final rows = await db.db.query('custody', where: 'rep_name=? AND status=?', whereArgs: [v['rep'], custodyOpen]);
        if (rows.isEmpty) throw FormatException('مفيش عهدة مفتوحة على ${v['rep']}.');
        text = 'المندوب ${v['rep']} هيرجّع:\n${rows.map((r) => '• ${r['qty']} × ${r['item_name']}').join('\n')}\n(الكميات هترجع لرصيد المخزن)';
        exec = () async {
          await db.returnCustodyMany([for (final r in rows) (r['id'] as num).toInt()]);
          return HReply('اترجّعت ${rows.length} عهدة ✅');
        };
        break;
      }
      case 'new_region': {
        text = 'هضيف منطقة «${v['name']}»${(v['sub'] ?? '').toString().isEmpty ? '' : ' — فرعية «${v['sub']}»'}';
        exec = () async {
          await db.saveRegion(name: v['name'].toString(), sub: (v['sub'] ?? '').toString());
          final n = (await db.db.query('regions')).length;
          return HReply('اتضافت المنطقة ✅ (عندك دلوقتي $n منطقة)', acts: const [HAct('📂 افتح المناطق', 'screen', 'regions')]);
        };
        break;
      }
      case 'new_rep':
      case 'new_collector': {
        final t = f.kind == 'new_rep' ? 'المناديب' : 'المحصلين';
        text = 'هضيف ${f.kind == 'new_rep' ? 'مندوب' : 'محصّل'} «${v['name']}»';
        exec = () async {
          await db.addRep(t, v['name']);
          final r = await db.db.query('representatives', where: 'type=? AND name=?', whereArgs: [t, v['name'].toString().trim()]);
          return HReply(r.isEmpty ? '⚠️ مقدرتش أتأكد، راجع شاشة المناديب والمحصلين.' : 'اتضاف ✅\n🔎 من القاعدة: ${r.first['name']} (${r.first['code']})', acts: const [HAct('📂 افتح الفريق', 'screen', 'reps')]);
        };
        break;
      }
      case 'new_supplier': {
        text = 'هضيف مورد «${v['name']}»';
        exec = () async {
          await db.addSupplier(v['name']);
          return const HReply('اتضاف المورد ✅', acts: [HAct('📂 افتح الموردين', 'screen', 'suppliers')]);
        };
        break;
      }
      case 'new_partner': {
        text = 'هضيف مساهم «${v['name']}» — رأس مال ${fmtMoney(v['capital'])} • نسبة ${v['pct']}%';
        exec = () async {
          await db.addPartner(v['name'], (v['capital'] as num).toDouble(), (v['pct'] as num).toDouble());
          return const HReply('اتضاف المساهم ✅', acts: [HAct('📂 افتح المساهمين', 'screen', 'partners')]);
        };
        break;
      }
      case 'supplier_invoice': {
        text = 'هسجّل فاتورة من المورد ${v['supplier']} بإجمالي ${fmtMoney(v['total'])} ومدفوع ${fmtMoney(v['paid'])}';
        exec = () async {
          await db.addSupplierInvoice(v['supplier'], (v['total'] as num).toDouble(), (v['paid'] as num).toDouble());
          return const HReply('اتسجّلت الفاتورة ✅', acts: [HAct('📂 افتح فواتير الموردين', 'screen', 'supplier_invoices')]);
        };
        break;
      }
      case 'supplier_pay': {
        final inv = (await db.supplierInvoices()).where((i) => i['supplier_name'] == v['supplier'] && (i['total'] as num) - (i['paid0'] as num) - (i['paid_extra'] as num) > 0.009).toList();
        if (inv.isEmpty) throw FormatException('مفيش فواتير عليها متبقي للمورد ${v['supplier']}.');
        inv.sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
        final i0 = inv.first;
        text = 'هسدّد ${fmtMoney(v['amount'])} جنيه للمورد ${v['supplier']} على فاتورة ${i0['inv_date']} (المتبقي ${fmtMoney((i0['total'] as num) - (i0['paid0'] as num) - (i0['paid_extra'] as num))})';
        exec = () async {
          await db.addSupplierPayment(i0['id'] as int, (v['amount'] as num).toDouble());
          return const HReply('اتسجّل السداد ✅', acts: [HAct('📂 افتح فواتير الموردين', 'screen', 'supplier_invoices')]);
        };
        break;
      }
      case 'return': {
        final c = v['customer'] as CRef;
        final p = v['product'] as Map<String, Object?>;
        text = 'هسجّل مرتجع من ${c.name}: ${v['qty']} × ${p['name']} بقيمة ${fmtMoney(v['amount'])} (هتتخصم من إجمالي العميل ويتعدّل القسط)';
        exec = () async {
          await db.addReturn(c.code, p['id'] as int, (v['qty'] as num).toInt(), (v['amount'] as num).toDouble());
          return HReply('اتسجّل المرتجع ✅\n${await _custLine(c.code)}', acts: [HAct('📂 افتح ملف العميل', 'customer', c.code)]);
        };
        break;
      }
      case 'damage': {
        final p = v['product'] as Map<String, Object?>;
        text = 'هسجّل تالف: ${v['qty']} × ${p['name']} (هيتخصم من المخزن وتتسجّل التكلفة)';
        exec = () async {
          final cost = await db.addDamage(p['id'] as int, (v['qty'] as num).toInt());
          return HReply('اتسجّل التالف ✅ تكلفته ${fmtMoney(cost)}', acts: const [HAct('📂 افتح التالف', 'screen', 'damages')]);
        };
        break;
      }
      case 'discount': {
        final c = v['customer'] as CRef;
        text = 'هديّ ${c.name} خصم ${fmtMoney(v['amount'])} جنيه (هيتخصم من إجمالي العقد)';
        exec = () async {
          await db.addDiscount(c.code, (v['amount'] as num).toDouble());
          return HReply('اتسجّل الخصم ✅\n${await _custLine(c.code)}', acts: [HAct('📂 افتح ملف العميل', 'customer', c.code)]);
        };
        break;
      }
      case 'delete_payment': {
        final c = v['customer'] as CRef;
        final ps = (await db.customerPayments(c.code)).where((p) => p['due_month'] != downLabel).toList();
        if (ps.isEmpty) throw FormatException('مفيش دفعات قسط على ${c.name}.');
        final last = ps.last;
        text = 'هحذف آخر دفعة على ${c.name}: ${fmtMoney(last['amount_paid'] as num)} جنيه بتاريخ ${last['pay_date']}';
        exec = () async {
          await db.deletePayment(last['id'] as int);
          return HReply('اتحذفت الدفعة ✅\n${await _custLine(c.code)}', acts: [HAct('📂 افتح ملف العميل', 'customer', c.code)]);
        };
        break;
      }
      case 'delete_customer': {
        final c = v['customer'] as CRef;
        text = '⚠️ هحذف العميل ${c.name} (${c.code}) وكل دفعاته نهائياً!';
        exec = () async {
          await db.deleteCustomer(c.code);
          return const HReply('اتحذف العميل ✅');
        };
        break;
      }
      case 'edit_customer': {
        final c = v['customer'] as CRef;
        final fld = v['field'].toString();
        text = 'هغيّر ${_fieldAr[fld]} للعميل ${c.name} لـ «${v['value']}»';
        exec = () async {
          await db.updateCustomer(c.code, {fld: v['value']});
          return HReply('اتعدّل ✅\n${await _custLine(c.code)}', acts: [HAct('📂 افتح ملف العميل', 'customer', c.code)]);
        };
        break;
      }
      case 'rep_target': {
        final ym = isoDate(today()).substring(0, 7);
        text = 'هحط هدف للمندوب ${v['rep']} عن شهر $ym = ${fmtMoney(v['amount'])} جنيه';
        exec = () async {
          await db.setRepTarget(v['rep'], ym, (v['amount'] as num).toDouble());
          return const HReply('اتسجّل الهدف ✅');
        };
        break;
      }
      case 'sales_invoice': {
        final c = v['customer'] as CRef;
        text = 'هصدّر فاتورة بيع للعميل ${c.name}';
        exec = () async {
          final inv = await db.makeSalesInvoice(c.code);
          return HReply('اتصدّرت فاتورة ${inv['inv_code']} بإجمالي ${fmtMoney(inv['total'] as num)} ✅');
        };
        break;
      }
      default: {
        throw FormatException('الأمر ${f.kind} مش مدعوم.');
      }
    }
    _flow = null;
    final need = !repMode && _pwKinds.contains(f.kind);
    _conf = _Confirm(text, exec, needPw: need);
    return HReply('$text\n\nأنفّذ؟ (أيوه / لأ)');
  }

  Future<HReply> _handleConfirm(String q) async {
    final c = _conf!;
    if (_isNo(q)) {
      _conf = null;
      return const HReply('تمام، لغيت ✅');
    }
    if (!_isYes(q)) return const HReply('قولّي «أيوه» أنفّذ أو «لأ» ألغي. (لو عايز تغيّر حاجة اكتب «لأ» وابدأ الأمر من الأول بالتعديل)');
    if (c.needPw) {
      _pw = c;
      _conf = null;
      return const HReply('🔐 اكتب كلمة سر المدير:', secret: true);
    }
    _conf = null;
    return _run(c);
  }

  int _pwTries = 0;

  Future<HReply> _handlePw(String text) async {
    final c = _pw!;
    if (_isNo(normAr(text).trim())) {
      _pw = null;
      _pwTries = 0;
      return const HReply('تمام، لغيت ✅');
    }
    if (!await AppDb.i.verifyAdmin(text)) {
      _pwTries++;
      if (_pwTries >= 3) {
        // 3 محاولات غلط: بنلغي العملية بالكامل ومبنكمّلش
        _pw = null;
        _pwTries = 0;
        return const HReply('الباسورد غلط 3 مرات، لغيت العملية للأمان 🔒');
      }
      return HReply('الباسورد غلط (${3 - _pwTries} محاولات متبقية). حاول تاني أو اكتب «لأ» للإلغاء.', secret: true);
    }
    _pw = null;
    _pwTries = 0;
    return _run(c);
  }

  /// تنفيذ مرة واحدة بس. أي عملية قاعدة بيانات جوّاها atomic (يا تكتمل كلها يا تتلغي كلها)
  Future<HReply> _run(_Confirm c) async {
    if (c.used) return const HReply('العملية دي اتنفّذت قبل كده ✅ — لو عايز تكررها اكتب الأمر من الأول.');
    c.used = true;
    try {
      return await c.exec();
    } on FormatException catch (e) {
      return HReply('⚠️ ${e.message}');
    } catch (e) {
      if (e.toString().contains('LICENSE_READONLY')) return const HReply('🔒 ${LicenseGuard.readOnlyText}');
      return HReply('⚠️ العملية ما اتمّتش بسبب خطأ ومفيش حاجة اتسجّلت ناقصة. جرّب تاني. (${e.toString().split('\n').first})');
    } finally {
      _invalidate();
    }
  }

  Future<HReply> _confirmSimple(String text, Future<HReply> Function() exec, {bool needPw = false}) async {
    _conf = _Confirm(text, exec, needPw: needPw);
    return HReply('$text\n\nأنفّذ؟ (أيوه / لأ)');
  }

  // تغيير الإعدادات من الحريف بيتنفّذ بعد تأكيدك بـ «أيوه» (مفيش كلمة سر جوه البرنامج غير الخصم)
  Future<HReply> _setSetting(String key, bool on, String label) =>
      _confirmSimple('${on ? 'أفعّل' : 'أوقف'} «$label»؟', () async {
        await AppDb.i.setSetting(key, on ? 'نعم' : 'لا');
        await AppDb.i.log('تغيير إعداد بواسطة الحريف', '$label = ${on ? 'نعم' : 'لا'}');
        return HReply('تمام ✅ ${on ? 'اتفعّل' : 'اتوقّف'} «$label»');
      });

  Future<HReply> _doBackup() => _confirmSimple('أعمل نسخة احتياطية من البيانات وأجهّزها للمشاركة؟', () async {
        return const HReply('جاهز 👇', acts: [HAct('💾 اعمل النسخة وشاركها', 'backup')]);
      });

  Future<HReply> _reminder(String text, String q) async {
    if (_has(q, ['كل المتاخرين', 'المتاخرين', 'كلهم', 'الكل'])) {
      final g = dueGroups(await AppDb.i.financials(), today());
      return HReply('عندك ${g.late.length} عميل متأخر بإجمالي ${fmtMoney(g.lateAmt)} جنيه. افتح شاشة التذكيرات وابعت لكل واحد بضغطة 👇', acts: const [HAct('💬 تذكير المتأخرين', 'screen', 'whatsapp')]);
    }
    final cs = await _findCustomers(text);
    if (cs.isEmpty) throw const FormatException('مش لاقي العميل ده.');
    if (cs.length > 1) return HReply('تقصد مين؟\n${_list(cs)}\nاكتب الاسم بالظبط وأعد الأمر.');
    final c = cs.first;
    if (c.phone.isEmpty) throw FormatException('العميل ${c.name} مالوش رقم موبايل.');
    final f = c.fin!;
    final msg = 'أهلاً ${f.name} 🌹\nتذكير بقسط ${fmtMoney(f.monthly)} جنيه${f.arrears > 0 ? '\nالمتأخر حالياً ${fmtMoney(f.arrears)} جنيه (${f.lateMonths} شهر)' : ''}\nالمتبقي الإجمالي ${fmtMoney(f.remaining)} جنيه.\nشكراً لتعاملكم معنا.';
    return HReply('جهّزت رسالة لـ ${f.name}:\n\n$msg', acts: [HAct('💬 ابعتها واتساب', 'wa', c.phone, msg)]);
  }

  // ===================================================================== استعلامات
  /// «سعر الكبة كام» / «مين اشترى كبة» — من المخزن ومربوطة بالعملاء
  Future<HReply?> _productQuery(String text, String q) async {
    final db = AppDb.i;
    bool a(List<String> w) => _has(q, w);
    final wantsBuyers = !repMode && a(['مين اشتري', 'مين شتري', 'اتباع لمين', 'اتباعت لمين', 'مين اخد', 'مين خد']);
    if (!wantsBuyers && !a(['سعر', 'بكام', 'بكم', 'تمن'])) return null;
    final prods = await _prodNames();
    final m = _matchNames(text, prods);
    if (m.isEmpty) return null;
    final p = await db.productByName(m.first);
    if (p == null) return null;
    if (wantsBuyers) {
      final b = await db.productBuyers((p['id'] as num).toInt());
      if (b.isEmpty) return HReply('${p['name']} لسه ما اتباعش لعملاء من العقود.');
      return HReply('🛒 ${p['name']} اتباع لـ:\n${b.take(10).map((x) => '• ${x['customer_name'] ?? x['customer_code']} (${x['customer_code']}): ${(x['qty'] as num).toInt() - (x['returned_qty'] as num).toInt()} × ${fmtMoney((x['unit_price'] ?? 0) as num)} — ${x['sold_at'] ?? ''}').join('\n')}',
          acts: [for (final x in b.take(3)) HAct('📂 ${x['customer_name'] ?? x['customer_code']}', 'customer', x['customer_code'].toString())]);
    }
    final sell = ((p['sell_price'] ?? 0) as num).toDouble();
    return HReply('💰 ${p['name']}: بيع ${sell > 0 ? fmtMoney(sell) : 'لسه ما اتحددش سعره'}${repMode ? '' : ' • شراء ${fmtMoney((p['buy_price'] ?? 0) as num)}'} • رصيد ${p['qty'] ?? 0} قطعة');
  }

  Future<HReply> _query(String text, String q) async {
    final db = AppDb.i;
    final pq = await _productQuery(text, q);
    if (pq != null) return pq;
    if (repMode) return _repQuery(q, text);
    // بنحسب المالية والمتأخرين بس لو السؤال محتاجهم (كانت بتتحسب مع كل رسالة)
    List<CustFin>? finC;
    DueGroups? gC;
    Future<List<CustFin>> finF() async => finC ??= await db.financials();
    Future<DueGroups> gF() async => gC ??= dueGroups(await finF(), today());
    bool a(List<String> w) => _has(q, w);
    final tk = Fuzzy.toks(q);
    final todayQ = a(['النهارده', 'انهارده', 'اليوم']);
    if (a(['ملخص', 'صباح', 'النهارده ايه', 'اخبار'])) return HReply(summaryText(await gF()));
    if (a(['ارباح', 'ربح', 'صافي', 'المساهمين'])) {
      final p = await db.profitSummary();
      final ps = (p['partners'] as List).cast<Map<String, Object?>>();
      return HReply('📊 المالية:\n• تحصيلات ${fmtMoney(p['collected'] as num)}\n• مصروفات ${fmtMoney(p['expenses'] as num)}\n• تالف ${fmtMoney(p['damages'] as num)}\n• مدفوع للموردين ${fmtMoney(p['suppliers'] as num)}\n• الصافي ${fmtMoney(p['net'] as num)}${ps.isEmpty ? '' : '\n${ps.map((x) => '  - ${x['name']} (${x['pct']}%): ${fmtMoney(x['share'] as num)}').join('\n')}'}');
    }
    if (a(['اداء', 'تارجت', 'هدف']) && a(['مندوب'])) {
      final r = _matchNames(text, await _names('المناديب'));
      final reps = r.isNotEmpty ? [r.first] : await _names('المناديب');
      if (reps.isEmpty) return const HReply('مفيش مناديب مسجّلين.');
      final out = <String>[];
      for (final n in reps.take(10)) {
        final s = await db.repTargetStatus(n);
        out.add('🚚 $n: مبيعات الشهر ${fmtMoney(s['sales'] as num)} (${s['count']} عقد)${s['target'] == null ? ' — مفيش هدف' : ' من هدف ${fmtMoney(s['target'] as num)} = ${(s['pct'] as double).toStringAsFixed(0)}%، فاضل ${fmtMoney(s['left'] as num)}'}');
      }
      return HReply(out.join('\n'));
    }
    // «محصّل النهارده» / «اتحصل النهارده كام»: رقم النهارده (ممكن لمحصّل بالاسم) مش أمر تحصيل
    if (todayQ && !a(['مين ']) && (a(['محصل']) || Fuzzy.hasWord(tk, ['حصلنا', 'اتحصل', 'تحصيل', 'حصل']))) {
      final r = a(['محصل']) ? _matchNames(text, await _names('المحصلين')) : <String>[];
      final t = await db.db.rawQuery("SELECT IFNULL(SUM(amount_paid),0) s, COUNT(*) n FROM payments WHERE pay_date=? AND IFNULL(due_month,'')!=? ${r.isNotEmpty ? 'AND collector=?' : ''}", [isoDate(today()), downLabel, if (r.isNotEmpty) r.first]);
      return HReply('اتحصّل النهارده${r.isNotEmpty ? ' (${r.first})' : ''} ${fmtMoney(t.first['s'] as num)} جنيه من ${t.first['n']} دفعة.');
    }
    if (a(['محصل']) && (a(['تحصيل', 'اداء', 'جمع', 'كام']) || Fuzzy.hasWord(tk, ['حصل']))) {
      final r = _matchNames(text, await _names('المحصلين'));
      final ym = isoDate(today()).substring(0, 7);
      final rows = await db.db.rawQuery("SELECT collector c, SUM(amount_paid) s, COUNT(*) n FROM payments WHERE substr(pay_date,1,7)=? AND IFNULL(due_month,'')!=? ${r.isNotEmpty ? 'AND collector=?' : ''} GROUP BY collector ORDER BY s DESC", [ym, downLabel, if (r.isNotEmpty) r.first]);
      if (rows.isEmpty) return const HReply('مفيش تحصيل مسجّل الشهر ده.');
      return HReply('💼 تحصيل الشهر:\n${rows.map((x) => '• ${x['c']}: ${fmtMoney(x['s'] as num)} (${x['n']} دفعة)').join('\n')}');
    }
    if (a(['مين دفع', 'مين حصل', 'اتحصل'])) {
      final rows = await db.db.rawQuery("SELECT customer_name n, amount_paid a FROM payments WHERE pay_date=? AND IFNULL(due_month,'')!=?", [isoDate(today()), downLabel]);
      return HReply(rows.isEmpty ? 'لسه محدش دفع النهارده.' : 'دفعوا النهارده:\n${rows.map((x) => '• ${x['n']}: ${fmtMoney(x['a'] as num)}').join('\n')}');
    }
    if (a(['متاخر', 'مأخر', 'متأخر'])) {
      final g = await gF();
      if (g.late.isEmpty) return const HReply('مفيش متأخرين 🎉');
      return HReply('المتأخرين ${g.late.length} عميل بإجمالي ${fmtMoney(g.lateAmt)} جنيه:\n${g.late.take(10).map((c) => '• ${c.name}: ${fmtMoney(c.arrears)} (${c.lateMonths} شهر)').join('\n')}', acts: const [HAct('💬 ابعت تذكير للمتأخرين', 'screen', 'whatsapp')]);
    }
    if (a(['محصل', 'حصلنا', 'اتحصل', 'تحصيل']) && a(['النهارده', 'انهارده', 'اليوم'])) {
      final r = await db.db.rawQuery("SELECT IFNULL(SUM(amount_paid),0) s, COUNT(*) n FROM payments WHERE pay_date=? AND IFNULL(due_month,'')!=?", [isoDate(today()), downLabel]);
      return HReply('اتحصّل النهارده ${fmtMoney(r.first['s'] as num)} جنيه من ${r.first['n']} دفعة.');
    }
    if (a(['مبيعات']) && todayQ) {
      final r = await db.db.rawQuery('SELECT IFNULL(SUM(total_amount),0) s, COUNT(*) n FROM customers WHERE start_date=?', [isoDate(today())]);
      return HReply('مبيعات النهارده ${fmtMoney(r.first['s'] as num)} جنيه من ${r.first['n']} عقد.');
    }
    if (a(['مصروفات', 'مصاريف']) && todayQ) {
      final r = await db.db.rawQuery('SELECT IFNULL(SUM(amount),0) s, COUNT(*) n FROM expenses WHERE exp_date=?', [isoDate(today())]);
      return HReply('مصروفات النهارده ${fmtMoney(r.first['s'] as num)} جنيه (${r.first['n']} بند).');
    }
    if (a(['مبيعات']) ) {
      final ym = isoDate(today()).substring(0, 7);
      final r = await db.db.rawQuery("SELECT IFNULL(SUM(total_amount),0) s, COUNT(*) n FROM customers WHERE substr(start_date,1,7)=?", [ym]);
      return HReply('مبيعات الشهر ${fmtMoney(r.first['s'] as num)} جنيه من ${r.first['n']} عقد.');
    }
    if (a(['مصروفات', 'مصاريف']) && a(['كام', 'الشهر', 'النهارده', 'اجمالي'])) {
      final ym = isoDate(today()).substring(0, 7);
      final r = await db.db.rawQuery('SELECT IFNULL(SUM(amount),0) s, COUNT(*) n FROM expenses WHERE substr(exp_date,1,7)=?', [ym]);
      return HReply('مصروفات الشهر ${fmtMoney(r.first['s'] as num)} جنيه (${r.first['n']} بند).');
    }
    if (a(['قيمة المخزن', 'ملخص المخزن', 'حالة المخزن', 'المخزن عامل', 'جرد المخزن'])) {
      final s = await db.stockSummary();
      return HReply('🏬 المخزن:\n• ${s['count']} صنف • ${s['low']} ناقص • ${s['out']} نفد\n• قيمته بسعر الشراء ${fmtMoney(s['buyVal'])} وبسعر البيع ${fmtMoney(s['sellVal'])}\n• في عهدة المناديب ${s['custody']} قطعة');
    }
    if (a(['ناقص', 'نواقص', 'نافد', 'خلص'])) {
      final r = await db.db.rawQuery('SELECT name, qty FROM products WHERE IFNULL(qty,0) <= IFNULL(min_qty,3) ORDER BY qty LIMIT 15');
      return HReply(r.isEmpty ? 'كل الأصناف رصيدها تمام ✅' : 'أصناف ناقصة:\n${r.map((p) => '• ${p['name']}: ${p['qty']}').join('\n')}');
    }
    if (a(['عهده', 'عهدة']) && a(['كام', 'مين', 'اعرض', 'وريني'])) {
      final r = await db.db.query('custody', where: 'status=?', whereArgs: [custodyOpen]);
      return HReply(r.isEmpty ? 'مفيش عهد مفتوحة.' : 'العهد المفتوحة:\n${r.map((x) => '• ${x['rep_name']}: ${x['qty']} × ${x['item_name']}').join('\n')}');
    }
    if (a(['توقع', 'هيدخل', 'متوقع'])) {
      final (rows, late) = forecast(await finF(), today());
      if (rows.isEmpty && late <= 0) return const HReply('مفيش أقساط جاية.');
      return HReply('${rows.map((r) => '• ${r.ym}: ${fmtMoney(r.amount)} (${r.count} قسط)').join('\n')}\n⚠️ متأخرات حالية ${fmtMoney(late)} جنيه.');
    }
    if (a(['زيارات', 'زيارة', 'خطه', 'خطة'])) {
      final p = visitPlan((await gF()).late);
      if (p.isEmpty) return const HReply('مفيش متأخرين محتاجين زيارة 🎉');
      return HReply(p.map((e) => '🚚 ${e.$1}\n${e.$2.map((r) => '  ${r.$1}: ${r.$2.map((c) => c.name).join('، ')}').join('\n')}').join('\n'));
    }
    if (a(['اجمالي', 'متبقي كله', 'كام عند العملاء'])) {
      return HReply('إجمالي المتبقي عند العملاء ${fmtMoney((await finF()).fold<double>(0, (s, c) => s + c.remaining))} جنيه.');
    }
    if (a(['رصيد', 'كام']) && a(['مخزن', 'رصيد', 'قطعه', 'عندي'])) {
      final prods = await _prodNames();
      final m = _matchNames(text, prods);
      if (m.isNotEmpty) {
        final p = await db.productByName(m.first);
        return HReply('رصيد ${p!['name']}: ${p['qty']} قطعة • بيع ${fmtMoney(p['sell_price'] as num)} • شراء ${fmtMoney(p['buy_price'] as num)}');
      }
    }
    final more = await _moreQueries(text, q, tk, finF, gF);
    if (more != null) return more;
    if (a(['كشف', 'حساب', 'كام علي', 'كام على', 'متبقي', 'قسط']) || true) {
      final cs = await _custOrLast(text, q);
      if (cs.isNotEmpty) {
        if (cs.length == 1) _last = cs.first;
        final out = <String>[];
        for (final c in cs.take(3)) {
          final f = c.fin!;
          out.add('👤 ${f.name} (${f.code})${f.collector.isEmpty ? '' : ' • محصّل ${f.collector}'}\nالإجمالي ${fmtMoney(f.total)} • المدفوع ${fmtMoney(f.paidTotal)} • المتبقي ${fmtMoney(f.remaining)}\n${f.instDesc}${f.arrears > 0 ? '\n⏰ متأخر ${fmtMoney(f.arrears)} (${f.lateMonths} شهر)' : ''}${f.nextDue != null ? '\nالقسط الجاي ${isoDate(f.nextDue!)}' : ''}');
        }
        return HReply(out.join('\n\n'), acts: [for (final c in cs.take(3)) HAct('📂 ${c.name}', 'customer', c.code)]);
      }
    }
    return const HReply('مفهمتش قصدك 🤔 جرّب مثلاً:\n• «كام على محمود» • «تليفون محمود»\n• «مين المتأخرين» • «مين عليه بكره»\n• «حصّل 500 من محمود» • «مصروف كهرباء 300»\n• «عملاء منطقة طنطا» • «ملخص النهارده»\nأو قول «مساعدة» عشان تشوف كل اللي أعرف أعمله.');
  }

  static const _followWords = ['متبقي', 'عليه', 'عليها', 'تليفونه', 'تليفونها', 'عنوانه', 'قسطه', 'ملفه', 'بتاعه', 'وكمان', 'والمتبقي', 'اخر دفعه', 'دفع كام', 'رقمه', 'منطقته'];

  /// العميل من الجملة، ولو مفيش اسم والجملة متابعة («والمتبقي؟») بنرجع لآخر عميل اتكلمنا عنه
  Future<List<CRef>> _custOrLast(String text, String q) async {
    final cs = await _findCustomers(text);
    if (cs.isNotEmpty) return cs;
    final l = _last;
    if (l != null && _has(q, _followWords)) {
      final fresh = (await _customers()).where((c) => c.code == l.code).toList();
      if (fresh.isNotEmpty) return fresh;
    }
    return [];
  }

  /// أسئلة إضافية (قراءة بس): النهارده/بكره، أعداد، أكتر متأخر، عملاء منطقة/مندوب، بيانات عميل (تليفون/عنوان/...)
  Future<HReply?> _moreQueries(String text, String q, List<String> tk, Future<List<CustFin>> Function() finF, Future<DueGroups> Function() gF) async {
    bool a(List<String> w) => _has(q, w);
    if (a(['السلام عليكم', 'صباح الخير', 'مساء الخير', 'اهلا', 'مرحبا'])) return const HReply('أهلاً بيك يا باشا 🌹 اؤمرني.');
    if (a(['شكرا', 'تسلم', 'متشكر'])) return const HReply('العفو يا باشا، في أي وقت 🌹');
    if (a(['بكره', 'بكرا', 'غدا'])) {
      final g = await gF();
      if (g.tomorrow.isEmpty) return const HReply('مفيش أقساط مستحقة بكره.');
      return HReply('📅 أقساط بكره (${g.tomorrow.length}) بإجمالي ${fmtMoney(g.tomorrowAmt)}:\n${g.tomorrow.take(15).map((c) => '• ${c.name}: ${fmtMoney(g.dueAmt[c.code] ?? c.monthly)}').join('\n')}', acts: const [HAct('💬 تذكير واتساب', 'screen', 'whatsapp')]);
    }
    if (a(['مستحق', 'اقساط النهارده', 'عليه النهارده', 'عليهم النهارده', 'هيدفع النهارده'])) {
      final g = await gF();
      if (g.today.isEmpty) return const HReply('مفيش أقساط مستحقة النهارده.');
      return HReply('📅 أقساط النهارده (${g.today.length}) بإجمالي ${fmtMoney(g.todayAmt)}:\n${g.today.take(15).map((c) => '• ${c.name}: ${fmtMoney(g.dueAmt[c.code] ?? c.monthly)}').join('\n')}', acts: const [HAct('💬 تذكير واتساب', 'screen', 'whatsapp')]);
    }
    if (a(['كام عميل', 'عدد العملاء', 'عندي كام عميل'])) {
      final fin = await finF();
      final open = fin.where((c) => c.remaining > 0.004).length;
      final g = await gF();
      return HReply('👥 عندك ${fin.length} عميل: $open عليهم متبقي، ${fin.length - open} مسددين، و${g.late.length} متأخر.');
    }
    if (a(['اكتر متاخر', 'اكبر متاخر', 'اكتر عميل متاخر', 'اعلي متاخرات', 'اكبر متاخرات'])) {
      final g = await gF();
      if (g.late.isEmpty) return const HReply('مفيش متأخرين 🎉');
      return HReply('🔝 أكبر المتأخرات:\n${g.late.take(5).map((c) => '• ${c.name}: ${fmtMoney(c.arrears)} (${c.lateMonths} شهر)').join('\n')}', acts: [for (final c in g.late.take(3)) HAct('📂 ${c.name}', 'customer', c.code)]);
    }
    // فتح الشاشات بالأمر
    if (a(['افتح', 'وديني', 'روح ل', 'فتح'])) {
      const targets = <String, (String, String, List<String>)>{
        'products': ('المخزن', 'product_home', ['مخزن', 'اصناف']),
        'regions': ('المناطق', 'regions', ['مناطق', 'منطقه']),
        'expenses': ('المصروفات', 'expenses', ['مصروفات', 'مصاريف']),
        'suppliers': ('الموردين', 'suppliers', ['موردين', 'مورد']),
        'partners': ('المساهمين', 'partners', ['مساهمين', 'مساهم']),
        'custody': ('العهدة', 'custody', ['عهده']),
        'reps': ('المناديب والمحصلين', 'reps', ['مناديب', 'محصلين', 'مندوب']),
        'supplier_invoices': ('فواتير الموردين', 'supplier_invoices', ['فواتير']),
        'damages': ('التالف', 'damages', ['تالف']),
        'whatsapp': ('تذكيرات واتساب', 'whatsapp', ['واتساب', 'تذكير']),
      };
      for (final e in targets.entries) {
        if (a(e.value.$3)) return HReply('تمام 👇', acts: [HAct('📂 افتح ${e.value.$1}', 'screen', e.value.$2)]);
      }
    }
    // تحصيل الشهر / السنة كلها / عميل معين — موزّع على المناطق (لو اخترت منطقة بيظهر هي بس، وإلا بيظهر الكل)
    if (a(['تحصيل الشهر', 'تحصيل السنه', 'تحصيل سنه', 'مستحق الشهر', 'مستحق السنه', 'مطلوب الشهر', 'مطلوب السنه', 'اقساط الشهر', 'اقساط السنه', 'مطلوب تحصيله'])) {
      final year = a(['السنه', 'سنه']);
      final t0 = today();
      final end = year ? DateTime(t0.year, 12, 31) : DateTime(t0.year, t0.month + 1, 0);
      final label = year ? 'السنة كلها (${t0.year})' : 'الشهر (${t0.month}/${t0.year})';
      var fin = await finF();
      final cs = await _findCustomers(text);
      final rg = _matchNames(text, await _regionNames());
      var scope = '';
      if (cs.isNotEmpty && cs.length <= 3) {
        final codes = {for (final c in cs) c.code};
        fin = fin.where((c) => codes.contains(c.code)).toList();
        scope = ' — ${cs.map((c) => c.name).join('، ')}';
      } else if (rg.isNotEmpty) {
        final rs = {for (final r in rg) normAr(r).trim()};
        fin = fin.where((c) => rs.contains(normAr(c.region).trim())).toList();
        scope = ' — ${rg.join('، ')}';
      }
      final due = <CustFin, double>{};
      for (final c in fin) {
        var x = 0.0;
        for (final r in installmentRows(c)) {
          if (!r.paid && r.due != null && !r.due!.isAfter(end)) x += r.toPay;
        }
        x = r2(x);
        if (x > c.remaining) x = c.remaining;
        if (x > 0.004) due[c] = x;
      }
      if (due.isEmpty) return HReply('مفيش مبالغ مستحقة لتحصيل $label$scope 🎉');
      final total = due.values.fold<double>(0, (p, e) => p + e);
      final byRegion = <String, (int, double)>{};
      due.forEach((c, v) {
        final k = c.region.trim().isEmpty ? 'من غير منطقة' : c.region.trim();
        final o = byRegion[k] ?? (0, 0.0);
        byRegion[k] = (o.$1 + 1, o.$2 + v);
      });
      final regs = byRegion.entries.toList()..sort((x, y) => y.value.$2.compareTo(x.value.$2));
      final top = due.entries.toList()..sort((x, y) => y.value.compareTo(x.value));
      final out = StringBuffer('📅 تحصيل $label$scope: ${due.length} عميل بإجمالي ${fmtMoney(total)} جنيه');
      if (cs.isEmpty) {
        out.write('\n\n📍 حسب المنطقة:');
        for (final e in regs.take(12)) {
          out.write('\n• ${e.key}: ${e.value.$1} عميل — ${fmtMoney(e.value.$2)}');
        }
      }
      out.write('\n\n👥 الأكبر:');
      for (final e in top.take(cs.isNotEmpty ? 10 : 6)) {
        out.write('\n• ${e.key.name}: ${fmtMoney(e.value)}');
      }
      return HReply(out.toString(), acts: [for (final e in top.take(3)) HAct('📂 ${e.key.name}', 'customer', e.key.code), const HAct('💬 تذكير واتساب', 'screen', 'whatsapp')]);
    }
    // عملاء منطقة / مندوب
    if (a(['عملاء', 'منطقه', 'متاخرين']) && !a(['عميل جديد'])) {
      final fin = await finF();
      final rg = _matchNames(text, await _regionNames());
      final rp = rg.isEmpty ? _matchNames(text, await _names('المناديب')) : <String>[];
      if (rg.length == 1 || rp.length == 1) {
        final isReg = rg.length == 1;
        final nm = isReg ? rg.first : rp.first;
        final list = fin.where((c) => normAr(isReg ? c.region : c.rep).trim() == normAr(nm).trim()).toList();
        if (list.isEmpty) return HReply('مفيش عملاء ${isReg ? 'في منطقة' : 'للمندوب'} $nm.');
        final late = list.where((c) => c.arrears > 0).toList()..sort((x, y) => y.arrears.compareTo(x.arrears));
        final rem = list.fold<double>(0, (t, c) => t + c.remaining);
        return HReply('${isReg ? '📍' : '🚚'} $nm: ${list.length} عميل • متبقي ${fmtMoney(rem)} • متأخر ${late.length}${late.isEmpty ? '' : '\n${late.take(8).map((c) => '• ${c.name}: ${fmtMoney(c.arrears)}').join('\n')}'}');
      }
    }
    // بيانات عميل: تليفون / عنوان / منطقة / مندوب / محصّل / بضاعة
    const fields = <String, List<String>>{
      'phone': ['تليفون', 'موبايل', 'رقم', 'نمره'],
      'address': ['عنوان', 'ساكن فين', 'بيسكن'],
      'region': ['منطقه'],
      'collector': ['محصل'],
      'rep': ['مندوب'],
      'item': ['اشتري ايه', 'اشتري', 'بضاعه'],
    };
    String? fld;
    for (final e in fields.entries) {
      if (a(e.value)) {
        fld = e.key;
        break;
      }
    }
    if (fld != null && !_has(q, ['اداء', 'تحصيل', 'عملاء'])) {
      final cs = await _custOrLast(text, q);
      if (cs.isNotEmpty && cs.length <= 3 && cs.first.fin != null) {
        if (cs.length == 1) _last = cs.first;
        String val(CustFin f) => switch (fld) {
              'phone' => f.phone,
              'address' => f.address,
              'region' => f.region,
              'collector' => f.collector,
              'rep' => f.rep,
              _ => f.item,
            };
        const lbl = {'phone': '📞 التليفون', 'address': '🏠 العنوان', 'region': '📍 المنطقة', 'collector': '💼 المحصّل', 'rep': '🚚 المندوب', 'item': '🛒 البضاعة'};
        final out = [for (final c in cs) '${c.fin!.name}: ${lbl[fld]} ${val(c.fin!).isEmpty ? 'مش متسجّل' : val(c.fin!)}'];
        return HReply(out.join('\n'), acts: [
          for (final c in cs.take(3)) HAct('📂 ${c.name}', 'customer', c.code),
          if (fld == 'phone') for (final c in cs.take(1)) if (c.phone.isNotEmpty) HAct('💬 واتساب', 'wa', c.phone, ''),
        ]);
      }
    }
    return null;
  }

  Future<HReply> _repQuery(String q, String text) async {
    final db = AppDb.i;
    final rows = await db.repEntries(onlyNew: true);
    final sold = rows.where((e) => e['kind'] == 'sale').fold<double>(0.0, (s, e) => s + (e['total'] as num));
    final got = rows.where((e) => e['kind'] == 'collect').fold<double>(0.0, (s, e) => s + (e['amount'] as num));
    if (_has(q, ['ملخص', 'شغلي', 'كام بعت', 'كام حصلت', 'حصلت كام', 'بعت كام'])) {
      return HReply('📋 شغلك لسه ما اتبعتش:\n• بيع ${fmtMoney(sold)} جنيه (${rows.where((e) => e['kind'] == 'sale').length} عقد)\n• تحصيل ${fmtMoney(got)} جنيه (${rows.where((e) => e['kind'] == 'collect').length} دفعة)');
    }
    if (_has(q, ['متاخر', 'متأخر'])) {
      final b = await db.db.rawQuery('SELECT name, arrears FROM rep_base WHERE arrears>0 ORDER BY arrears DESC LIMIT 10');
      return HReply(b.isEmpty ? 'مفيش متأخرين في عملائك 🎉' : 'المتأخرين عندك:\n${b.map((x) => '• ${x['name']}: ${fmtMoney(x['arrears'] as num)}').join('\n')}');
    }
    final cs = await _findCustomers(text);
    if (cs.isNotEmpty) {
      final c = cs.first;
      return HReply('👤 ${c.name} (${c.code})${c.remaining == null ? '\nعقد جديد سجّلته النهارده' : '\nالمتبقي ${fmtMoney(c.remaining)} • القسط ${fmtMoney(c.monthly ?? 0)}'}');
    }
    return const HReply('مفهمتش 🤔 جرّب «حصّلت 500 من محمود» أو «سجل عميل جديد ...» أو «ملخص شغلي».');
  }
}
