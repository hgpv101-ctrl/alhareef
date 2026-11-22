import 'dart:async';
import 'dart:io';
import 'license_sql.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../core/engine.dart';
import '../core/security.dart';
import '../core/utils.dart';

const defaultSettings = <String, String>{
  'company_name': '', 'company_activity': 'مفروشات + أدوات منزلية + أجهزة كهربائية', 'phones': '', 'company_address': '',
  'product_mode': 'منتجات المخزن', 'receipt_model': 'نصف ورقة', 'show_prices': 'نعم', 'show_shop_phone': 'نعم',
  'receipt_footer': 'شكراً لتعاملكم معنا', 'allow_negative_stock': 'لا', 'low_stock_default': '3', 'default_months': '12',
  'grace_days': '0', 'require_login': 'نعم', 'admin_unlock_minutes': '5', 'auto_backup': 'نعم',
  'backup_keep': '14', 'rep_is_collector': 'لا', 'hareef_call': 'باشا', 'owner_name': '', 'language_style': 'عامية مصرية', 'receipt_layout': 'a4x3', 'receipt_lang': 'ar',
  // بيانات الإيصال الإنجليزي (Contract Credit)
  'en_brand': '', 'en_brand_sub': '', 'en_address': '',
  'en_acc_no': '', 'en_acc_name': '', 'en_bank': '',
  'en_whatsapp': '', 'en_manager': '', 'en_logo_b64': '',
};

/// بيزيد لما بيانات العملاء/الدفعات تتغيّر — الشاشات بتسمعه وتحدّث نفسها (مع تجميع التنبيهات)
final ValueNotifier<int> dataRev = ValueNotifier<int>(0);
bool _revPending = false;
/// بيزيد فوراً مع أي تغيير — كاش الحسابات بيتأكد منه قبل ما يرجّع نتيجة قديمة
int _dataVer = 0;
int get dataVersion => _dataVer;
void bumpData() {
  _dataVer++;
  if (_revPending) return;
  _revPending = true;
  Future.delayed(const Duration(milliseconds: 250), () {
    _revPending = false;
    dataRev.value++;
  });
}

/// زوّد الرقم ده كل ما تضيف جدول/عمود جديد — الترقية بتتشغّل مرة واحدة بس بدل كل فتحة للتطبيق
const _schemaVersion = 6;

class _FinJob {
  const _FinJob(this.rows, this.paid, this.asOf, this.grace);
  final List<Map<String, Object?>> rows;
  final Map<String, double> paid;
  final DateTime asOf;
  final int grace;
}

/// حساب مالية العملاء كلهم — بيتنفّذ في isolate لو العملاء كتير عشان الشاشة ماتهنجش
List<CustFin> _computeAll(_FinJob j) =>
    [for (final r in j.rows) computeFin(r, j.paid[r['customer_code'].toString()] ?? 0, j.asOf, j.grace)];

