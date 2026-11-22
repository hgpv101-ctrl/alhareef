import 'dart:convert' show base64Decode;
import 'dart:math' show min;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../core/engine.dart';
import '../core/pdf_fonts.dart';
import '../core/receipt_data.dart';
import '../core/utils.dart';
import '../data/db.dart';
import 'receipt_en.dart';

/// شكل الطباعة: 3 إيصالات في صفحة A4 (مع خط قص) أو إيصال في كل صفحة بمقاس الورق الأصلي
enum SlipLayout { a4x3, single }

/// لغة/تصميم الإيصال: عربي (التصميم الحالي) أو إنجليزي (Contract Credit بنفس الإيصال الورقي)
enum SlipLang { ar, en }

Uint8List? _logoBytes(String b64) {
  if (b64.trim().isEmpty) return null;
  try {
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}

Future<EnInfo> enInfo() async {
  final db = AppDb.i;
  return EnInfo(
    brand: await db.getSetting('en_brand'), brandSub: await db.getSetting('en_brand_sub'), address: await db.getSetting('en_address'),
    accNo: await db.getSetting('en_acc_no'), accName: await db.getSetting('en_acc_name'), bank: await db.getSetting('en_bank'),
    whatsapp: await db.getSetting('en_whatsapp'), manager: await db.getSetting('en_manager'),
    logo: _logoBytes(await db.getSetting('en_logo_b64')),
  );
}

pw.Font _ttf(Uint8List b) => pw.Font.ttf(ByteData.view(b.buffer, b.offsetInBytes, b.lengthInBytes));

Future<pw.Document> _newDoc() async {
  final f = await loadPdfFonts();
  return pw.Document(theme: pw.ThemeData.withFont(base: _ttf(f.regular), bold: _ttf(f.bold)));
}

Future<CompanyInfo> companyInfo() async {
  final db = AppDb.i;
  return CompanyInfo(
    await db.getSetting('company_name'), await db.getSetting('company_activity'),
    await db.getSetting('phones'), await db.getSetting('receipt_footer'),
  );
}

String _words(double amt) {
  final v = (amt.abs() * 100).round();
  final pounds = v ~/ 100, pi = v % 100;
  final w = numWords(pounds);
  return pi > 0 ? '$w جنيها و${numWords(pi)} قرشا' : w;
}

/// الإيصال الواحد — جدول بخانات، أرقام هندية.
/// الشبكة: كل صف ارتفاعه واحد لكل خاناته (عشان الخطوط تتساوى)، وحدود الأعمدة متظبطة بين الصفوف
/// (على 14 / 33 / 73 / 85 من اليمين). الليبلز خط عادي والقيم المهمة بس (الاسم والمبالغ) بولد.
/// الليبل الطويل بيتقسم على سطرين بدل ما يصغر لحد ما ميتقريش.
pw.Widget _slip(SlipData s) {
  const bw = 1.1;
  pw.Widget cell(String t, num flex, double h, {bool bold = false, double size = 11, bool last = false, bool wrap = false, int lines = 2}) =>
      pw.Expanded(
        flex: (flex * 10).round(),
        child: pw.Container(
          height: h,
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          decoration: pw.BoxDecoration(border: pw.Border(
            left: const pw.BorderSide(width: bw), top: const pw.BorderSide(width: bw),
            right: last ? const pw.BorderSide(width: bw) : pw.BorderSide.none,
          )),
          child: wrap
              ? pw.Text(t, textDirection: pw.TextDirection.rtl, maxLines: lines, textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal))
              : pw.FittedBox(
                  fit: pw.BoxFit.scaleDown,
                  child: pw.Text(t, textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
                ),
        ),
      );
  // الصف بيتكتب بترتيب القراءة (يمين → شمال) وبيتعكس عشان يترسم صح. h = ارتفاع الصف كله
  pw.Widget row(double h, List<pw.Widget Function(bool last, double h)> cells) {
    final list = <pw.Widget>[];
    for (var i = cells.length - 1; i >= 0; i--) {
      list.add(cells[i](i == 0, h));
    }
    return pw.Row(children: list);
  }
  // ليبل: خط عادي. لو طويل (أكتر من 13 حرف) بيتقسم سطرين بخط أصغر شوية
  pw.Widget Function(bool, double) L(String t, num fl) => (last, h) {
        final long = t.length > 13;
        return cell(t, fl, h, size: long ? 9 : 10, last: last, wrap: long);
      };
  // قيمة: خط عادي، و b:true للمهم بس
  pw.Widget Function(bool, double) V(String t, num fl, {double size = 11.5, bool b = false, bool wrap = false, int lines = 2}) =>
      (last, h) => cell(t, fl, h, bold: b, size: size, last: last, wrap: wrap, lines: lines);

  final paid = s.kind == 'paid';
  final codeDigits = RegExp(r'\d+').firstMatch(s.code)?.group(0) ?? s.code;
  final hasPi = (s.amount.abs() * 100).round() % 100 > 0;
  return pw.Container(
    decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: bw))),
    child: pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
      row(24, [L('كود العميل', 14), V(arDigits(codeDigits), 12), V(arDigits(s.no), 7), V(s.company, 40, size: 13, b: true), L('الاجمالي', 12), V(arDigits(fmtMoney(s.total)), 15, b: true)]),
      row(24, [L('المنطقة', 14), V(s.region, 12), V(arDigits(s.months), 7), V(s.activity, 40, size: 10.5), L('المقدم', 12), V(arDigits(fmtMoney(s.down)), 15, b: true)]),
      row(28, [L('اسم العميل :', 14), V(s.name, 59, size: 13, b: true), L('الباقي بعد هذا الايصال', 12), V(arDigits(fmtMoney(s.after)), 15, b: true)]),
      row(30, [L('العنوان', 14), V(s.address, 59, size: 10.5, wrap: true), L('هاتف :', 12), V(arDigits(s.phone), 15, size: 11)]),
      row(36, [
        L(paid ? 'استلمنا من العميل مبلغ' : 'بموجب هذا الايصال اتعهد بدفع مبلغ', 33),
        V(arDigits(fmtMoney(s.amount)), 13, size: 13, b: true), L('فقط وقدره', 11), V(_words(s.amount), 28, size: 10, wrap: true, lines: 3),
        L(hasPi ? 'فقط لا غير' : 'فقط جنيها لا غير', 15),
      ]),
      row(24, [
        L('تاريخ الدفع', 14), V(arDigits(paid ? s.payDate : s.due), 19), L('تاريخ الشراء', 14),
        V(arDigits(s.start), 14), L('نظام القسط', 12), V(s.plan, 27, size: 10.5),
      ]),
      row(30, [L('المنتج', 14), V(s.item, 86, size: 11, wrap: true)]),
      row(24, [
        L('المندوب', 14), V(s.rep, 19),
        (last, h) => cell('للاستعلام : ${arDigits(s.phones)}', 67, h, size: 11, last: last),
      ]),
      if (paid)
        row(20, [(last, h) => cell('إيصال رقم ${arDigits(s.receiptNo)}  •  المحصّل: ${s.collector}', 100, h, size: 10, last: last)]),
    ]),
  );
}

