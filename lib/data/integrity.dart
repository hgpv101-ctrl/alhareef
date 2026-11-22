// سلامة التطبيق: بنقارن بصمة توقيع الـ APK الشغّال ببصمة مفتاحك (tool/hareef_debug.keystore).
// لو اتعدّل التطبيق وأُعيد توقيعه بمفتاح تاني، الفحص بيفشل والبرنامج بيقفل. بيتفحص في نسخة الـ release بس (التجربة المحلية مش بتتأثر).
// لو غيّرت ملف المفتاح: شغّل  keytool -list -v -keystore tool/hareef_debug.keystore -storepass android  وحط SHA256 هنا (حروف صغيرة من غير :).
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const kExpectedCertSha256 = '560bf211567889cf03f20a6d8a67d4d7c9f7d2ffb736397da789e60ab89fc838';
const _ch = MethodChannel('hareef/integrity');
bool? _cached;

Future<bool> apkIntegrityOk() async {
  if (!kReleaseMode) return true;
  if (_cached == true) return true; // اللي نجح مرة بيفضل (التوقيع مابيتغيّرش وانت شغّال)
  try {
    final r = await _ch.invokeMethod<List<dynamic>>('certs');
    final list = [for (final x in r ?? const []) x.toString().toLowerCase()];
    final ok = list.length == 1 && list.first == kExpectedCertSha256;
    if (ok) _cached = true;
    return ok;
  } catch (_) {
    return false; // مفيش رد من الجزء الأصلي = مش مطمّنين → قفل
  }
}
