// ملف المندوب/المحصّل: تسجيل في الميدان ← تصدير ← مراجعة المالك ← توزيع تلقائي
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../core/receipt_data.dart';
import '../core/utils.dart';
import 'db.dart';
import 'ops.dart';

const kinds = {'sale': 'بيع', 'collect': 'تحصيل'};

class RepEntry {
  RepEntry({
    required this.uid, required this.kind, required this.ts, this.custRef = '', this.name = '', this.phone = '', this.address = '',
    this.region = '', this.item = '', this.total = 0, this.down = 0, this.months = 0, this.plan = '', this.amount = 0,
    this.payDate = '', this.notes = '', this.qty = 0, this.lat, this.lng, List<Map<String, dynamic>>? items,
  }) : items = items ?? [];
  String uid, kind, ts, custRef, name, phone, address, region, item, plan, payDate, notes;
  double total, down, amount;
  double? lat, lng; // موقع العميل (اختياري) من الخريطة
  int months, qty;
  /// بنود البيع: [{code, name, qty, price}] — بتتربط بالمخزن عند المالك
  List<Map<String, dynamic>> items;

  Map<String, Object?> toJson() => {
        'uid': uid, 'kind': kind, 'ts': ts, 'cust_ref': custRef, 'name': name, 'phone': phone, 'address': address, 'region': region,
        'item': item, 'total': total, 'down': down, 'months': months, 'plan': plan, 'amount': amount, 'pay_date': payDate,
        'notes': notes, 'qty': qty,
        if (items.isNotEmpty) 'items': items,
        if (lat != null && lng != null) ...{'lat': lat, 'lng': lng},
      };

  static double _d(Object? v) => v is num ? v.toDouble() : (double.tryParse(trDigits((v ?? '').toString())) ?? 0);

  /// بيوحّد شكل البنود (عشان البصمة تطلع واحدة عند التصدير والاستيراد)
  static List<Map<String, dynamic>> normItems(Object? raw) {
    if (raw is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final q = _d(e['qty']).toInt();
      if (q <= 0) continue;
      out.add({'code': (e['code'] ?? '').toString(), 'name': (e['name'] ?? '').toString(), 'qty': q, 'price': _d(e['price'])});
    }
    return out;
  }

  factory RepEntry.fromJson(Map<String, dynamic> j) => RepEntry(
        uid: (j['uid'] ?? '').toString(), kind: (j['kind'] ?? '').toString(), ts: (j['ts'] ?? '').toString(),
        custRef: (j['cust_ref'] ?? '').toString(), name: (j['name'] ?? '').toString(), phone: (j['phone'] ?? '').toString(),
        address: (j['address'] ?? '').toString(), region: (j['region'] ?? '').toString(), item: (j['item'] ?? '').toString(),
        total: _d(j['total']), down: _d(j['down']), months: _d(j['months']).toInt(), plan: (j['plan'] ?? '').toString(),
        amount: _d(j['amount']), payDate: (j['pay_date'] ?? '').toString(), notes: (j['notes'] ?? '').toString(), qty: _d(j['qty']).toInt(),
        items: normItems(j['items']),
        lat: j['lat'] is num ? (j['lat'] as num).toDouble() : null, lng: j['lng'] is num ? (j['lng'] as num).toDouble() : null,
      );

  factory RepEntry.fromRow(Map<String, Object?> r) {
    Object? its;
    final raw = (r['items_json'] ?? '').toString();
    if (raw.isNotEmpty) {
      try {
        its = jsonDecode(raw);
      } catch (_) {}
    }
    return RepEntry.fromJson({...r, 'items': its});
  }
  String get title => kind == 'sale' ? 'بيع: $name — ${fmtMoney(total)}' : 'تحصيل: ${name.isEmpty ? custRef : name} — ${fmtMoney(amount)}';
}

String entriesChecksum(List<Map<String, Object?>> entries) => sha256.convert(utf8.encode(jsonEncode(entries))).toString();

class RepFile {
  RepFile({required this.batchId, required this.repName, required this.role, required this.createdAt, required this.entries, this.checksum = '', this.checksumOk = true, this.fileName = ''});
  String batchId, repName, role, createdAt, checksum, fileName;
  bool checksumOk;
  List<RepEntry> entries;