const _schema = <String>[
  "CREATE TABLE IF NOT EXISTS users (user_id TEXT PRIMARY KEY, password TEXT NOT NULL, role TEXT DEFAULT 'Admin')",
  'CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)',
  'CREATE TABLE IF NOT EXISTS regions (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, sub_name TEXT)',
  'CREATE TABLE IF NOT EXISTS representatives (id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL, name TEXT NOT NULL, user_num TEXT, password TEXT, phone TEXT, extra TEXT, notes TEXT, code TEXT, coll_ratio REAL DEFAULT 0)',
  'CREATE TABLE IF NOT EXISTS products (id INTEGER PRIMARY KEY AUTOINCREMENT, category TEXT, name TEXT, rep_ratio REAL DEFAULT 0, buy_price REAL DEFAULT 0, sell_price REAL DEFAULT 0, code TEXT, qty INTEGER DEFAULT 0, min_qty INTEGER DEFAULT 3, barcode TEXT)',
  '''CREATE TABLE IF NOT EXISTS customers (customer_code TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT, address TEXT, region TEXT,
     rep_name TEXT, collector_name TEXT, total_amount REAL DEFAULT 0, down_payment REAL DEFAULT 0, monthly_installment REAL DEFAULT 0,
     remaining_amount REAL DEFAULT 0, months_count INTEGER DEFAULT 12, item_desc TEXT, start_date TEXT, first_due_date TEXT, branch TEXT, plan_text TEXT)''',
  'CREATE TABLE IF NOT EXISTS suppliers_invoices (id INTEGER PRIMARY KEY AUTOINCREMENT, supplier_name TEXT, inv_date TEXT, total REAL, paid REAL, notes TEXT)',
  'CREATE TABLE IF NOT EXISTS payments (id INTEGER PRIMARY KEY AUTOINCREMENT, customer_code TEXT, customer_name TEXT, amount_paid REAL, pay_date TEXT, due_month TEXT, collector TEXT, notes TEXT)',
  'CREATE TABLE IF NOT EXISTS custody (id INTEGER PRIMARY KEY AUTOINCREMENT, rep_name TEXT, item_name TEXT, qty INTEGER, date_given TEXT, status TEXT, returned_date TEXT, notes TEXT)',
  'CREATE TABLE IF NOT EXISTS expenses (id INTEGER PRIMARY KEY AUTOINCREMENT, item_name TEXT, amount REAL, exp_date TEXT, notes TEXT)',
  'CREATE TABLE IF NOT EXISTS partners (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, capital REAL DEFAULT 0, share_percent REAL DEFAULT 0, code TEXT, phone TEXT, notes TEXT)',
  'CREATE TABLE IF NOT EXISTS suppliers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT, address TEXT, activity TEXT, notes TEXT, code TEXT)',
  'CREATE TABLE IF NOT EXISTS supplier_payments (id INTEGER PRIMARY KEY AUTOINCREMENT, invoice_id INTEGER, amount REAL, pay_date TEXT, notes TEXT)',
  'CREATE TABLE IF NOT EXISTS stock_moves (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER, product_name TEXT, kind TEXT, qty INTEGER, balance_after INTEGER, move_date TEXT, ref TEXT, notes TEXT)',
  'CREATE TABLE IF NOT EXISTS warehouses (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL)',
  'CREATE TABLE IF NOT EXISTS wh_stock (product_id INTEGER, wh_id INTEGER, qty INTEGER DEFAULT 0, PRIMARY KEY(product_id, wh_id))',
  'CREATE TABLE IF NOT EXISTS audit_log (id INTEGER PRIMARY KEY AUTOINCREMENT, ts TEXT, action TEXT, details TEXT, who TEXT)',
  'CREATE TABLE IF NOT EXISTS returns_log (id INTEGER PRIMARY KEY AUTOINCREMENT, ret_date TEXT, customer_code TEXT, product_id INTEGER, product_name TEXT, qty INTEGER, amount REAL, reason TEXT)',
  'CREATE TABLE IF NOT EXISTS damages (id INTEGER PRIMARY KEY AUTOINCREMENT, dmg_date TEXT, product_id INTEGER, product_name TEXT, qty INTEGER, cost REAL, reason TEXT, stock_updated INTEGER)',
  'CREATE TABLE IF NOT EXISTS discounts (id INTEGER PRIMARY KEY AUTOINCREMENT, disc_date TEXT, customer_code TEXT, amount REAL, reason TEXT)',
  'CREATE TABLE IF NOT EXISTS sales_invoices (id INTEGER PRIMARY KEY AUTOINCREMENT, inv_code TEXT UNIQUE, inv_date TEXT, customer_code TEXT, customer_name TEXT, item TEXT, total REAL, down REAL, months INTEGER, monthly REAL, branch TEXT)',
  'CREATE TABLE IF NOT EXISTS branches (id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT, name TEXT UNIQUE NOT NULL, address TEXT, created TEXT)',
  'CREATE TABLE IF NOT EXISTS rep_targets (id INTEGER PRIMARY KEY AUTOINCREMENT, rep_name TEXT NOT NULL, ym TEXT NOT NULL, target REAL NOT NULL, created TEXT, UNIQUE(rep_name, ym))',
  'CREATE TABLE IF NOT EXISTS hareef_chats (id INTEGER PRIMARY KEY AUTOINCREMENT, ts TEXT, sender TEXT, text TEXT)',
  'CREATE TABLE IF NOT EXISTS commission_lines (id INTEGER PRIMARY KEY AUTOINCREMENT, rep_name TEXT, ym TEXT, kind TEXT, customer_code TEXT, customer_name TEXT, amount REAL, notes TEXT, created TEXT)',
  'CREATE TABLE IF NOT EXISTS settlements (id INTEGER PRIMARY KEY AUTOINCREMENT, rep_name TEXT, ym TEXT, collected REAL, coll_comm REAL, sales_total REAL, sales_comm REAL, extra_comm REAL, total REAL, closed_at TEXT, notes TEXT)',
  'CREATE TABLE IF NOT EXISTS rep_entries (uid TEXT PRIMARY KEY, kind TEXT, ts TEXT, cust_ref TEXT, name TEXT, phone TEXT, address TEXT, region TEXT, item TEXT, total REAL, down REAL, months INTEGER, plan TEXT, amount REAL, pay_date TEXT, notes TEXT, exported INTEGER DEFAULT 0)',
  'CREATE TABLE IF NOT EXISTS rep_base (code TEXT PRIMARY KEY, name TEXT, phone TEXT, address TEXT, region TEXT, item TEXT, remaining REAL, monthly REAL, arrears REAL, next_due TEXT, collector TEXT)',
  'CREATE TABLE IF NOT EXISTS rep_reports (id INTEGER PRIMARY KEY AUTOINCREMENT, batch_id TEXT UNIQUE, rep_name TEXT, role TEXT, file_name TEXT, imported_at TEXT, n_sales INTEGER, n_collect INTEGER, total_sales REAL, total_collect REAL, n_ok INTEGER, n_warn INTEGER, n_err INTEGER, n_applied INTEGER, issues TEXT)',
  'CREATE TABLE IF NOT EXISTS applied_entries (uid TEXT PRIMARY KEY, batch_id TEXT, rep_name TEXT, kind TEXT, applied_at TEXT, ref TEXT)',
  'CREATE TABLE IF NOT EXISTS customer_items (id INTEGER PRIMARY KEY AUTOINCREMENT, customer_code TEXT, product_id INTEGER, product_name TEXT, qty INTEGER DEFAULT 1, unit_price REAL DEFAULT 0, line_total REAL DEFAULT 0, stock_qty INTEGER DEFAULT 0, returned_qty INTEGER DEFAULT 0, sold_at TEXT, rep_name TEXT)',
  'CREATE INDEX IF NOT EXISTS ix_items_cust ON customer_items(customer_code)',
  'CREATE INDEX IF NOT EXISTS ix_items_prod ON customer_items(product_id)',
  'CREATE INDEX IF NOT EXISTS ix_pay_cust ON payments(customer_code)',
  'CREATE INDEX IF NOT EXISTS ix_pay_date ON payments(pay_date)',
  'CREATE INDEX IF NOT EXISTS ix_cust_name ON customers(name)',
  'CREATE INDEX IF NOT EXISTS ix_moves_prod ON stock_moves(product_id)',
];

/// أعمدة ممكن تكون ناقصة في نسخة .db قديمة
const _upgradeCols = <List<String>>[
  ['representatives', 'extra', 'TEXT'], ['representatives', 'notes', 'TEXT'], ['representatives', 'code', 'TEXT'],
  ['representatives', 'coll_ratio', 'REAL DEFAULT 0'], ['representatives', 'coll_comm', 'REAL DEFAULT 0'], ['products', 'rep_comm', 'REAL DEFAULT 0'], ['regions', 'collector', 'TEXT'], ['rep_base', 'due_amt', 'REAL DEFAULT 0'], ['rep_base', 'due_month', 'TEXT'], ['regions', 'notes', 'TEXT'], ['products', 'code', 'TEXT'], ['products', 'qty', 'INTEGER DEFAULT 0'],
  ['products', 'min_qty', 'INTEGER DEFAULT 3'], ['products', 'barcode', 'TEXT'], ['products', 'en_name', 'TEXT'], ['suppliers', 'code', 'TEXT'],
  ['partners', 'code', 'TEXT'], ['partners', 'phone', 'TEXT'], ['partners', 'notes', 'TEXT'], ['customers', 'branch', 'TEXT'],
  ['customers', 'plan_text', 'TEXT'], ['custody', 'returned_date', 'TEXT'], ['custody', 'notes', 'TEXT'], ['audit_log', 'who', 'TEXT'], ['rep_entries', 'items_json', 'TEXT'],
  ['customers', 'lat', 'REAL'], ['customers', 'lng', 'REAL'], ['customers', 'en_name', 'TEXT'], ['customers', 'en_address', 'TEXT'], ['customers', 'en_item', 'TEXT'], ['rep_entries', 'lat', 'REAL'], ['rep_entries', 'lng', 'REAL'],
  ['customer_items', 'stock_qty', 'INTEGER DEFAULT 0'], ['customer_items', 'returned_qty', 'INTEGER DEFAULT 0'], ['customer_items', 'sold_at', 'TEXT'], ['customer_items', 'rep_name', 'TEXT'],
];