class _Job {
  const _Job(this.slips, this.layout, this.reg, this.bold, this.perPage, this.lang, this.en);
  final List<SlipData> slips;
  final int layout, perPage, lang;
  final Uint8List reg, bold;
  final EnInfo en;
}

/// الإيصال الإنجليزي: صفحة لكل عقد عميل (لو العميل له أكتر من قسط في القايمة بيتجمّعوا في عقد واحد).
/// single = ورقة A5 طولي (مقاس الإيصال الورقي) • a4x3 = ورقتين A5 جنب بعض على A4 عرضي.
pw.Document _renderEn(_Job j) {
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: _ttf(j.reg), bold: _ttf(j.bold)));
  final seen = <String>{};
  final uniq = [for (final s in j.slips) if (seen.add(s.code)) s];
  // كل صفحة = (العقد، رقم الصفحة)
  final pages = <(SlipData, int)>[
    for (final s in uniq)
      for (var p = 1; p <= enPageCount(s); p++) (s, p),
  ];
  if (pages.isEmpty) return doc;
  const m = 0.6 * PdfPageFormat.cm;
  if (j.layout == SlipLayout.single.index) {
    const fmt = PdfPageFormat(14.8 * PdfPageFormat.cm, 21.0 * PdfPageFormat.cm, marginAll: m);
    const cw = 14.8 * PdfPageFormat.cm - 2 * m;
    for (final pg in pages) {
      doc.addPage(pw.Page(
        pageFormat: fmt, textDirection: pw.TextDirection.ltr,
        build: (_) => pw.FittedBox(
          fit: pw.BoxFit.scaleDown, alignment: pw.Alignment.topCenter,
          child: pw.SizedBox(width: cw, child: slipEn(pg.$1, j.en, page: pg.$2)),
        ),
      ));
    }
  } else {
    const fmt = PdfPageFormat(29.7 * PdfPageFormat.cm, 21.0 * PdfPageFormat.cm, marginAll: 0.4 * PdfPageFormat.cm);
    const cw = 14.8 * PdfPageFormat.cm - 2 * m;
    for (var i = 0; i < pages.length; i += 2) {
      final two = pages.sublist(i, i + 2 > pages.length ? pages.length : i + 2);
      doc.addPage(pw.Page(
        pageFormat: fmt, textDirection: pw.TextDirection.ltr,
        build: (_) => pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          for (var k = 0; k < 2; k++)
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: m),
                decoration: k == 0 && two.length > 1 ? const pw.BoxDecoration(border: pw.Border(left: pw.BorderSide(width: 0.5, color: PdfColors.grey500, style: pw.BorderStyle.dashed))) : null,
                child: k < two.length
                    ? pw.FittedBox(fit: pw.BoxFit.scaleDown, alignment: pw.Alignment.topCenter, child: pw.SizedBox(width: cw, child: slipEn(two[k].$1, j.en, page: two[k].$2)))
                    : pw.SizedBox(),
              ),
            ),
        ]),
      ));
    }
  }
  return doc;
}