  static RepFile parse(String text, {String fileName = ''}) {
    final Object? j;
    try {
      j = jsonDecode(text);
    } catch (_) {
      throw const FormatException('الملف مش بصيغة صحيحة (مش ملف الحريف أو اتبوّظ).');
    }
    if (j is! Map<String, dynamic> || j['type'] != 'rep_report') throw const FormatException('ده مش ملف تقرير مندوب من الحريف.');
    final raw = (j['entries'] as List? ?? []).cast<Map<String, dynamic>>();
    final cs = (j['checksum'] ?? '').toString();
    final calc = entriesChecksum([for (final e in raw) RepEntry.fromJson(e).toJson()]);
    return RepFile(
      batchId: (j['batch_id'] ?? '').toString(), repName: (j['rep_name'] ?? '').toString(), role: (j['role'] ?? 'مندوب').toString(),
      createdAt: (j['created_at'] ?? '').toString(), checksum: cs, checksumOk: cs.isEmpty ? false : cs == calc,
      entries: [for (final e in raw) RepEntry.fromJson(e)], fileName: fileName,
    );
  }
}

class Check {
  Check(this.e);
  final RepEntry e;
  final errors = <String>[], warns = <String>[];
  String? code; // الكود النهائي للعميل (للتحصيل) أو اللي هيتولّد (للبيع)
  bool apply = true;
  bool get ok => errors.isEmpty;
  String get level => errors.isNotEmpty ? 'err' : (warns.isNotEmpty ? 'warn' : 'ok');
}

class ReviewResult {
  ReviewResult(this.file, this.checks, this.fileErrors, this.fileWarns);
  final RepFile file;
  final List<Check> checks;
  final List<String> fileErrors, fileWarns;
  int get nOk => checks.where((c) => c.level == 'ok').length;
  int get nWarn => checks.where((c) => c.level == 'warn').length;
  int get nErr => checks.where((c) => c.level == 'err').length;
  double get sales => checks.where((c) => c.e.kind == 'sale').fold<double>(0.0, (s, c) => s + c.e.total);
  double get collected => checks.where((c) => c.e.kind == 'collect').fold<double>(0.0, (s, c) => s + c.e.amount);
}

