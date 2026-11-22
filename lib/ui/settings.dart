import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/utils.dart';
import '../data/db.dart';
import '../data/license.dart';
import '../data/regions.dart';
import '../theme.dart';
import '../version.dart';
import 'license_screen.dart';
import 'widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _S();
}

class _S extends State<SettingsScreen> {
  final text = {for (final k in ['company_name', 'company_activity', 'phones', 'company_address', 'receipt_footer', 'default_months', 'grace_days', 'low_stock_default', 'hareef_call', 'owner_name', 'en_brand', 'en_brand_sub', 'en_address', 'en_acc_no', 'en_acc_name', 'en_bank', 'en_whatsapp', 'en_manager']) k: TextEditingController()};
  final yn = <String, bool>{};
  String productMode = 'منتجات المخزن';
  static const labels = {
    'company_name': 'اسم الشركة', 'company_activity': 'النشاط', 'phones': 'التليفونات', 'company_address': 'العنوان',
    'receipt_footer': 'ذيل الإيصال', 'default_months': 'عدد شهور التقسيط الافتراضي', 'grace_days': 'أيام السماح قبل التأخير',
    'low_stock_default': 'حد الطلب الافتراضي', 'hareef_call': 'الحريف بيناديك إيه', 'owner_name': 'اسم صاحب النشاط',
    'en_brand': 'English receipt: Brand (e.g. ELASELL)', 'en_brand_sub': 'English receipt: Brand 2nd word (e.g. Company)', 'en_address': 'English receipt: Company address (2 lines)',
    'en_acc_no': 'English receipt: Account number', 'en_acc_name': 'English receipt: Account name', 'en_bank': 'English receipt: Bank',
    'en_whatsapp': 'English receipt: WhatsApp no.', 'en_manager': 'English receipt: Sales manager name (optional)',
  };
  static const toggles = {
    'require_login': 'طلب كلمة السر عند فتح التطبيق',
    'allow_negative_stock': 'السماح برصيد مخزن بالسالب', 'show_prices': 'إظهار الأسعار في الإيصال', 'auto_backup': 'نسخة احتياطية تلقائية',
    'rep_is_collector': 'المحصّل = المندوب اللي باع (لو مفيش محصّل متحدد للعميل)',
  };

  @override
  void initState() {
    super.initState();
    () async {
      for (final e in text.entries) {
        e.value.text = await AppDb.i.getSetting(e.key);
      }
      for (final k in toggles.keys) {
        yn[k] = await AppDb.i.getSetting(k) == 'نعم';
      }
      productMode = await AppDb.i.getSetting('product_mode');
      if (mounted) setState(() {});
    }();
  }

  Future<void> _save() async {
    await guard(context, () async {
      for (final e in text.entries) {
        await AppDb.i.setSetting(e.key, e.value.text.trim());
      }
      for (final e in yn.entries) {
        await AppDb.i.setSetting(e.key, e.value ? 'نعم' : 'لا');
      }
      await AppDb.i.setSetting('product_mode', productMode);
      await AppDb.i.log('تعديل الإعدادات');
    }, ok: 'اتحفظت الإعدادات');
  }

  /// تطبيق الخيار على العملاء القدام اللي عليهم متبقي وملهمش محصّل: بيعرض العدد الأول وبيطلب تأكيد
  Future<void> _applyRepCollector() async {
    if (await AppDb.i.getSetting('rep_is_collector') != 'نعم') {
      if (mounted) toast(context, 'فعّل الخيار واحفظ الإعدادات الأول.');
      return;
    }
    final list = await AppDb.i.repCollectorCandidates();
    if (!mounted) return;
    if (list.isEmpty) {
      toast(context, 'مفيش عملاء محتاجين تغيير (كلهم ليهم محصّل أو من غير مندوب).');
      return;
    }
    final names = list.take(5).map((c) => '${c.name} ← ${c.rep}').join('\n');
    if (!await confirm(context, 'هيتحدّد المندوب كمحصّل لـ ${list.length} عميل ملهمش محصّل:\n$names${list.length > 5 ? '\n...' : ''}\n\nمفيش مبلغ ولا قسط هيتغيّر، وأي عميل ليه محصّل مش هيتلمس. تكمّل؟')) return;
    await guard(context, () async {
      final n = await AppDb.i.applyRepAsCollector();
      if (mounted) toast(context, 'اتحدّث $n عميل ✅');
    });
  }