/// بيتنفّذ في isolate لو الإيصالات كتير — عشان الشاشة ماتهنجش
Future<Uint8List> _renderJob(_Job j) async {
  if (j.lang == SlipLang.en.index) return _renderEn(j).save();
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: _ttf(j.reg), bold: _ttf(j.bold)));
  final slips = j.slips;
  if (j.layout == SlipLayout.single.index) {
    const fmt = PdfPageFormat(18.5 * PdfPageFormat.cm, 9.6 * PdfPageFormat.cm, marginAll: 0.35 * PdfPageFormat.cm);
    for (final s in slips) {
      doc.addPage(pw.Page(pageFormat: fmt, textDirection: pw.TextDirection.ltr, build: (_) => _slip(s)));
    }
  } else {
    // عدد الإيصالات في الورقة: 3 (أو أقل) = الحجم الكبير الأصلي، أكتر من 3 = بيصغّر بالتناسب
    final n = j.perPage < 1 ? 3 : j.perPage;
    final fmt = PdfPageFormat(PdfPageFormat.a4.width, PdfPageFormat.a4.height,
        marginTop: 0.4 * PdfPageFormat.cm, marginBottom: 0.4 * PdfPageFormat.cm,
        marginLeft: 1.6 * PdfPageFormat.cm, marginRight: 1.6 * PdfPageFormat.cm);
    final contentW = fmt.width - 3.2 * PdfPageFormat.cm;
    final slotH = n <= 3 ? 9.5 * PdfPageFormat.cm : (fmt.height - 0.8 * PdfPageFormat.cm - 2) / n;
    for (var i = 0; i < slips.length; i += n) {
      final chunk = slips.sublist(i, min(i + n, slips.length));
      doc.addPage(pw.Page(
        pageFormat: fmt,
        textDirection: pw.TextDirection.ltr,
        build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          for (var k = 0; k < n; k++)
            pw.Container(
              height: slotH,
              decoration: k < chunk.length ? const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.6, color: PdfColors.grey600))) : null, // خط القص
              child: k < chunk.length
                  ? pw.FittedBox(
                      fit: pw.BoxFit.scaleDown, alignment: pw.Alignment.topCenter,
                      child: pw.SizedBox(width: contentW, child: _slip(chunk[k])),
                    )
                  : pw.SizedBox(),
            ),
        ]),
      ));
    }
  }
  return doc.save();
}