class AppDb {
  AppDb._(this.db, this.path);
  Database db;
  String path;
  String who = 'admin';
  List<CustFin>? _finCache;
  int _finVer = -1, _finGrace = -1;
  String _finDay = '';
  static AppDb? _i;
  static AppDb get i => _i!;

  static Future<String> defaultPath() async {
    final d = await getDatabasesPath();
    return p.join(d, 'sales_system.db');
  }

  static Future<AppDb> open([String? path]) async {
    path ??= await defaultPath();
    final db = await _openRaw(path);
    final a = AppDb._(db, path);
    await LicenseSql.relax(db); // الترقيات بتكتب: نفتح القفل مؤقتاً
    await a._init();
    if (licenseEnforced) await LicenseSql.install(db); // القراءة فقط على مستوى القاعدة (بتتفتح بس لما الترخيص يتأكد)
    _i = a;
    unawaited(a._autoBackup()); // نسخة يومية تلقائية في الخلفية (بعد ما التطبيق يفتح)
    return a;
  }

  /// فتح القاعدة بإعدادات آمنة وخفيفة: WAL (الكتابة ما بتبوظش لو الجهاز اتقفل فجأة) + ذاكرة مؤقتة صغيرة للأجهزة الضعيفة
  /// للاختبارات بس (الاختبارات بتكتب من غير ترخيص). في التطبيق الحقيقي دايماً true.
  static bool licenseEnforced = true;

  /// بيتنده بعد استبدال القاعدة (استيراد نسخة) عشان الترخيص يتفحص تاني
  static void Function()? onReopened;

  static Future<Database> _openRaw(String path) => openDatabase(path, onConfigure: (d) async {
        try {
          await d.rawQuery('PRAGMA journal_mode=WAL');
          await d.execute('PRAGMA synchronous=NORMAL');
          await d.execute('PRAGMA cache_size=-2000');
          await d.execute('PRAGMA temp_store=MEMORY');
        } catch (_) {}
      });

