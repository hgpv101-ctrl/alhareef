// خطوط الـ PDF: بتتحمّل من assets (من غير نت) وبتتخزّن في الذاكرة — كانت بتتحمّل من الإنترنت مع كل طباعة.
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;

class PdfFontBytes {
  const PdfFontBytes(this.regular, this.bold);
  final Uint8List regular, bold;
}

PdfFontBytes? _cache;

Future<Uint8List?> _tryLoad(String path) async {
  try {
    final d = await rootBundle.load(path);
    return d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
  } catch (_) {
    return null;
  }
}

/// Cairo لو المستخدم حطّه في assets/fonts، وإلا DejaVu Sans المضمّن.
Future<PdfFontBytes> loadPdfFonts() async {
  final c = _cache;
  if (c != null) return c;
  final r = await _tryLoad('assets/fonts/Cairo-Regular.ttf') ?? await _tryLoad('assets/fonts/DejaVuSans.ttf');
  final b = await _tryLoad('assets/fonts/Cairo-Bold.ttf') ?? await _tryLoad('assets/fonts/DejaVuSans-Bold.ttf');
  if (r == null || b == null) {
    throw const FormatException('ملفات خط الإيصال مش موجودة في assets/fonts');
  }
  return _cache = PdfFontBytes(r, b);
}
