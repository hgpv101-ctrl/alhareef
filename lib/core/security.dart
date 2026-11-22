import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'utils.dart';

/// عدد لفّات التشفير للكلمات الجديدة. 600 ألف كانت بتاخد عشرات الثواني على الموبايل (بتعلّق الدخول وفتح التطبيق).
/// الكلمات القديمة بتفضل تتفحص عادي وبتتحدّث تلقائي للسرعة الجديدة أول ما صاحبها يدخل.
const pwIters = 20000;
const defaultAdminPw = '000000';

String normPw(String? pw) => trDigits(pw ?? '').trim();

String _hex(List<int> b) => b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

String _pbkdf2(String pw, String salt, int iters) {
  final p = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(Uint8List.fromList(utf8.encode(salt)), iters, 32));
  return _hex(p.process(Uint8List.fromList(utf8.encode(pw))));
}

/// مهم: الـ PBKDF2 بـ 600 ألف لفّة تقيل. نادها داخل compute() / Isolate.
String hashPw(String pw) {
  final r = Random.secure();
  final salt = _hex(List.generate(16, (_) => r.nextInt(256)));
  return 'pbkdf2\$$salt\$${_pbkdf2(normPw(pw), salt, pwIters)}\$$pwIters';
}

bool isHashed(String? s) => (s ?? '').startsWith('pbkdf2\$');

bool checkPw(String? stored, String pw) {
  stored ??= '';
  final cands = <String>{normPw(pw), pw};
  if (isHashed(stored)) {
    try {
      final parts = stored.split('\$');
      final iters = parts.length > 3 ? int.parse(parts[3]) : 60000;
      for (final c in cands) {
        if (_pbkdf2(c, parts[1], iters) == parts[2]) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
  return cands.contains(stored);
}

bool checkPwArgs(List<String> a) => checkPw(a[0], a[1]);

/// الكلمة متخزّنة بعدد لفّات أعلى من الحالي → تتحدّث لنسخة أسرع بعد دخول ناجح
bool needsRehash(String? stored) {
  if (!isHashed(stored)) return true;
  final parts = stored!.split('\$');
  final it = parts.length > 3 ? int.tryParse(parts[3]) ?? 0 : 0;
  return it > pwIters;
}
String hashPwArg(String pw) => hashPw(pw);

const roleAdmin = 'Admin';
const roles = <String, Set<String>>{
  'محاسب': {'customers', 'collection', 'receipts', 'expenses', 'suppliers', 'settlement', 'partners', 'reports', 'whatsapp', 'regions', 'followup'},
  'أمين مخزن': {'products', 'warehouse', 'custody', 'inout'},
};
bool canOpen(String role, String screen) => role == roleAdmin || (roles[role]?.contains(screen) ?? false);
