// الإيصال الإنجليزي «CONTRACT CREDIT» — بنفس شكل الإيصال الورقي (ورقة A5 طولي):
// شعار وعنوان الشركة، رقم العقد، المنتج والإجمالي والمقدم، جدول الأقساط (DATE / DESCRIPTION / MONTHLY PAYMENT)،
// بيانات العميل، حساب الدفع، الملاحظات، وخانتين التوقيع. كل الأرقام إنجليزي.
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../core/receipt_data.dart';
import '../core/utils.dart';

const _blue = PdfColor.fromInt(0xFF1B8DBF);
const _navy = PdfColor.fromInt(0xFF14306B);
const _ink = PdfColor.fromInt(0xFF1A237E);

const enRowsPerPage = 10;
const enMinRows = 5;

bool _hasAr(String s) => RegExp(r'[؀-ۿ]').hasMatch(s);

pw.TextStyle _lbl(double size) => pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold, color: _blue);
pw.TextStyle _val(double size) => pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold, color: _ink);

pw.Widget _txt(String t, pw.TextStyle st) => pw.Text(t, style: st, textDirection: _hasAr(t) ? pw.TextDirection.rtl : pw.TextDirection.ltr);

/// خانة بخط منقّط: «LABEL ........» والقيمة مكتوبة فوق النقط
pw.Widget _field(String label, String value, {double size = 11, double h = 19, double labelSize = 11}) => pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(label, style: _lbl(labelSize)),
        pw.SizedBox(width: 4),
        pw.Expanded(
          child: pw.Container(
            height: h,
            alignment: pw.Alignment.bottomLeft,
            padding: const pw.EdgeInsets.only(bottom: 1),
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 1, color: _blue, style: pw.BorderStyle.dotted))),
            child: pw.FittedBox(fit: pw.BoxFit.scaleDown, alignment: pw.Alignment.bottomLeft, child: _txt(value, _val(size))),
          ),
        ),
      ],
    );

String _money(double v) => fmtMoney(v);

String _serial(String code) {
  final d = RegExp(r'\d+').firstMatch(code)?.group(0) ?? code;
  return d.length >= 4 ? d : d.padLeft(4, '0');
}

/// عدد صفحات العقد (كل صفحة لحد 10 أقساط)
int enPageCount(SlipData s) => s.sched.isEmpty ? 1 : (s.sched.length / enRowsPerPage).ceil();