  /// نسخة احتياطية يومية (مرة في اليوم) في فولدر التطبيق، وبنحتفظ بآخر [backup_keep] نسخة. الإعداد «نسخة احتياطية تلقائية» بيتحكّم فيها.
  Future<void> _autoBackup() async {
    try {
      await Future<void>.delayed(const Duration(seconds: 8)); // نسيب الأجهزة الضعيفة تفتح الأول
      if ((await getSetting('auto_backup')) == 'لا') return;
      final keep = int.tryParse(await getSetting('backup_keep')) ?? 14;
      final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'auto_backups'));
      await dir.create(recursive: true);
      final n = DateTime.now();
      final out = File(p.join(dir.path, 'auto_${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}.db'));
      if (await out.exists()) return;
      await db.execute('PRAGMA wal_checkpoint(FULL)').catchError((_) {});
      final tmp = File('${out.path}.tmp');
      await File(path).copy(tmp.path);
      await tmp.rename(out.path); // بنسمّيها بعد ما تكتمل عشان مفيش نسخة نص نص
      final files = [for (final e in await dir.list().toList()) if (e is File && e.path.endsWith('.db')) e]..sort((a, b) => a.path.compareTo(b.path));
      for (var i = 0; i < files.length - keep.clamp(3, 60); i++) {
        await files[i].delete();
      }
    } catch (_) {}
  }

  Future<void> _init() async {
    final ver = Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')) ?? 0;
    if (ver < _schemaVersion) {
      final b = db.batch();
      for (final s in _schema) {
        b.execute(s);
      }
      await b.commit(noResult: true);
      final have = <String, Set<String>>{};
      for (final c in _upgradeCols) {
        final cols = have[c[0]] ??= {for (final r in await db.rawQuery('PRAGMA table_info(${c[0]})')) r['name'].toString()};
        if (!cols.contains(c[1])) {
          await db.execute('ALTER TABLE ${c[0]} ADD COLUMN ${c[1]} ${c[2]}');
          cols.add(c[1]);
        }
      }
      final sb = db.batch();
      for (final e in defaultSettings.entries) {
        sb.insert('settings', {'key': e.key, 'value': e.value}, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await sb.commit(noResult: true);
      // مرة واحدة: مسح بيانات الشركة التجريبية اللي كانت متسجلة تلقائي في الإيصال الإنجليزي
      final done = await db.query('settings', where: "key='en_defaults_cleared'");
      if (done.isEmpty) {
        const old = {
          'en_brand': 'ELASELL', 'en_brand_sub': 'Company', 'en_address': 'No. 1 Bompai Road, P.M.B. 3023\nKano, Nigeria',
          'en_acc_no': '9035597582', 'en_acc_name': 'SHERIF MAHMOUD ABDELGANIYU MOHAMED', 'en_bank': 'MONIEPOINT MICRO FINANCE BANK',
          'en_whatsapp': '09035597582 / 07083065940',
        };
        for (final e in old.entries) {
          await db.update('settings', {'value': ''}, where: 'key=? AND value=?', whereArgs: [e.key, e.value]);
        }
        await db.insert('settings', {'key': 'en_defaults_cleared', 'value': '1'}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    final u = await db.query('users', where: "user_id='admin'");
    if (u.isEmpty) {
      await db.insert('users', {'user_id': 'admin', 'password': await compute(hashPwArg, defaultAdminPw), 'role': 'Admin'});
    }
    if (ver < _schemaVersion) {
      // أكواد للأصناف/الموردين/... القديمة بدون كود
      for (final t in _codeTables.entries) {
        final rows = await db.rawQuery("SELECT id FROM ${t.key} WHERE IFNULL(code,'')='' ORDER BY id");
        for (final r in rows) {
          await db.update(t.key, {'code': await nextCode(t.value, t.key, 'code')}, where: 'id=?', whereArgs: [r['id']]);
        }
      }
      await db.execute('PRAGMA user_version = $_schemaVersion');
    }
  }

  static const _codeTables = {'products': 'P', 'suppliers': 'S', 'partners': 'M', 'representatives': 'R', 'branches': 'B'};

  // ---------------------------------------------------------------- إعدادات
  final Map<String, String> _sc = {}; // كاش الإعدادات في الذاكرة
  Future<String> getSetting(String k) async {
    final hit = _sc[k];
    if (hit != null) return hit;
    final r = await db.query('settings', where: 'key=?', whereArgs: [k]);
    if (r.isEmpty) return defaultSettings[k] ?? '';
    return _sc[k] = (r.first['value'] ?? '').toString();
  }

  /// قراءة فورية من الكاش (بعد warmSettings) — للرسائل والنصوص اللي مش بتستنى async
  String cached(String k) => _sc[k] ?? defaultSettings[k] ?? '';

  Future<void> warmSettings() async {
    for (final r in await db.query('settings')) {
      _sc[(r['key'] ?? '').toString()] = (r['value'] ?? '').toString();
    }
  }

  Future<int> getInt(String k, [int d = 0]) async {
    try {
      return parseNum(await getSetting(k), d.toDouble()).toInt();
    } catch (_) {
      return d;
    }
  }

  Future<void> setSetting(String k, String v) async {
    await db.insert('settings', {'key': k, 'value': v}, conflictAlgorithm: ConflictAlgorithm.replace);
    _sc[k] = v;
  }

  // ---------------------------------------------------------------- كلمة السر
  Future<bool> verifyAdmin(String pw) async {
    final r = await db.query('users', columns: ['password'], where: "user_id='admin'");
    if (r.isEmpty) return false;
    final ok = await compute(checkPwArgs, [r.first['password'].toString(), pw]);
    if (ok && needsRehash(r.first['password'].toString())) {
      compute(hashPwArg, normPw(pw)).then((h) => db.update('users', {'password': h}, where: "user_id='admin'"), onError: (_) => 0);
    }
    return ok;
  }

  Future<void> setAdminPassword(String pw) async {
    await db.update('users', {'password': await compute(hashPwArg, pw)}, where: "user_id='admin'");
    await log('تغيير كلمة سر المدير');
  }

  Future<void> log(String action, [String details = '']) => logIn(db, action, details);

  /// نفس log بس جوه transaction موجودة (عشان السجل يتحفظ أو يتلغي مع العملية نفسها)
  Future<void> logIn(DatabaseExecutor ex, String action, [String details = '']) => ex.insert('audit_log', {
        'ts': DateTime.now().toIso8601String().substring(0, 19).replaceFirst('T', ' '),
        'action': action, 'details': details, 'who': who,
      });

  /// السماح بالرصيد السالب — بتتقرا من نفس الـtransaction (القراءة من db جوّاها بتعلّق التطبيق)
  Future<bool> allowNegIn(DatabaseExecutor ex) async {
    final r = await ex.query('settings', columns: ['value'], where: 'key=?', whereArgs: ['allow_negative_stock']);
    final v = r.isEmpty ? (defaultSettings['allow_negative_stock'] ?? 'لا') : (r.first['value'] ?? '').toString();
    return v == 'نعم';
  }

  Future<int> _graceIn(DatabaseExecutor? ex) async {
    if (ex == null) return getInt('grace_days', 0);
    final r = await ex.query('settings', columns: ['value'], where: 'key=?', whereArgs: ['grace_days']);
    final v = r.isEmpty ? (defaultSettings['grace_days'] ?? '0') : (r.first['value'] ?? '0').toString();
    try {
      return parseNum(v, 0).toInt();
    } catch (_) {
      return 0;
    }
  }

  // ---------------------------------------------------------------- أكواد
  Future<String> nextCode(String letter, String table, String col, [DatabaseExecutor? ex]) async {
    final rows = await (ex ?? db).rawQuery('SELECT $col AS c FROM $table');
    var mx = 0;
    for (final r in rows) {
      final n = codeNum(r['c']?.toString(), letter);
      if (n != null && n > mx) mx = n;
    }
    return '$letter${mx + 1}';
  }

  /// كود العميل التالي: عداد واحد لكل العملاء (عربي وإنجليزي)، بيكمّل على أعلى رقم موجود
  /// بنفس شكل الكود (لو آخر كود «3» الجاي «4»، ولو «C7» الجاي «C8»).
  Future<String> nextCustomerCode([DatabaseExecutor? ex]) async {
    final rows = await (ex ?? db).rawQuery('SELECT customer_code AS c FROM customers');
    final re = RegExp(r'^([A-Za-z]*-?)(0*)(\d+)$');
    var mx = 0, width = 0;
    var prefix = 'C';
    for (final r in rows) {
      final m = re.firstMatch((r['c'] ?? '').toString().trim());
      if (m == null) continue;
      final n = int.tryParse(m[3]!);
      if (n == null || n < mx) continue;
      if (n == mx && mx != 0) continue;
      mx = n;
      prefix = m[1]!;
      width = m[2]!.isEmpty ? 0 : m[2]!.length + m[3]!.length;
    }
    if (mx == 0 && rows.isEmpty) return 'C1';
    var next = '${mx + 1}';
    if (width > next.length) next = next.padLeft(width, '0');
    var code = '$prefix$next';
    // أمان: لو الكود موجود فعلاً بنزوّد لحد أول كود فاضي
    final all = {for (final r in rows) (r['customer_code'] ?? '').toString().trim()};
    var k = mx + 1;
    while (all.contains(code)) {
      k++;
      code = '$prefix${'$k'.padLeft(width, '0')}';
    }
    return code;
  }

  // ---------------------------------------------------------------- العملاء + المالية
  /// مالية العملاء. [ex] = transaction شغّالة (لازم تتمرّر لو بتتنادى من جواها وإلا التطبيق يتعلّق).
  /// النتيجة الكاملة (كل العملاء) بتتخزّن لحد أول تغيير في البيانات أو تغيّر اليوم أو مدة السماح.
  Future<List<CustFin>> financials({DateTime? asOf, String? code, DatabaseExecutor? ex}) async {
    final useCache = asOf == null && code == null && ex == null;
    final ver = _dataVer;
    asOf ??= today();
    final grace = await _graceIn(ex);
    final day = isoDate(asOf);
    final fc = _finCache;
    if (useCache && fc != null && _finVer == ver && _finDay == day && _finGrace == grace) {
      return List<CustFin>.of(fc);
    }
    final DatabaseExecutor q = ex ?? db;
    final paid = <String, double>{};
    // لو بنحسب عميل واحد: بنجمّع دفعاته هو بس (كان بيجمّع جدول الدفعات كله مع كل عملية)
    final sums = code == null
        ? await q.rawQuery(
            "SELECT customer_code c, IFNULL(SUM(amount_paid),0) s FROM payments WHERE IFNULL(due_month,'') != ? GROUP BY customer_code",
            [downLabel])
        : await q.rawQuery(
            "SELECT customer_code c, IFNULL(SUM(amount_paid),0) s FROM payments WHERE customer_code=? AND IFNULL(due_month,'') != ? GROUP BY customer_code",
            [code, downLabel]);
    for (final r in sums) {
      paid[r['c'].toString()] = (r['s'] as num).toDouble();
    }
    final rows = code == null
        ? await q.query('customers', orderBy: 'rowid')
        : await q.query('customers', where: 'customer_code=?', whereArgs: [code]);
    List<CustFin> out;
    if (rows.length > 400) {
      final plain = [for (final r in rows) Map<String, Object?>.from(r)];
      out = await compute(_computeAll, _FinJob(plain, paid, asOf, grace));
    } else {
      out = [for (final r in rows) computeFin(r, paid[r['customer_code'].toString()] ?? 0, asOf, grace)];
    }
    if (useCache) {
      _finCache = out;
      _finVer = ver;
      _finDay = day;
      _finGrace = grace;
      return List<CustFin>.of(out);
    }
    return out;
  }

  Future<void> syncRemaining(DatabaseExecutor tx, String code) async {
    final f = await financials(code: code, ex: tx);
    if (f.isNotEmpty) {
      await tx.update('customers', {'remaining_amount': f.first.remaining}, where: 'customer_code=?', whereArgs: [code]);
    }
    bumpData();
  }

  String cleanPhone(String? phone) {
    final s = trDigits(phone ?? '').trim();
    if (s.isEmpty) return '';
    final d = s.replaceAll(RegExp(r'\D'), '');
    if (d.length < 7 || d.length > 15) throw const FormatException('رقم الموبايل لازم يكون من 7 لـ 15 رقم');
    return s;
  }

  /// [inTx]: شغل إضافي بيتنفّذ جوه نفس الـtransaction (مثلاً تسجيل إن الملف اتطبّق) — لو فشل العقد كله بيتلغي
  Future<String> addCustomer(Map<String, dynamic> d, {Future<void> Function(DatabaseExecutor tx, String code)? inTx}) async {
    final name = (d['name'] ?? '').toString().trim();
    if (name.isEmpty) throw const FormatException('اكتب اسم العميل الأول.');
    var total = (d['total'] ?? 0).toDouble();
    if (total <= 0 && d['items'] is List) {
      total = (d['items'] as List).fold<double>(0, (a, it) => a + ((it as Map)['qty'] as num).toDouble() * ((it['price'] ?? 0) as num).toDouble());
    }
    final down = (d['down'] ?? 0).toDouble();
    var months = (d['months'] ?? 0).toInt();
    final plan = parsePlan(d['plan']?.toString());
    if (plan.isNotEmpty) months = plan.fold<int>(0, (s, e) => s + (e[0] as int));
    if (total <= 0) throw const FormatException('إجمالي البضاعة لازم يكون أكبر من صفر.');
    if (down < 0 || down > total) throw const FormatException('المقدم لازم يكون من صفر لحد إجمالي البضاعة.');
    if (months <= 0 || months > 120) throw const FormatException('عدد الشهور لازم يكون رقم صحيح من 1 لـ 120.');
    if (plan.isNotEmpty) {
      final ptot = r2(plan.fold<double>(0, (s, e) => s + (e[0] as int) * (e[1] as num)));
      if (!planTotalOk(ptot, r2(total - down))) {
        throw FormatException('مجموع التقسيط المتدرّج (${fmtMoney(ptot)}) لازم يقارب الإجمالي − المقدم (${fmtMoney(total - down)}).');
      }
    }
    final phone = cleanPhone(d['phone']?.toString());
    final code = (d['code'] ?? '').toString().trim().isNotEmpty ? d['code'].toString().trim() : await nextCustomerCode();
    if ((await db.query('customers', where: 'customer_code=?', whereArgs: [code])).isNotEmpty) {
      throw FormatException('كود العميل $code موجود قبل كده، غيّر الكود.');
    }
    final rem = r2(total - down);
    final monthly = rem > 0 ? r2(rem / months) : 0.0;
    final start = d['start'] != null ? (toDate(d['start']) ?? today()) : today();
    final first = d['first_due'] != null ? (toDate(d['first_due']) ?? addMonths(start, 1)) : addMonths(start, 1);
    // بنود العقد: كل صنف (كود/اسم، كمية، سعر). الطريقة القديمة (صنف واحد) بتتحوّل لبند.
    final items = <Map<String, dynamic>>[
      for (final it in ((d['items'] as List?) ?? const [])) Map<String, dynamic>.from(it as Map),
    ];
    final sp = d['stock_pid'], sq = ((d['stock_qty'] ?? 0) as num).toInt();
    if (items.isEmpty && sp != null && sq > 0) {
      final pr = await db.query('products', columns: ['name'], where: 'id=?', whereArgs: [sp]);
      items.add({'pid': sp, 'name': pr.isEmpty ? (d['item'] ?? '').toString() : pr.first['name'], 'qty': sq, 'price': r2(total / sq)});
    }
    final tracked = await trackStock();
    final allowNeg = d['force_stock'] == true || await getSetting('allow_negative_stock') == 'نعم';
    final custodyRep = (d['custody_rep'] ?? '').toString().trim();
    // خيار «المحصّل = المندوب اللي باع»: بيشتغل بس لو مفيش محصّل متحدد للعميل ولو فيه مندوب، وإلا بنسيب الخانة زي ما هي
    var collName = (d['collector'] ?? '').toString().trim();
    final repName0 = (d['rep'] ?? '').toString().trim();
    if (collName.isEmpty && repName0.isNotEmpty && await getSetting('rep_is_collector') == 'نعم') collName = repName0;
    final saleDate = isoDate(start);
    await db.transaction((tx) async {
      final lines = <Map<String, Object?>>[];
      for (final it in items) {
        final pid = it['pid'] == null ? null : (it['pid'] as num).toInt();
        final q = ((it['qty'] ?? 0) as num).toInt();
        if (q <= 0) continue;
        final price = ((it['price'] ?? 0) as num).toDouble();
        var fromStock = it.containsKey('stock_qty') ? ((it['stock_qty'] ?? 0) as num).toInt() : q;
        var pname = (it['name'] ?? '').toString();
        if (pid != null && tracked) {
          if (custodyRep.isNotEmpty) {
            final used = await _consumeCustody(tx, custodyRep, pname, q, pid, code);
            fromStock = q - used;
          }
          if (fromStock > 0) await _stockMove(tx, pid, -fromStock, 'بيع', ref: 'عميل $code', notes: name, allowNeg: allowNeg);
        } else {
          fromStock = 0;
        }
        lines.add({
          'customer_code': code, 'product_id': pid, 'product_name': pname, 'qty': q, 'unit_price': price, 'line_total': r2(price * q),
          'stock_qty': fromStock, 'returned_qty': 0, 'sold_at': saleDate, 'rep_name': (d['rep'] ?? '').toString().trim(),
        });
      }
      await tx.insert('customers', {
        'customer_code': code, 'name': name, 'phone': phone, 'address': (d['address'] ?? '').toString().trim(),
        'region': (d['region'] ?? '').toString().trim(), 'rep_name': (d['rep'] ?? '').toString().trim(),
        'total_amount': total, 'down_payment': down, 'monthly_installment': monthly, 'remaining_amount': rem,
        'months_count': months, 'item_desc': (d['item'] ?? '').toString().trim().isNotEmpty ? (d['item'] ?? '').toString().trim() : itemsDesc(items), 'start_date': isoDate(start), 'collector_name': collName,
        'first_due_date': isoDate(first), 'plan_text': planText(plan), 'branch': (d['branch'] ?? '').toString(),
        if (_okGeo(d['lat'], d['lng'])) ...{'lat': (d['lat'] as num).toDouble(), 'lng': (d['lng'] as num).toDouble()},
        'en_name': (d['en_name'] ?? '').toString().trim(), 'en_address': (d['en_address'] ?? '').toString().trim(), 'en_item': (d['en_item'] ?? '').toString().trim(),
      });
      for (final l in lines) {
        await tx.insert('customer_items', l);
      }
      if (down > 0) {
        await tx.insert('payments', {
          'customer_code': code, 'customer_name': name, 'amount_paid': down, 'pay_date': isoDate(start),
          'due_month': downLabel, 'collector': (d['down_collector'] ?? 'مدير النظام').toString(), 'notes': 'مقدم نقدي',
        });
      }
      await tx.insert('audit_log', {
        'ts': DateTime.now().toIso8601String().substring(0, 19).replaceFirst('T', ' '), 'action': 'إضافة عميل',
        'details': '$code - $name - إجمالي ${fmtMoney(total)} - مقدم ${fmtMoney(down)} - $months شهر', 'who': who,
      });
      if (inTx != null) await inTx(tx, code);
    });
    bumpData();
    return code;
  }

  Future<void> updateCustomer(String code, Map<String, dynamic> d) async {
    await db.transaction((tx) => updateCustomerIn(tx, code, d));
    bumpData();
  }

  /// تعديل عميل جوه transaction موجودة (التحقق والكتابة والسجل كلهم في نفس العملية)
  Future<void> updateCustomerIn(DatabaseExecutor ex, String code, Map<String, dynamic> d) async {
    final cur = await financials(code: code, ex: ex);
    if (cur.isEmpty) throw const FormatException('العميل مش موجود.');
    final old = cur.first;
    final name = (d['name'] ?? old.name).toString().trim();
    if (name.isEmpty) throw const FormatException('اسم العميل مينفعش يبقى فاضي.');
    final total = (d['total'] ?? old.total).toDouble();
    final down = (d['down'] ?? old.down).toDouble();
    var months = (d['months'] ?? old.months).toInt();
    final plan = parsePlan((d['plan'] ?? old.plan).toString());
    final pt = planText(plan);
    if (plan.isNotEmpty) months = plan.fold<int>(0, (s, e) => s + (e[0] as int));
    if (total <= 0) throw const FormatException('إجمالي البضاعة لازم يكون أكبر من صفر.');
    if (down < 0 || down > total) throw const FormatException('المقدم لازم يكون من صفر لحد إجمالي البضاعة.');
    if (months <= 0 || months > 120) throw const FormatException('عدد الشهور لازم يكون رقم صحيح من 1 لـ 120.');
    if (plan.isNotEmpty) {
      final ptot = r2(plan.fold<double>(0, (s, e) => s + (e[0] as int) * (e[1] as num)));
      if (!planTotalOk(ptot, r2(total - down))) {
        throw FormatException('مجموع التقسيط المتدرّج (${fmtMoney(ptot)}) لازم يقارب الإجمالي − المقدم.');
      }
    }
    if (pt != planText(parsePlan(old.plan)) && old.paidInst > 0.004) {
      throw const FormatException('مينفعش تغيّر خطة التقسيط المتدرّج لأن العميل دفع أقساط.');
    }
    if (r2(down + old.paidInst) > r2(total + 0.001)) {
      throw FormatException('المدفوع فعلاً (${fmtMoney(down + old.paidInst)}) أكبر من الإجمالي الجديد.');
    }
    if (months != old.months && old.paidInst > 0.004) {
      throw FormatException('مينفعش تغيّر عدد الشهور لأن العميل دفع أقساط (${fmtMoney(old.paidInst)} جنيه).');
    }
    final phone = cleanPhone((d['phone'] ?? old.phone).toString());
    final rem = r2(total - down);
    final monthly = rem > 0 ? r2(rem / months) : 0.0;
    await ex.update('customers', {
      'name': name, 'phone': phone, 'address': (d['address'] ?? old.address).toString().trim(),
      'region': (d['region'] ?? old.region).toString().trim(), 'rep_name': (d['rep'] ?? old.rep).toString().trim(),
      'item_desc': (d['item'] ?? old.item).toString().trim(), 'collector_name': (d['collector'] ?? old.collector).toString().trim(), 'total_amount': total, 'down_payment': down,
      'monthly_installment': monthly, 'months_count': months, 'plan_text': pt,
      if (toDate(d['start']) != null) 'start_date': isoDate(toDate(d['start'])!),
      if (toDate(d['first_due']) != null) 'first_due_date': isoDate(toDate(d['first_due'])!),
      // الموقع: لو المفتاح موجود بنحدّثه (null = مسح الموقع)، ولو مش موجود مبنلمسوش
      if (d.containsKey('en_name')) 'en_name': (d['en_name'] ?? '').toString().trim(),
      if (d.containsKey('en_address')) 'en_address': (d['en_address'] ?? '').toString().trim(),
      if (d.containsKey('en_item')) 'en_item': (d['en_item'] ?? '').toString().trim(),
      if (d.containsKey('lat')) ...{
        'lat': _okGeo(d['lat'], d['lng']) ? (d['lat'] as num).toDouble() : null,
        'lng': _okGeo(d['lat'], d['lng']) ? (d['lng'] as num).toDouble() : null,
      },
    }, where: 'customer_code=?', whereArgs: [code]);
    final row = await ex.query('payments', columns: ['id'], where: 'customer_code=? AND due_month=?', whereArgs: [code, downLabel]);
    if (down > 0 && row.isNotEmpty) {
      await ex.update('payments', {'amount_paid': down, 'customer_name': name}, where: 'id=?', whereArgs: [row.first['id']]);
    } else if (down > 0) {
      await ex.insert('payments', {
        'customer_code': code, 'customer_name': name, 'amount_paid': down, 'pay_date': isoDate(today()),
        'due_month': downLabel, 'collector': 'مدير النظام', 'notes': 'مقدم نقدي',
      });
    } else if (row.isNotEmpty) {
      await ex.delete('payments', where: 'id=?', whereArgs: [row.first['id']]);
    }
    if (name != old.name) {
      await ex.update('payments', {'customer_name': name}, where: 'customer_code=?', whereArgs: [code]);
    }
    await syncRemaining(ex, code);
    await logIn(ex, 'تعديل عميل', '$code - $name');
  }

  static bool _okGeo(Object? lat, Object? lng) =>
      lat is num && lng is num && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180 && !(lat == 0 && lng == 0);

  /// موقع عميل على الخريطة (null لو ما اتحددش)
  Future<({double lat, double lng})?> customerLocation(String code) async {
    final r = await db.query('customers', columns: ['lat', 'lng'], where: 'customer_code=?', whereArgs: [code]);
    if (r.isEmpty || !_okGeo(r.first['lat'], r.first['lng'])) return null;
    return (lat: (r.first['lat'] as num).toDouble(), lng: (r.first['lng'] as num).toDouble());
  }

  /// مواقع كل العملاء اللي ليهم موقع (كود ← إحداثيات) — لعلامة الدبوس في القايمة
  Future<Map<String, ({double lat, double lng})>> customerLocations() async {
    final r = await db.query('customers', columns: ['customer_code', 'lat', 'lng'], where: 'lat IS NOT NULL AND lng IS NOT NULL');
    return {
      for (final x in r)
        if (_okGeo(x['lat'], x['lng'])) x['customer_code'].toString(): (lat: (x['lat'] as num).toDouble(), lng: (x['lng'] as num).toDouble()),
    };
  }

  Future<void> setCustomerLocation(String code, double? lat, double? lng) async {
    final ok = _okGeo(lat, lng);
    await db.update('customers', {'lat': ok ? lat : null, 'lng': ok ? lng : null}, where: 'customer_code=?', whereArgs: [code]);
    await log(ok ? 'تحديد موقع عميل' : 'مسح موقع عميل', code);
    bumpData();
  }

  Future<void> deleteCustomer(String code) async {
    // كل حاجة (القراءة والإرجاع للمخزن والحذف والسجل) في عملية واحدة: يا تكتمل كلها يا تتلغي كلها
    await db.transaction((tx) async {
      final r = await tx.query('customers', columns: ['name'], where: 'customer_code=?', whereArgs: [code]);
      if (r.isEmpty) throw const FormatException('العميل مش موجود.');
      final s = await tx.rawQuery('SELECT COUNT(*) n, IFNULL(SUM(amount_paid),0) s FROM payments WHERE customer_code=?', [code]);
      final its = await tx.query('customer_items', where: 'customer_code=?', whereArgs: [code]);
      final pm = await tx.query('settings', columns: ['value'], where: 'key=?', whereArgs: ['product_mode']);
      final mode = pm.isEmpty ? (defaultSettings['product_mode'] ?? '') : (pm.first['value'] ?? '').toString();
      if (mode == 'منتجات المخزن') {
        for (final it in its) {
          final back = (((it['stock_qty'] ?? 0) as num).toInt()) - (((it['returned_qty'] ?? 0) as num).toInt());
          if (it['product_id'] != null && back > 0) {
            final ex = await tx.query('products', columns: ['id'], where: 'id=?', whereArgs: [it['product_id']]);
            if (ex.isNotEmpty) await _stockMove(tx, (it['product_id'] as num).toInt(), back, 'إلغاء بيع', ref: 'حذف عميل $code', allowNeg: true);
          }
        }
      }
      await tx.delete('customer_items', where: 'customer_code=?', whereArgs: [code]);
      await tx.delete('payments', where: 'customer_code=?', whereArgs: [code]);
      await tx.delete('customers', where: 'customer_code=?', whereArgs: [code]);
      await logIn(tx, 'حذف عميل', '$code - ${r.first['name']} (و${s.first['n']} دفعة بإجمالي ${fmtMoney(s.first['s'] as num)})');
    });
    bumpData();
  }

  // ---------------------------------------------------------------- الدفعات
  Future<List<Map<String, Object?>>> customerPayments(String code) =>
      db.rawQuery('SELECT id, pay_date, amount_paid, due_month, collector, notes FROM payments WHERE customer_code=? ORDER BY pay_date, id', [code]);

  /// تسجيل قسط: التحقق والدفعة وتحديث المتبقي والسجل (وأي شغل في [inTx]) في عملية واحدة.
  Future<double> addPayment(String code, double amount,
      {String collector = '', String notes = 'قسط شهري', String? dueMonth, String? payDate, Future<void> Function(DatabaseExecutor tx)? inTx}) async {
    final amt = r2(amount);
    if (amt <= 0) throw const FormatException('المبلغ لازم يكون أكبر من صفر.');
    final n = today();
    final due = dueMonth ?? '${n.month.toString().padLeft(2, '0')}-${n.year}';
    final pd = payDate ?? isoDate(n);
    await db.transaction((tx) async {
      final fin = await financials(code: code, ex: tx);
      if (fin.isEmpty) throw const FormatException('العميل مش موجود.');
      final c = fin.first;
      if (c.remaining <= 0) throw const FormatException('العميل ده مسدد بالكامل.');
      if (amt > c.remaining + 0.009) {
        throw FormatException('المبلغ (${fmtMoney(amt)}) أكبر من المتبقي على العميل (${fmtMoney(c.remaining)}).');
      }
      await tx.insert('payments', {
        'customer_code': code, 'customer_name': c.name, 'amount_paid': amt, 'pay_date': pd,
        'due_month': due, 'collector': collector.isEmpty ? 'مدير النظام' : collector, 'notes': notes,
      });
      await syncRemaining(tx, code);
      await logIn(tx, 'تحصيل قسط', '$code - ${c.name} - ${fmtMoney(amt)} - $collector');
      if (inTx != null) await inTx(tx);
    });
    return amt;
  }

  Future<void> deletePayment(int id) async {
    await db.transaction((tx) async {
      final r = await tx.query('payments', where: 'id=?', whereArgs: [id]);
      if (r.isEmpty) throw const FormatException('الدفعة مش موجودة.');
      if (r.first['due_month'] == downLabel) throw const FormatException('دي دفعة المقدم، عدّلها من تعديل بيانات العميل.');
      await tx.delete('payments', where: 'id=?', whereArgs: [id]);
      await syncRemaining(tx, r.first['customer_code'].toString());
      await logIn(tx, 'حذف دفعة', '${r.first['customer_code']} - ${r.first['customer_name']} - ${fmtMoney(r.first['amount_paid'] as num)}');
    });
  }

  // ---------------------------------------------------------------- المخزن
  Future<bool> trackStock() async => (await getSetting('product_mode')) == 'منتجات المخزن';

  /// نفس trackStock بس بتقرا من الـtransaction الجارية
  Future<bool> trackStockIn(DatabaseExecutor ex) async {
    final r = await ex.query('settings', columns: ['value'], where: 'key=?', whereArgs: ['product_mode']);
    final v = r.isEmpty ? (defaultSettings['product_mode'] ?? '') : (r.first['value'] ?? '').toString();
    return v == 'منتجات المخزن';
  }

  Future<int> _stockMove(DatabaseExecutor tx, int pid, int delta, String kind, {String ref = '', String notes = '', bool? allowNeg}) async {
    final r = await tx.query('products', columns: ['name', 'qty'], where: 'id=?', whereArgs: [pid]);
    if (r.isEmpty) throw const FormatException('الصنف مش موجود في المخزن.');
    final name = r.first['name'].toString();
    final qty = ((r.first['qty'] ?? 0) as num).toInt();
    final nw = qty + delta;
    if (nw < 0 && !(allowNeg ?? await allowNegIn(tx))) {
      throw FormatException("رصيد '$name' في المخزن ($qty) مش كفاية لكمية ${delta.abs()}.");
    }
    await tx.update('products', {'qty': nw}, where: 'id=?', whereArgs: [pid]);
    await tx.insert('stock_moves', {
      'product_id': pid, 'product_name': name, 'kind': kind, 'qty': delta, 'balance_after': nw,
      'move_date': isoDate(today()), 'ref': ref, 'notes': notes,
    });
    return nw;
  }

  /// بيع من عهدة مندوب: بيخصم الكمية من عهدته المفتوحة (مش من رصيد المخزن تاني لأنها اتخصمت وقت تسليم العهدة).
  /// بيرجّع الكمية اللي اتغطّت من العهدة.
  Future<int> _consumeCustody(DatabaseExecutor tx, String rep, String itemName, int qty, int pid, String ref) async {
    final n = normAr(itemName).trim();
    final rows = await tx.query('custody', where: 'rep_name=? AND status=?', whereArgs: [rep, custodyOpen], orderBy: 'id');
    var left = qty, used = 0;
    for (final r in rows) {
      if (left <= 0) break;
      if (normAr((r['item_name'] ?? '').toString()).trim() != n) continue;
      final have = ((r['qty'] ?? 0) as num).toInt();
      if (have <= 0) continue;
      final take = have < left ? have : left;
      final rest = have - take;
      await tx.update('custody', {'qty': rest, if (rest == 0) 'status': custodySold, if (rest == 0) 'returned_date': isoDate(today())}, where: 'id=?', whereArgs: [r['id']]);
      left -= take;
      used += take;
    }
    if (used > 0) {
      final pr = await tx.query('products', columns: ['name', 'qty'], where: 'id=?', whereArgs: [pid]);
      if (pr.isNotEmpty) {
        await tx.insert('stock_moves', {
          'product_id': pid, 'product_name': pr.first['name'], 'kind': 'بيع من عهدة', 'qty': 0, 'balance_after': pr.first['qty'],
          'move_date': isoDate(today()), 'ref': 'عميل $ref', 'notes': 'مندوب $rep — $used قطعة من عهدته',
        });
      }
    }
    return used;
  }

  /// نفس حركة المخزن بس جوه transaction موجودة (للعمليات المركّبة)
  Future<int> stockMoveIn(DatabaseExecutor tx, int pid, int delta, String kind, {String ref = '', String notes = '', bool? allowNeg}) =>
      _stockMove(tx, pid, delta, kind, ref: ref, notes: notes, allowNeg: allowNeg);

  Future<int> stockMove(int pid, int delta, String kind, {String ref = '', String notes = ''}) =>
      db.transaction((tx) => _stockMove(tx, pid, delta, kind, ref: ref, notes: notes));

  // ---------------------------------------------------------------- نسخ احتياطي / استيراد
  Future<String> backupTo(String dir) async {
    final n = DateTime.now();
    final name = 'sales_backup_${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}_${n.hour.toString().padLeft(2, '0')}${n.minute.toString().padLeft(2, '0')}.db';
    final out = p.join(dir, name);
    await db.execute('PRAGMA wal_checkpoint(FULL)').catchError((_) {});
    await File(path).copy(out);
    return out;
  }

  /// استيراد نسخة .db من البرنامج المكتبي: بنستبدل القاعدة الحالية (بعد أخذ نسخة أمان) وبنشغّل الترقية.
  Future<void> importDbFile(String src) async {
    final dir = (await getApplicationDocumentsDirectory()).path;
    await backupTo(dir);
    await db.close();
    await File(src).copy(path);
    db = await _openRaw(path);
    _sc.clear();
    _finCache = null;
    await LicenseSql.relax(db);
    await _init();
    if (licenseEnforced) await LicenseSql.install(db);
    onReopened?.call();
    bumpData();
  }
}
