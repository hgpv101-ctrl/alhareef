// نظام الترخيص السنوي (أوفلاين): ترخيص موقّع رقمياً ومربوط بالجهاز + حماية الوقت من التلاعب + قراءة فقط بعد الانتهاء.
// طبقات الحماية:
//  1) توقيع Ed25519: الكود مينفعش يتألّف من غير المفتاح الخاص (مع المالك بس).
//  2) ربط بالجهاز: الترخيص لجهاز واحد (ANDROID_ID) ومينفعش يتنقل.
//  3) الوقت: أعلى وقت اتشاف (بتوقيع HMAC) محفوظ في مكانين (القاعدة + ملف) + آخر سجل في audit_log؛
//     لو ساعة الجهاز رجعت ورا بأكتر من يوم → قراءة فقط لحد ما الوقت يتصلّح. ولو فيه نت بنتأكد من وقت الإنترنت.
//  3b) وقت الإنترنت بيتقبل بس لما مصدرين مستقلين (جوجل + كلاودفلير) يتطابقوا؛ وفشل فحص الترخيص = قفل (مش آخر حالة).
//  3c) الفحص بيتعمل كمان أول ما التطبيق يرجع من الخلفية.
//  4) قفل كامل: من غير ترخيص ساري (تجربة أو اشتراك) البرنامج مبيفتحش — بتظهر شاشة التفعيل بس.
//     وكمان القراءة فقط على مستوى القاعدة (triggers) كطبقة أمان إضافية.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:android_id/android_id.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'db.dart';
import 'integrity.dart';
import 'license_codec.dart';
import 'license_pub.dart';
import 'license_sql.dart';

/// فحص وقت الإنترنت (طلب HEAD واحد خفيف). لو عايز تقفله خليه false.
const kNetTime = true;
const _tolMs = 3 * 3600 * 1000; // فرق الساعة المسموح قبل ما نعتبرها متلاعب بيها
const _salt = 'hrf.t.2026';

enum LicStatus { none, active, expired, tampered, invalid, modified }

class LicenseGuard extends ChangeNotifier {
  LicenseGuard._();
  static final i = LicenseGuard._();

  LicStatus status = LicStatus.none;
  int daysLeft = 0;
  DateTime? expiry;
  String deviceCode = '';
  Uint8List _dev = Uint8List(8);
  bool ready = false; // خلص أول فحص للترخيص
  bool _started = false, _busy = false, _hasNet = false;
  int _netMs = 0, _audit = 0, _tick = 0, _fails = 0;
  bool _auditLoaded = false;
  Timer? _timer;
  final _sw = Stopwatch();

  bool get canWrite => status == LicStatus.active;
  bool get warnSoon => canWrite && daysLeft <= 30;

  String get message => switch (status) {
        LicStatus.active => daysLeft <= 30 ? 'باقي $daysLeft يوم على انتهاء الاشتراك' : 'الاشتراك ساري',
        LicStatus.expired => 'انتهى الاشتراك أو الفترة المجانية — جدّد عشان تكمّل',
        LicStatus.tampered => 'ساعة الجهاز مش مظبوطة — اطلب كود تصحيح الوقت من المالك',
        LicStatus.invalid => 'الترخيص غير صالح لهذا الجهاز — اطلب كود جديد من المالك',
        LicStatus.modified => 'نسخة التطبيق دي معدّلة أو مش الأصلية — نزّل النسخة الأصلية من المالك',
        LicStatus.none => 'البرنامج غير مفعّل — ابعت كود الجهاز للمالك عشان ياخد فترة مجانية أو اشتراك',
      };

  static const readOnlyText = 'الاشتراك منتهي أو غير مفعّل — البرنامج للقراءة فقط. فعّل أو جدّد الاشتراك من «الاشتراك والترخيص».';

