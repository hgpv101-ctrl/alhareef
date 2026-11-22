// فك وتحقق كود الترخيص (دوال نقية من غير أي إضافات — بتتختبر بسهولة)
// الشكل: base32( payload[17] + signature[64] )، والتوقيع Ed25519 على الـpayload.
// payload = type(1) | device(8) | issueDay(2) | expiryDay(2) | serial(4)
//   type 1 = ترخيص سنوي، type 2 = تصحيح وقت الجهاز (issueDay = اليوم الصح)
import 'dart:convert';
import 'dart:typed_data';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

const int kLicEpochDay = 18262; // 2020-01-01 بعد 1970-01-01 بالأيام
const int kPayloadLen = 17;

class LicParsed {
  LicParsed(this.type, this.device, this.issueDay, this.expiryDay, this.serial, this.sigOk, this.normalized);
  final int type;
  final Uint8List device; // 8 bytes
  final int issueDay, expiryDay, serial; // الأيام من 2020-01-01
  final bool sigOk;
  final String normalized;
}

class LicenseCodec {
  LicenseCodec._();
  static const _alpha = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static Uint8List? _b32(String s) {
    var bits = 0, val = 0;
    final out = <int>[];
    for (final ch in s.codeUnits) {
      final i = _alpha.indexOf(String.fromCharCode(ch));
      if (i < 0) return null;
      val = (val << 5) | i;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((val >> bits) & 0xFF);
        val &= (1 << bits) - 1;
      }
    }
    return Uint8List.fromList(out);
  }

  /// بيشيل المسافات والشرطات والبادئة HRF1- ويرجّع الحروف بس
  static String clean(String input) {
    var s = input.trim().toUpperCase();
    if (s.startsWith('HRF1-')) s = s.substring(5);
    return s.replaceAll(RegExp(r'[^A-Z2-7]'), '');
  }

  static LicParsed? parse(String input, {String? pubB64, Uint8List? pubBytes}) {
    final c = clean(input);
    final b = _b32(c);
    if (b == null || b.length != kPayloadLen + 64) return null;
    final msg = Uint8List.fromList(b.sublist(0, kPayloadLen));
    final sig = Uint8List.fromList(b.sublist(kPayloadLen));
    bool ok = false;
    try {
      final pk = pubBytes ?? Uint8List.fromList(base64Decode(pubB64 ?? ''));
      ok = pk.length == 32 && ed.verify(ed.PublicKey(pk), msg, sig);
    } catch (_) {
      ok = false;
    }
    int u16(int o) => (b[o] << 8) | b[o + 1];
    final serial = (b[13] << 24) | (b[14] << 16) | (b[15] << 8) | b[16];
    return LicParsed(b[0], Uint8List.fromList(b.sublist(1, 9)), u16(9), u16(11), serial, ok, c);
  }

  static int dayOfMs(int utcMs) => (utcMs ~/ 86400000) - kLicEpochDay;
  static DateTime dateOfDay(int day) => DateTime.utc(1970).add(Duration(days: day + kLicEpochDay));
  static String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  static bool sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