/// يبني ملف PDF لمجموعة إيصالات (من واحد لمئات)
Future<Uint8List> buildSlipsPdf(List<SlipData> slips, SlipLayout layout, {int perPage = 3, SlipLang? lang}) async {
  final f = await loadPdfFonts();
  // اللغة: اللي اتحدد صراحة، وإلا اللي اختارها المستخدم آخر مرة (receipt_lang)
  final l = lang ?? (await AppDb.i.getSetting('receipt_lang') == 'en' ? SlipLang.en : SlipLang.ar);
  final job = _Job(slips, layout.index, f.regular, f.bold, perPage, l.index, await enInfo());
  if (slips.length <= 6) return _renderJob(job);
  return compute(_renderJob, job);
}

/// إيصال القسط الحالي للعميل (للتوافق مع الحريف وباقي الشاشات)
Future<void> shareReceipt(CustFin c, [double? amount]) async {
  final co = await companyInfo();
  final rows = installmentRows(c);
  InstRow? cur;
  for (final r in rows) {
    if (!r.paid) {
      cur = r;
      break;
    }
  }
  final custom = amount != null && amount > 0;
  final amt = custom ? amount! : (c.suggested > 0 ? c.suggested : c.monthly);
  final r = cur ?? InstRow(c.paidCount + 1, c.nextDue ?? today(), amt, 0, 'due', amt);
  final after = custom || cur == null ? (c.remaining - amt < 0 ? 0.0 : r2(c.remaining - amt)) : null;
  final s = slipForRow(c, co, r, amount: custom ? amt : null, after: after);
  final bytes = await buildSlipsPdf([s], SlipLayout.single);
  await Printing.sharePdf(bytes: bytes, filename: 'receipt_${c.code}.pdf');
}

pw.Widget _r(String a, String b, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(a, style: const pw.TextStyle(fontSize: 11)),
        pw.Text(b, style: pw.TextStyle(fontSize: 12, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      ]),
    );

/// كشف حساب عميل (ملخص + جدول الأقساط + سجل الدفعات)
Future<void> shareStatement(CustFin c, List<Map<String, Object?>> pays) async {
  final co = await companyInfo();
  final doc = await _newDoc();
  final t = today();
  String st(InstRow r) => r.paid ? 'مسدد' : (r.status == 'partial' ? 'جزئي' : ((r.due != null && r.due!.isBefore(t)) ? 'متأخر' : 'مستحق'));
  final rows = installmentRows(c);
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    textDirection: pw.TextDirection.rtl,
    build: (_) => [
      pw.Text(co.name, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      pw.Text('كشف حساب: ${c.name} (${c.code})', style: const pw.TextStyle(fontSize: 14)),
      pw.SizedBox(height: 8),
      _r('الإجمالي', fmtMoney(c.total)), _r('المقدم', fmtMoney(c.down)), _r('الأقساط', c.instDesc),
      _r('المدفوع', fmtMoney(c.paidTotal)), _r('المتبقي', fmtMoney(c.remaining), bold: true),
      if (c.arrears > 0) _r('المتأخر', fmtMoney(c.arrears), bold: true),
      pw.SizedBox(height: 10),
      if (rows.isNotEmpty) ...[
        pw.Text('جدول الأقساط', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.TableHelper.fromTextArray(
          headers: ['القسط', 'الاستحقاق', 'المبلغ', 'الحالة'],
          data: [for (final r in rows) ['${r.no}', r.due == null ? '' : slashDate(r.due!), fmtMoney(r.amount), st(r)]],
          cellAlignment: pw.Alignment.center,
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
      ],
      pw.Text('سجل الدفعات', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.TableHelper.fromTextArray(
        headers: ['التاريخ', 'المبلغ', 'عن شهر', 'المحصّل'],
        data: [for (final p in pays) [p['pay_date'], fmtMoney(p['amount_paid'] as num), p['due_month'], p['collector'] ?? '']],
        cellAlignment: pw.Alignment.center,
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      ),
    ],
  ));
  await Printing.sharePdf(bytes: await doc.save(), filename: 'statement_${c.code}.pdf');
}

/// جدول عام للتقارير
Future<void> shareTablePdf(String title, List<String> headers, List<List<String>> rows) async {
  final co = await companyInfo();
  final doc = await _newDoc();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4, textDirection: pw.TextDirection.rtl,
    header: (_) => pw.Text('${co.name}  —  $title', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
    build: (_) => [pw.TableHelper.fromTextArray(headers: headers, data: rows, cellAlignment: pw.Alignment.center, headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold))],
  ));
  await Printing.sharePdf(bytes: await doc.save(), filename: 'report.pdf');
}