  Future<void> start() async {
    if (_started) return;
    _started = true;
    AppDb.onReopened = () => refresh();
    await _initDevice();
    await refresh();
    ready = true;
    notifyListeners();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      _tick++;
      refresh();
      if (_tick % 360 == 0) _fetchNet().then((_) => refresh());
    });
    unawaited(_fetchNet().then((_) => refresh()));
  }

  // ------------------------------------------------------------- الجهاز
  Future<File> _file(String n) async => File('${(await getApplicationSupportDirectory()).path}/$n');

  Future<String> _fallbackId() async {
    try {
      final s = (await AppDb.i.getSetting('lic_dev_fb')).trim();
      if (s.isNotEmpty) return s;
      final f = await _file('.hrf_d');
      if (await f.exists()) {
        final t = (await f.readAsString()).trim();
        if (t.isNotEmpty) {
          await AppDb.i.setSetting('lic_dev_fb', t);
          return t;
        }
      }
      final r = Random.secure();
      final id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await AppDb.i.setSetting('lic_dev_fb', id);
      await f.writeAsString(id);
      return id;
    } catch (_) {
      return 'unknown';
    }
  }

  Future<void> _initDevice() async {
    String? id;
    try {
      id = await const AndroidId().getId();
    } catch (_) {}
    if (id == null || id.isEmpty) id = await _fallbackId();
    _dev = Uint8List.fromList(sha256.convert(utf8.encode('HRF-DEV|$id')).bytes.sublist(0, 8));
    final h = LicenseCodec.hex(_dev);
    deviceCode = '${h.substring(0, 4)}-${h.substring(4, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}';
  }

  // ------------------------------------------------------------- أعلى وقت اتشاف (HWM)
  String _mac(int ms) => Hmac(sha256, utf8.encode('HRF-HWM|${LicenseCodec.hex(_dev)}|$_salt')).convert(utf8.encode('$ms')).toString().substring(0, 16);
  String _enc(int ms) => '$ms.${_mac(ms)}';
  int? _dec(String? s) {
    if (s == null) return null;
    final p = s.trim().split('.');
    if (p.length != 2) return null;
    final ms = int.tryParse(p[0]);
    return (ms == null || _mac(ms) != p[1]) ? null : ms;
  }

  Future<int> _readHwm() async {
    var m = 0;
    try {
      final a = _dec(await AppDb.i.getSetting('lic_hwm'));
      if (a != null && a > m) m = a;
    } catch (_) {}
    for (final f in await _anchors()) {
      try {
        if (await f.exists()) {
          final b = _dec(await f.readAsString());
          if (b != null && b > m) m = b;
        }
      } catch (_) {}
    }
    return m;
  }

  Future<void> _writeHwm(int ms) async {
    final e = _enc(ms);
    try {
      await AppDb.i.setSetting('lic_hwm', e);
    } catch (_) {}
    for (final f in await _anchors()) {
      try {
        await f.writeAsString(e);
      } catch (_) {}
    }
  }

  /// أماكن متعددة لأعلى وقت اتشاف (مسح واحد منهم مايكفيش): فولدر الدعم + المستندات + الكاش + الفولدر الخارجي الخاص بالتطبيق
  Future<List<File>> _anchors() async {
    final r = <File>[await _file('.hrf_t')];
    try {
      r.add(File('${(await getApplicationDocumentsDirectory()).path}/.hrf_t2'));
    } catch (_) {}
    try {
      r.add(File('${(await getTemporaryDirectory()).path}/.hrf_t3'));
    } catch (_) {}
    try {
      final x = await getExternalStorageDirectory();
      if (x != null) r.add(File('${x.path}/.hrf_t4'));
    } catch (_) {}
    return r;
  }

  Future<int> _auditMax() async {
    try {
      final r = await AppDb.i.db.rawQuery('SELECT MAX(ts) m FROM audit_log');
      final m = r.isEmpty ? null : r.first['m']?.toString();
      if (m == null || m.length < 19) return 0;
      return DateTime.tryParse(m.replaceFirst(' ', 'T'))?.toUtc().millisecondsSinceEpoch ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ------------------------------------------------------------- وقت الإنترنت (اختياري)
  /// وقت الإنترنت من مصدرين مستقلين لازم يتطابقوا (فرق أقل من 10 دقايق) — مصدر واحد متزوّر ما يقدرش يرجّع الوقت ورا.
  Future<int?> _netOne(String url) async {
    HttpClient? c;
    try {
      c = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final req = await c.headUrl(Uri.parse(url)).timeout(const Duration(seconds: 5));
      final res = await req.close().timeout(const Duration(seconds: 5));
      final d = res.headers.value('date');
      if (d == null) return null;
      final ms = HttpDate.parse(d).millisecondsSinceEpoch;
      return ms > 1700000000000 ? ms : null;
    } catch (_) {
      return null;
    } finally {
      c?.close(force: true);
    }
  }

  Future<void> _fetchNet() async {
    if (!kNetTime) return;
    final r = await Future.wait([_netOne('https://www.google.com/generate_204'), _netOne('https://www.cloudflare.com/cdn-cgi/trace')]);
    final a = r[0], b = r[1];
    if (a == null || b == null || (a - b).abs() > 10 * 60 * 1000) return; // مصدر واحد أو مختلفين = مانثقش
    _netMs = a > b ? a : b;
    _sw
      ..reset()
      ..start();
    _hasNet = true;
  }

  // ------------------------------------------------------------- التقييم
  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      await _refresh();
      _fails = 0;
    } catch (_) {
      // فشل الفحص = مانقدرش نتأكد من الترخيص → نقفل (مش نسيب آخر حالة شغّالة)
      if (++_fails >= 2 && status != LicStatus.invalid) {
        status = LicStatus.invalid;
        daysLeft = 0;
        try {
          await LicenseSql.setReadOnly(AppDb.i.db, true);
        } catch (_) {}
        notifyListeners();
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _refresh() async {
    final db = AppDb.i;
    if (!await apkIntegrityOk()) {
      final ch = status != LicStatus.modified;
      status = LicStatus.modified;
      daysLeft = 0;
      expiry = null;
      try {
        await LicenseSql.setReadOnly(db.db, true);
      } catch (_) {}
      if (ch) notifyListeners();
      return;
    }
    final clock = DateTime.now().toUtc().millisecondsSinceEpoch;
    var hwm = await _readHwm();
    if (!_auditLoaded || _tick % 10 == 0) {
      _audit = await _auditMax();
      _auditLoaded = true;
    }
    final ack = int.tryParse(await db.getSetting('lic_audit_ack')) ?? 0;
    final aFloor = _audit > ack ? _audit : 0;
    final floor = hwm > aFloor ? hwm : aFloor;
    int t;
    var tampered = false;
    if (_hasNet) {
      // وقت الإنترنت هو المرجع: لو الأعلى وقت اتشاف عدّاه بأكتر من يوم يبقى كان غلط والنت بيصلّحه
      t = _netMs + _sw.elapsedMilliseconds;
      if (hwm > t + _tolMs) {
        await _writeHwm(t);
        await db.setSetting('lic_audit_ack', '$_audit');
        hwm = t;
      }
    } else {
      tampered = clock < floor - _tolMs;
      t = clock > floor ? clock : floor;
    }
    if (!tampered && t > hwm + 10 * 60 * 1000) await _writeHwm(t);

    final key = (await db.getSetting('lic_key')).trim();
    var st = LicStatus.none;
    var left = 0;
    DateTime? exp;
    if (key.isNotEmpty) {
      final p = LicenseCodec.parse(key, pubB64: kLicensePub);
      if (p == null || !p.sigOk || p.type != 1 || !LicenseCodec.sameBytes(p.device, _dev)) {
        st = LicStatus.invalid;
      } else {
        final today = LicenseCodec.dayOfMs(t);
        exp = LicenseCodec.dateOfDay(p.expiryDay);
        if (tampered || today < p.issueDay - 2) {
          st = LicStatus.tampered;
        } else if (today > p.expiryDay) {
          st = LicStatus.expired;
        } else {
          st = LicStatus.active;
          left = p.expiryDay - today;
        }
      }
    } else if (tampered) {
      st = LicStatus.tampered;
    }
    final changed = st != status || left != daysLeft;
    status = st;
    daysLeft = left;
    expiry = exp;
    try {
      await LicenseSql.setReadOnly(db.db, !canWrite);
    } catch (_) {}
    if (changed) notifyListeners();
  }

  // ------------------------------------------------------------- التفعيل
  Future<String> activate(String input) async {
    final p = LicenseCodec.parse(input, pubB64: kLicensePub);
    if (p == null) throw const FormatException('الكود غير صحيح — انسخه كامل من غير تعديل.');
    if (!p.sigOk) throw const FormatException('الكود ده غير صالح (التوقيع غير صحيح).');
    if (!LicenseCodec.sameBytes(p.device, _dev)) throw const FormatException('الكود ده لجهاز تاني، مش الجهاز ده.');
    final db = AppDb.i;
    if (p.type == 1) {
      final cur = LicenseCodec.parse(await db.getSetting('lic_key'), pubB64: kLicensePub);
      final curOk = cur != null && cur.sigOk && cur.type == 1 && LicenseCodec.sameBytes(cur.device, _dev);
      if (curOk && cur.expiryDay >= p.expiryDay) throw const FormatException('عندك ترخيص أحدث أو مساوي للكود ده.');
      await db.setSetting('lic_key', p.normalized);
      await refresh();
      final d = LicenseCodec.dateOfDay(p.expiryDay);
      final ds = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      if (status == LicStatus.active) return 'تم التفعيل ✅ — الاشتراك ساري لحد $ds';
      if (status == LicStatus.expired) throw FormatException('الترخيص ده منتهي (كان لحد $ds).');
      if (status == LicStatus.tampered) return 'اتحفظ الترخيص، بس ساعة الجهاز مش مظبوطة — اطلب كود تصحيح الوقت من المالك.';
      throw const FormatException('الترخيص مش مطابق للجهاز.');
    }
    if (p.type == 2) {
      final last = int.tryParse(await db.getSetting('lic_rst_serial')) ?? 0;
      if (p.serial <= last) throw const FormatException('كود تصحيح الوقت ده اتستخدم قبل كده.');
      await _writeHwm((p.issueDay + kLicEpochDay) * 86400000);
      _audit = await _auditMax();
      await db.setSetting('lic_audit_ack', '$_audit');
      await db.setSetting('lic_rst_serial', '${p.serial}');
      await refresh();
      return 'تم تصحيح الوقت ✅';
    }
    throw const FormatException('نوع الكود غير معروف.');
  }
}