extension RepOwner on AppDb {
  Future<ReviewResult> reviewRepFile(RepFile f) async {
    final fileErrors = <String>[], fileWarns = <String>[];
    if (f.batchId.isEmpty) fileErrors.add('الملف من غير رقم دفعة (batch).');
    if (f.batchId.isNotEmpty && (await db.query('rep_reports', where: 'batch_id=?', whereArgs: [f.batchId])).isNotEmpty) {
      fileErrors.add('الملف ده اتستورد قبل كده (نفس رقم الدفعة).');
    }
    if (!f.checksumOk) fileWarns.add('البصمة (checksum) مش مطابقة — الملف ممكن يكون اتعدّل بعد التصدير. راجع الأرقام كويس.');
    if (f.repName.trim().isEmpty) fileWarns.add('اسم المندوب فاضي في الملف.');
    else {
      final reps = [...await namesOf('المناديب'), ...await namesOf('المحصلين')];
      if (!reps.any((n) => normAr(n).trim() == normAr(f.repName).trim())) {
        fileWarns.add("الاسم '${f.repName}' مش مسجّل في المناديب/المحصلين عندك.");
      }
    }

    final fin = await financials();
    final byCode = {for (final c in fin) c.code: c};
    final remain = {for (final c in fin) c.code: c.remaining};
    final newRemain = <String, double>{}; // NEW:uid → remaining
    final newOk = <String, bool>{};
    final applied = {for (final r in await db.query('applied_entries', columns: ['uid'])) r['uid'].toString()};
    final pays = await db.rawQuery("SELECT customer_code, amount_paid, pay_date FROM payments WHERE IFNULL(due_month,'')!=?", [downLabel]);
    final payKeys = {for (final p in pays) '${p['customer_code']}|${((p['amount_paid'] as num).toDouble()).toStringAsFixed(2)}|${p['pay_date']}'};
    final seenInFile = <String>{};
    final seenUids = <String>{};
    final trackS = await trackStock();
    final allowNeg = await getSetting('allow_negative_stock') == 'نعم';
    final nowD = today();
    final custLeft = <int, int>{}, whLeft = <int, int>{};

    final entries = [...f.entries]..sort((a, b) => a.ts.compareTo(b.ts));
    final checks = <Check>[];
    for (final e in entries) {
      final c = Check(e);
      checks.add(c);
      if (e.uid.isEmpty) c.errors.add('السجل من غير معرّف.');
      else if (!seenUids.add(e.uid)) c.errors.add('السجل متكرر جوه الملف.');
      else if (applied.contains(e.uid)) c.errors.add('السجل ده اتسجّل قبل كده في البرنامج.');
      final dt = toDate(e.payDate.isEmpty ? e.ts : e.payDate);
      if (dt == null) c.errors.add('التاريخ غلط أو ناقص.');
      else {
        if (dt.isAfter(nowD)) c.errors.add('التاريخ في المستقبل (${isoDate(dt)}).');
        if (nowD.difference(dt).inDays > 90) c.warns.add('التاريخ قديم (${isoDate(dt)}) — أكتر من 90 يوم.');
      }

      if (e.kind == 'sale') {
        if (e.name.trim().isEmpty) c.errors.add('اسم العميل فاضي.');
        if (e.total <= 0) c.errors.add('إجمالي البيع لازم يكون أكبر من صفر.');
        if (e.down < 0 || e.down > e.total) c.errors.add('المقدم (${fmtMoney(e.down)}) لازم يكون من صفر لحد الإجمالي.');
        List<List<num>> plan = [];
        try {
          plan = parsePlan(e.plan);
        } on FormatException catch (x) {
          c.errors.add(x.message);
        }
        final months = plan.isNotEmpty ? plan.fold<int>(0, (s, x) => s + (x[0] as int)) : e.months;
        if (months <= 0 || months > 120) c.errors.add('عدد الشهور لازم يكون من 1 لـ 120.');
        if (plan.isNotEmpty) {
          final ptot = r2(plan.fold<double>(0, (s, x) => s + (x[0] as int) * (x[1] as num)));
          if (!planTotalOk(ptot, r2(e.total - e.down))) c.errors.add('مجموع الخطة المتدرّجة (${fmtMoney(ptot)}) مش بيقارب الإجمالي − المقدم (${fmtMoney(e.total - e.down)}).');
        }
        try {
          cleanPhone(e.phone);
        } on FormatException catch (x) {
          c.errors.add(x.message);
        }
        if (e.phone.trim().isEmpty) c.warns.add('من غير رقم موبايل.');
        if (e.region.trim().isEmpty) c.warns.add('المنطقة فاضية.');
        if (e.item.trim().isEmpty) c.warns.add('البضاعة فاضية.');
        final dup = fin.where((x) => (e.phone.trim().isNotEmpty && normAr(x.phone) == normAr(e.phone)) || normAr(x.name).trim() == normAr(e.name).trim()).toList();
        if (dup.isNotEmpty && e.name.trim().isNotEmpty) {
          c.warns.add('فيه عميل بنفس الاسم/الموبايل: ${dup.first.name} (${dup.first.code}) — تأكد إنه مش مكرر.');
        }
        if (e.items.isNotEmpty) {
          var sum = 0.0;
          for (final it in e.items) {
            final q = (it['qty'] as int), pr = (it['price'] as num).toDouble();
            sum += q * pr;
            final p = await productByCodeOrName((it['code'] ?? '').toString(), (it['name'] ?? '').toString());
            if (p == null) {
              c.warns.add("الصنف '${it['name']}' مش موجود في المخزن عندك — هيتسجل في العقد من غير خصم.");
              continue;
            }
            if (!trackS) continue;
            final pid = (p['id'] as num).toInt();
            // الرصيد المتاح = عهدة المندوب أولاً ثم المخزن
            custLeft[pid] ??= await _openCustodyQty(f.repName, (p['name'] ?? '').toString());
            whLeft[pid] ??= ((p['qty'] ?? 0) as num).toInt();
            final fromCust = (custLeft[pid]! < q) ? custLeft[pid]! : q;
            final fromWh = q - fromCust;
            custLeft[pid] = custLeft[pid]! - fromCust;
            if (fromWh > 0 && whLeft[pid]! < fromWh) {
              c.warns.add("رصيد '${p['name']}' (${whLeft[pid]} في المخزن) أقل من المطلوب ($fromWh${fromCust > 0 ? ' بعد خصم $fromCust من عهدة المندوب' : ''}) — البيع حقيقي فهيتسجل والرصيد هيبقى بالسالب، راجع الجرد.");
            }
            whLeft[pid] = whLeft[pid]! - fromWh;
            if (pr > 0 && ((p['sell_price'] ?? 0) as num) > 0 && pr < (p['sell_price'] as num).toDouble() * 0.8) {
              c.warns.add("سعر '${p['name']}' (${fmtMoney(pr)}) أقل من سعر البيع (${fmtMoney(p['sell_price'] as num)}) بأكتر من 20%.");
            }
          }
          if (sum > 0 && e.total + 0.5 < sum) c.warns.add('إجمالي العقد (${fmtMoney(e.total)}) أقل من مجموع الأصناف (${fmtMoney(sum)}).');
        } else if (e.qty > 0 && trackS) {
          final p = await productByName(e.item);
          if (p == null) c.warns.add('الصنف مش موجود في المخزن — مش هيتخصم.');
          else if (((p['qty'] ?? 0) as num).toInt() < e.qty && !allowNeg) c.warns.add('رصيد المخزن (${p['qty']}) مش كفاية — العقد هيتسجل من غير خصم.');
        }
        if (c.errors.isEmpty) {
          newRemain['NEW:${e.uid}'] = r2(e.total - e.down);
          newOk['NEW:${e.uid}'] = true;
        }
      } else if (e.kind == 'collect') {
        String ref = e.custRef.trim();
        double? rem;
        double monthly = 0;
        String assignedRep = '', assignedColl = '';
        if (e.amount <= 0) c.errors.add('مبلغ التحصيل لازم يكون أكبر من صفر.');
        if (ref.startsWith('NEW:')) {
          if (newOk[ref] != true) c.errors.add('بيشاور على عقد جديد في الملف مش سليم أو مش موجود.');
          else {
            rem = newRemain[ref];
            c.code = ref;
          }
        } else {
          var cust = byCode[ref];
          if (cust == null) {
            final nn = normAr(e.name).trim();
            final m = fin.where((x) => (e.phone.trim().isNotEmpty && normAr(x.phone) == normAr(e.phone)) || (nn.isNotEmpty && normAr(x.name).trim() == nn)).toList();
            if (m.length == 1) {
              cust = m.first;
              c.warns.add("كود العميل '$ref' مش موجود — اتطابق بالاسم/الموبايل مع ${cust.name} (${cust.code}).");
            } else if (m.length > 1) {
              c.errors.add("كود العميل '$ref' مش موجود، وفيه ${m.length} عملاء بنفس الاسم — حدّد الكود.");
            } else {
              c.errors.add("العميل '${e.name.isEmpty ? ref : e.name}' مش موجود عندك.");
            }
          }
          if (cust != null) {
            ref = cust.code;
            c.code = cust.code;
            rem = remain[cust.code];
            monthly = cust.monthly;
            assignedRep = cust.rep;
            assignedColl = cust.collector;
            if ((rem ?? 0) <= 0.004) c.errors.add('العميل ${cust.name} مسدد بالكامل.');
            if (assignedRep.isNotEmpty && f.role == 'مندوب' && normAr(assignedRep).trim() != normAr(f.repName).trim()) {
              c.warns.add('العميل ده مسجّل على المندوب $assignedRep مش ${f.repName}.');
            }
            if (assignedColl.isNotEmpty && f.role == 'محصل' && normAr(assignedColl).trim() != normAr(f.repName).trim()) {
              c.warns.add('العميل ده مسجّل على المحصّل $assignedColl مش ${f.repName}.');
            }
            if (monthly > 0 && e.amount > monthly * 3) c.warns.add('المبلغ (${fmtMoney(e.amount)}) أكبر من 3 أضعاف القسط (${fmtMoney(monthly)}).');
          }
        }
        if (c.errors.isEmpty && rem != null) {
          if (e.amount > rem + 0.009) {
            c.errors.add('المبلغ (${fmtMoney(e.amount)}) أكبر من المتبقي على العميل (${fmtMoney(rem)}).');
          } else {
            final key = '${c.code}|${e.amount.toStringAsFixed(2)}|${e.payDate.isEmpty ? (e.ts.length >= 10 ? e.ts.substring(0, 10) : e.ts) : e.payDate}';
            if (payKeys.contains(key)) c.warns.add('فيه دفعة بنفس العميل والمبلغ والتاريخ مسجّلة قبل كده — يمكن تكرار.');
            if (!seenInFile.add(key)) c.warns.add('نفس العميل والمبلغ والتاريخ اتكرروا جوه الملف.');
            if (ref.startsWith('NEW:')) {
              newRemain[ref] = r2((newRemain[ref] ?? 0) - e.amount);
            } else {
              remain[c.code!] = r2(rem - e.amount);
            }
          }
        }
      } else {
        c.errors.add("نوع السجل '${e.kind}' غير معروف.");
      }
      if (c.errors.isNotEmpty) c.apply = false;
    }
    return ReviewResult(f, checks, fileErrors, fileWarns);
  }