/// صفحة واحدة من عقد العميل (page من 1)
pw.Widget slipEn(SlipData s, EnInfo e, {int page = 1}) {
  const bw = 1.3;
  final pages = enPageCount(s);
  final from = (page - 1) * enRowsPerPage;
  final chunk = s.sched.isEmpty ? <SlipRow>[] : s.sched.sublist(from, (from + enRowsPerPage) > s.sched.length ? s.sched.length : from + enRowsPerPage);
  final nRows = chunk.length < enMinRows ? enMinRows : chunk.length;

  pw.Widget cell(pw.Widget child, double flex, {double h = 17}) => pw.Expanded(
        flex: (flex * 10).round(),
        child: pw.Container(
          height: h,
          alignment: pw.Alignment.center,
          decoration: const pw.BoxDecoration(border: pw.Border(left: pw.BorderSide(width: bw, color: _blue), bottom: pw.BorderSide(width: bw, color: _blue))),
          child: child,
        ),
      );

  pw.Widget head(String t, double flex) => cell(pw.Text(t, style: _lbl(10.5), textAlign: pw.TextAlign.center), flex, h: t.contains('\n') ? 26 : 20);

  pw.Widget bodyRow(SlipRow? r) {
    final tick = r == null ? '' : (r.status == 'paid' ? '✓' : (r.status == 'partial' ? 'part.' : ''));
    return pw.Row(children: [
      cell(pw.Text(r?.date ?? '', style: _val(10.5)), 24),
      cell(pw.Text(r == null ? '' : _money(r.amount), style: _val(11)), 52),
      cell(pw.Text(tick, style: _val(11)), 24),
    ]);
  }

  final note1 = 'The company only accepts the Account above for transfer.';
  const note2 = 'Warranty of one (1) year from the date of sale.';
  const note3 = 'If you feel that you cannot pay the money, you can return the goods and terminate the contract a week after you receive the goods, then you must pay ₦10,000.00 (Ten thousand naira) only to the Company Account as transportation with the return of the goods.';

  pw.Widget line(String a, String b) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2.5),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 78, child: pw.Text(a, style: _lbl(9.5))),
          pw.Expanded(child: pw.Text(b, style: _lbl(9.5))),
        ]),
      );

  return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, mainAxisSize: pw.MainAxisSize.min, children: [
    // الشعار + عنوان الشركة
    pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      if (e.logo != null)
        pw.SizedBox(height: 56, width: 150, child: pw.Image(pw.MemoryImage(e.logo!), fit: pw.BoxFit.contain, alignment: pw.Alignment.centerLeft))
      else
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        if (e.brand.trim().isNotEmpty)
          pw.Text(e.brand.toUpperCase(), style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold, color: _blue, letterSpacing: 1)),
        if (e.brandSub.trim().isNotEmpty)
          pw.Row(children: [
            pw.Container(width: 24, height: 11, color: _navy),
            pw.SizedBox(width: 4),
            pw.Text(e.brandSub, style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold, color: _blue)),
          ]),
      ]),
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        if ('${e.brand} ${e.brandSub}'.trim().isNotEmpty) pw.Text('${e.brand} ${e.brandSub}'.trim().toUpperCase(), style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _blue)),
        for (final l in e.address.split('\n').where((x) => x.trim().isNotEmpty)) pw.Text(l.trim(), style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: _blue)),
      ]),
    ]),
    pw.SizedBox(height: 8),
    // العنوان + رقم العقد
    pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text('CONTRACT CREDIT', style: pw.TextStyle(fontSize: 21, fontWeight: pw.FontWeight.bold, color: _blue)),
      pw.Text(_serial(s.code) + (pages > 1 ? '  ($page/$pages)' : ''), style: pw.TextStyle(fontSize: 15, color: PdfColors.grey800)),
    ]),
    pw.SizedBox(height: 6),
    pw.Row(children: [
      pw.Expanded(flex: 5, child: _field('PRODUCT:', s.enItem.trim().isNotEmpty ? s.enItem : s.item, size: 10.5)),
      pw.SizedBox(width: 6),
      pw.Text('#', style: _lbl(11)),
      pw.Expanded(flex: 2, child: pw.Container(height: 19, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 1, color: _blue, style: pw.BorderStyle.dotted))))),
      pw.SizedBox(width: 6),
      pw.Text('#', style: _lbl(11)),
      pw.Expanded(flex: 2, child: pw.Container(height: 19, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 1, color: _blue, style: pw.BorderStyle.dotted))))),
    ]),
    pw.Row(children: [
      pw.Expanded(flex: 5, child: _field('TOTAL PRICE=', _money(s.total), size: 11.5)),
      pw.SizedBox(width: 14),
      pw.Expanded(flex: 4, child: _field('ADVANCE=', s.down > 0 ? _money(s.down) : '', size: 11.5)),
    ]),
    pw.SizedBox(height: 7),
    // جدول الأقساط
    pw.Container(
      decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: bw, color: _blue), right: pw.BorderSide(width: bw, color: _blue))),
      child: pw.Column(children: [
        pw.Row(children: [head('DATE', 24), head('DESCRIPTION', 52), head('MONTHLY\nPAYMENT', 24)]),
        for (var i = 0; i < nRows; i++) bodyRow(i < chunk.length ? chunk[i] : null),
      ]),
    ),
    pw.SizedBox(height: 10),
    _field('1. CUSTOMERS NAME', s.enName.trim().isNotEmpty ? s.enName : s.name, size: 12),
    _field('2. CUSTOMERS NUMBER', s.phone, size: 11.5),
    _field('3. CUSTOMERS ADDRESS', s.enAddress.trim().isNotEmpty ? s.enAddress : s.address, size: 10.5),
    _field('4. CUSTOMERS CODE', s.code, size: 11.5),
    pw.SizedBox(height: 7),
    pw.Text('PAYMENT ACCOUNT', style: _lbl(10.5)),
    pw.SizedBox(height: 2),
    line('ACCOUNT NUMBER:', e.accNo),
    line('ACCOUNT NAME:', e.accName),
    line('BANK:', e.bank),
    line('WHATSAPP NO:', e.whatsapp),
    pw.SizedBox(height: 4),
    pw.Text('NOTE:', style: _lbl(10.5)),
    pw.SizedBox(height: 2),
    pw.Text('1. $note1', style: _lbl(8.5)),
    pw.Text('2. $note2', style: _lbl(8.5)),
    pw.Text('3. $note3', style: _lbl(8.5)),
    pw.SizedBox(height: 26),
    // التوقيعات
    pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
      pw.Expanded(
        child: pw.Column(children: [
          pw.Container(height: 1.1, color: _blue),
          pw.SizedBox(height: 2),
          pw.Text("CUSTOMER'S SIGNATURE", style: _lbl(9.5)),
        ]),
      ),
      pw.SizedBox(width: 34),
      pw.Expanded(
        child: pw.Column(children: [
          if (e.manager.isNotEmpty) pw.Text(e.manager, style: _val(11)),
          pw.Container(height: 1.1, color: _blue),
          pw.SizedBox(height: 2),
          pw.Text('SALES MANAGER', style: _lbl(9.5)),
        ]),
      ),
    ]),
  ]);
}