  Future<void> _password() async {
    final a = TextEditingController(), b = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('🔑 تغيير كلمة سر المدير'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: a, obscureText: true, decoration: const InputDecoration(labelText: 'الكلمة الحالية')),
          const SizedBox(height: 8),
          TextField(controller: b, obscureText: true, decoration: const InputDecoration(labelText: 'الكلمة الجديدة (4 أرقام على الأقل)')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تغيير'))],
      ),
    );
    if (ok != true || !mounted) return;
    await guard(context, () async {
      if (!await AppDb.i.verifyAdmin(a.text)) throw const FormatException('الكلمة الحالية غلط.');
      if (b.text.trim().length < 4) throw const FormatException('الكلمة الجديدة لازم تكون 4 خانات على الأقل.');
      await AppDb.i.setAdminPassword(b.text);
    }, ok: 'اتغيرت كلمة السر');
  }

  /// لوجو الشركة للإيصال الإنجليزي (صورة PNG/JPG صغيرة) — بيتخزن جوه قاعدة البيانات فبيتنسخ مع النسخة الاحتياطية
  Future<void> _pickLogo() async {
    final pick = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = pick?.files.single.path;
    if (path == null || !mounted) return;
    await guard(context, () async {
      final bytes = await File(path).readAsBytes();
      if (bytes.length > 700 * 1024) throw const FormatException('الصورة كبيرة (أكتر من 700 كيلو). صغّرها واختار تاني.');
      await AppDb.i.setSetting('en_logo_b64', base64Encode(bytes));
    }, ok: 'اتحفظ اللوجو ✅ (هيظهر في الإيصال الإنجليزي)');
  }

  Future<void> _clearLogo() async {
    await AppDb.i.setSetting('en_logo_b64', '');
    if (mounted) toast(context, 'اتشال اللوجو، هيرجع الاسم المكتوب');
  }

  Future<void> _backup() async {
    await guard(context, () async {
      final dir = (await getApplicationDocumentsDirectory()).path;
      final out = await AppDb.i.backupTo(dir);
      await Share.shareXFiles([XFile(out)], text: 'نسخة احتياطية - الحريف');
    });
  }

  Future<void> _import() async {
    final pick = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = pick?.files.single.path;
    if (path == null || !mounted) return;
    if (!await confirm(context, 'هيتم استبدال كل البيانات الحالية بالنسخة المختارة (وهياخد نسخة أمان قبلها). تكمل؟')) return;
        await guard(context, () async {
      final h = await File(path).openRead(0, 16).first;
      if (String.fromCharCodes(h.take(15)) != 'SQLite format 3') throw const FormatException('الملف ده مش قاعدة بيانات SQLite صحيحة.');
      await AppDb.i.importDbFile(path);
      await AppDb.i.log('استيراد نسخة', path.split('/').last);
    }, ok: 'اتستورد الملف بنجاح');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('⚙️ الإعدادات')),
        body: ListView(padding: const EdgeInsets.all(14), children: [
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.info_outline_rounded, color: C.purple),
              title: Text('الإصدار $appVersion (بناء $appBuild)', style: const TextStyle(fontWeight: FontWeight.w800)),
              children: [for (final c in changelog) ListTile(dense: true, title: Text('v${c[0]}', style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(c[1]))],
            ),
          ),
          for (final e in text.entries) ...[
            if (e.key == 'en_brand')
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 14, 4, 8),
                child: Text('🧾 بيانات الإيصال الإنجليزي (Contract Credit)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            Field(labels[e.key]!, e.value, lines: e.key == 'en_address' ? 2 : 1),
          ],
          DropdownButtonFormField<String>(
            initialValue: productMode,
            decoration: const InputDecoration(labelText: 'وضع المنتجات'),
            items: [for (final m in ['منتجات المخزن', 'منتجات العهدة', 'كل المنتجات']) DropdownMenuItem(value: m, child: Text(m))],
            onChanged: (v) => productMode = v ?? productMode,
          ),
          const SizedBox(height: 6),
          for (final e in toggles.entries) SwitchListTile(title: Text(e.value), value: yn[e.key] ?? false, onChanged: (v) => setState(() => yn[e.key] = v)),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('حفظ الإعدادات')),
          const Divider(height: 36),
          ListTile(leading: const Icon(Icons.swap_horiz_rounded, color: C.green), title: const Text('المندوب = المحصّل للعملاء القدام'), subtitle: const Text('للعملاء اللي ملهمش محصّل بس (بعد تأكيدك)'), onTap: _applyRepCollector),
          ListTile(leading: const Icon(Icons.verified_user_rounded, color: C.blue), title: const Text('الاشتراك والترخيص'), subtitle: Text(LicenseGuard.i.message), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LicenseScreen()))),
          ListTile(leading: const Icon(Icons.image_rounded, color: C.blue), title: const Text('لوجو الإيصال الإنجليزي'), subtitle: const Text('اختار صورة اللوجو (بدل الاسم المكتوب) — اضغط مطوّلاً لإزالته'), onTap: _pickLogo, onLongPress: _clearLogo),
          ListTile(leading: const Icon(Icons.key, color: C.purple), title: const Text('تغيير كلمة سر المدير'), onTap: _password),
          ListTile(leading: const Icon(Icons.backup, color: C.green), title: const Text('نسخة احتياطية ومشاركتها'), subtitle: const Text('ملف .db تقدر تفتحه في البرنامج المكتبي'), onTap: _backup),
          ListTile(leading: const Icon(Icons.download, color: C.orange), title: const Text('استيراد / استعادة نسخة .db'), subtitle: const Text('من البرنامج المكتبي أو نسخة قديمة'), onTap: _import),
        ]),
      );
}

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});
  @override
  State<AuditScreen> createState() => _A();
}

class _A extends State<AuditScreen> {
  String q = '';
  List<Map<String, Object?>> rows = [];
  @override
  void initState() {
    super.initState();
    AppDb.i.db.query('audit_log', orderBy: 'id DESC', limit: 1000).then((v) => mounted ? setState(() => rows = v) : null);
  }

  @override
  Widget build(BuildContext context) {
    final nq = normAr(q);
    final l = rows.where((r) => nq.isEmpty || normAr('${r['action']} ${r['details']} ${r['who']}').contains(nq)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('📜 سجل العمليات')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(onChanged: (v) => setState(() => q = v), decoration: const InputDecoration(hintText: 'بحث في السجل', prefixIcon: Icon(Icons.search)))),
        Expanded(
          child: ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final r in l) Card(child: ListTile(title: Text('${r['action']}', style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('${r['details'] ?? ''}'), trailing: Text('${r['ts'] ?? ''}'.replaceFirst(' ', '\n'), style: const TextStyle(fontSize: 11)))),
          ]),
        ),
      ]),
    );
  }
}