  Future<int> _openCustodyQty(String rep, String itemName) async {
    final n = normAr(itemName).trim();
    var q = 0;
    for (final r in await db.query('custody', where: 'rep_name=? AND status=?', whereArgs: [rep, custodyOpen])) {
      if (normAr((r['item_name'] ?? '').toString()).trim() == n) q += ((r['qty'] ?? 0) as num).toInt();
    }
    return q;
  }

  /// توزيع السجلات السليمة في أماكنها: بيع ← عقد، تحصيل ← دفعة. بيرجّع رسائل التطبيق.
  Future<List<String>> applyRepReview(ReviewResult r) async {
    final msgs = <String>[];
    final map = <String, String>{}; // NEW:uid → كود العميل
    var applied = 0, failed = 0;
    final issues = <Map<String, Object?>>[];
    final f = r.file;
    final isRep = f.role == 'مندوب';
    for (final c in r.checks) {
      final e = c.e;
      if (!c.apply || !c.ok) {
        issues.add({'uid': e.uid, 'kind': e.kind, 'title': e.title, 'level': 'err', 'msgs': c.errors.isEmpty ? ['اتخطّى بقرار المالك'] : c.errors});
        continue;
      }
      try {
        final d = toDate(e.payDate.isEmpty ? e.ts : e.payDate) ?? today();
        if (e.kind == 'sale') {
          await ensureRegion(e.region);
          final items = <Map<String, dynamic>>[];
          for (final it in e.items) {
            final p = await productByCodeOrName((it['code'] ?? '').toString(), (it['name'] ?? '').toString());
            items.add({'pid': p == null ? null : (p['id'] as num).toInt(), 'name': p == null ? it['name'] : p['name'], 'qty': it['qty'], 'price': it['price']});
          }
          int? pid;
          if (items.isEmpty && e.qty > 0 && await trackStock()) {
            final p = await productByName(e.item);
            if (p != null && ((p['qty'] ?? 0) as num).toInt() >= e.qty) pid = p['id'] as int;
          }
          final code = await addCustomer({
            'name': e.name, 'phone': e.phone, 'address': e.address, 'region': e.region, 'item': e.item, 'total': e.total, 'down': e.down,
            'months': e.months, 'plan': e.plan, 'rep': isRep ? f.repName : '', 'collector': isRep ? '' : f.repName, 'down_collector': f.repName,
            'start': isoDate(d), 'stock_pid': pid, 'stock_qty': pid == null ? 0 : e.qty,
            if (e.lat != null && e.lng != null) ...{'lat': e.lat, 'lng': e.lng},
            if (items.isNotEmpty) 'items': items,
            if (items.isNotEmpty && isRep) 'custody_rep': f.repName,
            if (items.isNotEmpty) 'force_stock': true,
          }, inTx: (tx, newCode) async {
            // علامة «اتطبّق» في نفس العملية: لو العقد فشل ما تتسجلش، ولو العقد نجح ما يتكررش لو الملف اتفتح تاني
            await tx.insert('applied_entries', {'uid': e.uid, 'batch_id': f.batchId, 'rep_name': f.repName, 'kind': 'sale', 'applied_at': DateTime.now().toIso8601String(), 'ref': newCode});
          });
          map['NEW:${e.uid}'] = code;
          msgs.add('✓ عقد جديد $code — ${e.name}');
        } else {
          var code = c.code ?? e.custRef;
          if (code.startsWith('NEW:')) {
            final mapped = map[code];
            if (mapped == null) throw const FormatException('العقد الجديد المرتبط ما اتسجلش.');
            code = mapped;
          }
          final payCode = code;
          await addPayment(payCode, e.amount, collector: f.repName, notes: e.notes.isEmpty ? 'تحصيل ${f.role} ${f.repName}' : e.notes, payDate: isoDate(d), inTx: (tx) async {
            await tx.insert('applied_entries', {'uid': e.uid, 'batch_id': f.batchId, 'rep_name': f.repName, 'kind': 'collect', 'applied_at': DateTime.now().toIso8601String(), 'ref': payCode});
          });
          msgs.add('✓ تحصيل ${fmtMoney(e.amount)} من $code');
        }
        applied++;
        if (c.warns.isNotEmpty) issues.add({'uid': e.uid, 'kind': e.kind, 'title': e.title, 'level': 'warn', 'msgs': c.warns});
      } catch (x) {
        failed++;
        final m = x is FormatException ? x.message : x.toString();
        issues.add({'uid': e.uid, 'kind': e.kind, 'title': e.title, 'level': 'err', 'msgs': [m]});
        msgs.add('✗ ${e.title}: $m');
      }
    }
    if (f.batchId.isNotEmpty && r.fileErrors.isEmpty) {
      await db.insert('rep_reports', {
        'batch_id': f.batchId, 'rep_name': f.repName, 'role': f.role, 'file_name': f.fileName, 'imported_at': DateTime.now().toIso8601String().substring(0, 19).replaceFirst('T', ' '),
        'n_sales': r.checks.where((c) => c.e.kind == 'sale').length, 'n_collect': r.checks.where((c) => c.e.kind == 'collect').length,
        'total_sales': r.sales, 'total_collect': r.collected, 'n_ok': r.nOk, 'n_warn': r.nWarn, 'n_err': r.nErr + failed, 'n_applied': applied,
        'issues': jsonEncode(issues),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await log('استيراد ملف ${f.role}', '${f.repName}: اتسجّل $applied، فشل/اتخطّى ${r.checks.length - applied}');
    return msgs;
  }

  /// حزمة بيانات للمندوب: عملاؤه + الأصناف + المناطق + أسماء الفريق
  /// [ym] (مثلاً 2026-10): حزمة «تحصيل الشهر» — بس العملاء اللي عليهم أقساط مستحقة لحد آخر الشهر ده (ومعاهم المتأخر)،
  /// وكل عميل معاه مبلغ المطلوب منه. من غير [ym] بتتبعت كل العملاء زي الأول.
  /// [ym] = شهر (2026-10) أو سنة كاملة (2026). [regions] فلتر مناطق (فاضي = كل المناطق). [customer] كود عميل معين.
  Future<String> exportRepPackage(String rep, {bool allCustomers = false, String? ym, Set<String> regions = const {}, String? customer}) async {
    final fin = await financials();
    var mine = fin.where((c) => allCustomers || c.rep == rep || c.collector == rep).toList();
    if (customer != null) mine = mine.where((c) => c.code == customer).toList();
    if (regions.isNotEmpty) {
      final rs = {for (final r in regions) normAr(r).trim()};
      mine = mine.where((c) => rs.contains(normAr(c.region).trim())).toList();
    }
    final dueAmt = <String, double>{};
    if (ym != null) {
      final y = int.parse(ym.substring(0, 4));
      final end = ym.length == 4 ? DateTime(y, 12, 31) : DateTime(y, int.parse(ym.substring(5, 7)) + 1, 0);
      for (final c in mine) {
        var s = 0.0;
        for (final r in installmentRows(c)) {
          if (!r.paid && r.due != null && !r.due!.isAfter(end)) s += r.toPay;
        }
        s = r2(s);
        // المطلوب مينفعش يعدّي المتبقي على العميل
        if (s > c.remaining) s = c.remaining;
        if (s > 0.004) dueAmt[c.code] = s;
      }
      mine = mine.where((c) => dueAmt.containsKey(c.code)).toList();
    }
    final j = {
      'type': 'rep_package', 'v': 1, 'for': rep, if (ym != null) 'month': ym, 'created_at': DateTime.now().toIso8601String(),
      'customers': [
        for (final c in mine)
          {'code': c.code, 'name': c.name, 'phone': c.phone, 'address': c.address, 'region': c.region, 'item': c.item, 'remaining': c.remaining,
           'monthly': c.monthly, 'arrears': c.arrears, 'next_due': c.nextDue == null ? '' : isoDate(c.nextDue!), 'collector': c.collector,
           if (ym != null) 'due_amt': dueAmt[c.code]}
      ],
      'products': [for (final p in await db.query('products', columns: ['code', 'name', 'sell_price', 'qty'], orderBy: 'name')) {'code': p['code'], 'name': p['name'], 'sell_price': p['sell_price'], 'qty': p['qty']}],
      'regions': [for (final r in await db.query('regions')) {'name': r['name'], 'sub_name': r['sub_name']}],
      'company': await getSetting('company_name'),
    };
    final dir = await getTemporaryDirectory();
    final safe = rep.replaceAll(RegExp(r'[^\w؀-ۿ]+'), '_');
    final file = File('${dir.path}/hareef_package_${safe}_${isoDate(today())}.json');
    await file.writeAsString(jsonEncode(j));
    return file.path;
  }
}

extension RepField on AppDb {
  Future<String> getTempDir() async => (await getTemporaryDirectory()).path;

  Future<String> get repName async => getSetting('rep_name');
  Future<String> get repRole async {
    final r = await getSetting('rep_role');
    return r.isEmpty ? 'مندوب' : r;
  }

  Future<String> _newUid() async {
    final n = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final r = sha256.convert(utf8.encode('$n${(await getSetting('rep_name'))}${DateTime.now().hashCode}')).toString().substring(0, 6);
    return 'E$n$r';
  }

  Future<List<Map<String, Object?>>> repBaseSearch(String q) async {
    final all = await db.query('rep_base', orderBy: 'name');
    final nq = normAr(q);
    return all.where((r) => nq.isEmpty || normAr('${r['name']} ${r['code']} ${r['phone']} ${r['region']}').contains(nq)).toList();
  }

  Future<String> addRepSale({required String name, String phone = '', String address = '', String region = '', String item = '', required double total, double down = 0, int months = 12, String plan = '', int qty = 0, String notes = '', double? lat, double? lng, List<Map<String, dynamic>> items = const []}) async {
    if (name.trim().isEmpty) throw const FormatException('اكتب اسم العميل.');
    if (total <= 0) throw const FormatException('إجمالي البيع لازم يكون أكبر من صفر.');
    if (down < 0 || down > total) throw const FormatException('المقدم لازم يكون من صفر لحد الإجمالي.');
    final pl = parsePlan(plan);
    final m = pl.isNotEmpty ? pl.fold<int>(0, (s, e) => s + (e[0] as int)) : months;
    if (m <= 0 || m > 120) throw const FormatException('عدد الشهور لازم يكون من 1 لـ 120.');
    if (pl.isNotEmpty) {
      final ptot = r2(pl.fold<double>(0, (s, e) => s + (e[0] as int) * (e[1] as num)));
      if (!planTotalOk(ptot, r2(total - down))) throw FormatException('مجموع الخطة (${fmtMoney(ptot)}) لازم يقارب الإجمالي − المقدم (${fmtMoney(total - down)}).');
    }
    cleanPhone(phone);
    final its = RepEntry.normItems(items);
    if (its.isNotEmpty && item.trim().isEmpty) item = itemsDesc(its);
    final uid = await _newUid();
    await db.transaction((tx) async {
    await tx.insert('rep_entries', {
      'uid': uid, 'kind': 'sale', 'ts': DateTime.now().toIso8601String().substring(0, 19), 'cust_ref': 'NEW:$uid', 'name': name.trim(), 'phone': phone.trim(),
      'address': address.trim(), 'region': region.trim(), 'item': item.trim(), 'total': total, 'down': down, 'months': m, 'plan': planText(pl), 'amount': 0,
      'pay_date': isoDate(today()), 'notes': notes, 'exported': 0,
      'items_json': its.isEmpty ? '' : jsonEncode(its),
      if (lat != null && lng != null) ...{'lat': lat, 'lng': lng},
    });
    // رصيد الأصناف عند المندوب بينقص محلياً عشان يشوف المتاح (معلومة بس)
    for (final it in its) {
      await tx.rawUpdate('UPDATE products SET qty = MAX(IFNULL(qty,0) - ?, 0) WHERE code=? OR name=?', [it['qty'], it['code'], it['name']]);
    }
    });
    return uid;
  }

  /// تحصيل من عميل موجود في بيانات المندوب (code) أو من عقد جديد سجّله النهارده (NEW:uid)
  Future<void> addRepCollect({required String custRef, required String name, String phone = '', required double amount, String notes = ''}) async {
    if (amount <= 0) throw const FormatException('المبلغ لازم يكون أكبر من صفر.');
    if (custRef.isEmpty) throw const FormatException('اختار العميل.');
    if (custRef.startsWith('NEW:')) {
      final s = await db.query('rep_entries', where: 'uid=?', whereArgs: [custRef.substring(4)]);
      if (s.isEmpty) throw const FormatException('العقد الجديد مش موجود.');
    } else {
      final b = await db.query('rep_base', where: 'code=?', whereArgs: [custRef]);
      if (b.isNotEmpty) {
        final rem = (b.first['remaining'] as num).toDouble();
        if (rem > 0 && amount > rem + 0.009) throw FormatException('المبلغ أكبر من المتبقي على العميل (${fmtMoney(rem)}).');
      }
    }
    final uid = await _newUid();
    await db.transaction((tx) async {
    await tx.insert('rep_entries', {
      'uid': uid, 'kind': 'collect', 'ts': DateTime.now().toIso8601String().substring(0, 19), 'cust_ref': custRef, 'name': name, 'phone': phone,
      'amount': amount, 'pay_date': isoDate(today()), 'notes': notes, 'exported': 0, 'total': 0, 'down': 0, 'months': 0,
    });
    // حدّث المتبقي المحلي عشان المندوب يشوف الرقم الجديد
    final b = await tx.query('rep_base', where: 'code=?', whereArgs: [custRef]);
    if (b.isNotEmpty) {
      final rem = (b.first['remaining'] as num).toDouble();
      await tx.update('rep_base', {'remaining': r2(rem - amount < 0 ? 0 : rem - amount)}, where: 'code=?', whereArgs: [custRef]);
    }
    });
  }

  Future<List<Map<String, Object?>>> repEntries({bool onlyNew = false}) =>
      db.query('rep_entries', where: onlyNew ? 'exported=0' : null, orderBy: 'ts DESC');

  Future<void> deleteRepEntry(String uid) => db.transaction((tx) async {
        final r = await tx.query('rep_entries', where: 'uid=?', whereArgs: [uid]);
        if (r.isEmpty) return;
        if (r.first['kind'] == 'collect' && !(r.first['cust_ref'] ?? '').toString().startsWith('NEW:')) {
          final b = await tx.query('rep_base', where: 'code=?', whereArgs: [r.first['cust_ref']]);
          if (b.isNotEmpty) {
            await tx.update('rep_base', {'remaining': r2((b.first['remaining'] as num).toDouble() + (r.first['amount'] as num).toDouble())}, where: 'code=?', whereArgs: [r.first['cust_ref']]);
          }
        }
        if (r.first['kind'] == 'sale') {
          for (final it in RepEntry.fromRow(r.first).items) {
            await tx.rawUpdate('UPDATE products SET qty = IFNULL(qty,0) + ? WHERE code=? OR name=?', [it['qty'], it['code'], it['name']]);
          }
          // احذف التحصيلات المرتبطة بالعقد الجديد
          await tx.delete('rep_entries', where: 'cust_ref=?', whereArgs: ['NEW:$uid']);
        }
        await tx.delete('rep_entries', where: 'uid=?', whereArgs: [uid]);
      });

  /// بيكتب ملف التصدير (بيع + تحصيل لم يُصدَّر) ويعلّم السجلات «مُصدَّرة». بيرجّع مسار الملف.
  Future<String> exportRepReport() async {
    final name = (await repName).trim();
    if (name.isEmpty) throw const FormatException('اكتب اسمك في إعدادات المندوب الأول.');
    final rows = await db.query('rep_entries', where: 'exported=0', orderBy: 'ts');
    if (rows.isEmpty) throw const FormatException('مفيش سجلات جديدة للتصدير.');
    final entries = [for (final r in rows) RepEntry.fromRow(r).toJson()];
    final j = {
      'type': 'rep_report', 'v': 1, 'batch_id': await _newUid(), 'rep_name': name, 'role': await repRole,
      'created_at': DateTime.now().toIso8601String().substring(0, 19), 'company': await getSetting('company_name'),
      'entries': entries, 'checksum': entriesChecksum(entries),
      'summary': {
        'sales': rows.where((r) => r['kind'] == 'sale').fold<double>(0, (s, r) => s + (r['total'] as num)),
        'collected': rows.where((r) => r['kind'] == 'collect').fold<double>(0, (s, r) => s + (r['amount'] as num)),
      },
    };
    final dir = await getTemporaryDirectory();
    final n = DateTime.now();
    final safe = name.replaceAll(RegExp(r'[^\w؀-ۿ]+'), '_');
    final file = File('${dir.path}/hareef_${safe}_${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}_${n.hour.toString().padLeft(2, '0')}${n.minute.toString().padLeft(2, '0')}.json');
    await file.writeAsString(jsonEncode(j));
    await db.update('rep_entries', {'exported': 1}, where: 'exported=0');
    await log('تصدير ملف ${await repRole}', '$name: ${rows.length} سجل');
    return file.path;
  }

  /// استيراد حزمة المالك عند المندوب: عملاء + أصناف + مناطق
  Future<String> importRepPackage(String text) async {
    final Object? j;
    try {
      j = jsonDecode(text);
    } catch (_) {
      throw const FormatException('الملف مش بصيغة صحيحة.');
    }
    if (j is! Map<String, dynamic> || j['type'] != 'rep_package') throw const FormatException('ده مش ملف حزمة بيانات من المالك.');
    final custs = (j['customers'] as List? ?? []).cast<Map<String, dynamic>>();
    final batch = db.batch();
    batch.delete('rep_base');
    for (final c in custs) {
      batch.insert('rep_base', {
        'code': c['code'], 'name': c['name'], 'phone': c['phone'], 'address': c['address'], 'region': c['region'], 'item': c['item'],
        'remaining': c['remaining'], 'monthly': c['monthly'], 'arrears': c['arrears'], 'next_due': c['next_due'], 'collector': c['collector'],
        'due_amt': c['due_amt'] is num ? (c['due_amt'] as num).toDouble() : 0.0, 'due_month': (j['month'] ?? '').toString(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    for (final r in (j['regions'] as List? ?? []).cast<Map<String, dynamic>>()) {
      await ensureRegion((r['name'] ?? '').toString());
    }
    var np = 0, nu = 0;
    for (final p in (j['products'] as List? ?? []).cast<Map<String, dynamic>>()) {
      final n = (p['name'] ?? '').toString();
      final pc = (p['code'] ?? '').toString();
      if (n.isEmpty) continue;
      final ex = await productByCodeOrName(pc, n);
      final price = (p['sell_price'] is num) ? (p['sell_price'] as num).toDouble() : parseNum(p['sell_price']);
      final q = (p['qty'] is num) ? (p['qty'] as num).toInt() : 0;
      if (ex != null) {
        await db.update('products', {'sell_price': price, 'qty': q, if (pc.isNotEmpty) 'code': pc}, where: 'id=?', whereArgs: [ex['id']]);
        nu++;
      } else {
        await db.insert('products', {'name': n, 'sell_price': price, 'qty': q, 'min_qty': 3, 'code': pc.isNotEmpty ? pc : await nextCode('P', 'products', 'code')});
        np++;
      }
    }
    final co = (j['company'] ?? '').toString();
    if (co.isNotEmpty && (await getSetting('company_name')).isEmpty) await setSetting('company_name', co);
    await log('استيراد حزمة بيانات', '${custs.length} عميل');
    return 'اتحمّل ${custs.length} عميل${np > 0 ? ' و$np صنف جديد' : ''}${nu > 0 ? ' وتحديث أسعار وأرصدة $nu صنف' : ''}.';
  }
}
