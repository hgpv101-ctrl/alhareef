import 'dart:async';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../core/security.dart';
import '../core/utils.dart';
import '../data/db.dart';
import '../data/hareef_brain.dart';
import '../data/repfile.dart';
import '../theme.dart';
import 'crud.dart';
import 'customers.dart';
import 'ops_screens.dart';
import 'regions.dart';
import 'stock.dart';
import 'receipt_pdf.dart';
import 'reports.dart';
import 'widgets.dart';

/// الحريف: بيفهم بالعامية وبينفّذ الأوامر فعلاً (إضافة/تحصيل/مصروف/مخزن/عهدة/...) بعد تأكيدك
class HareefScreen extends StatefulWidget {
  const HareefScreen({super.key, this.repMode = false, this.role = roleAdmin});
  final bool repMode;
  final String role; // صلاحيات المستخدم الحالي — الحريف ما بينفّذش غير اللي مسموح له
  @override
  State<HareefScreen> createState() => _S();
}

class _Msg {
  _Msg(this.me, this.text, [this.acts = const [], this.choices = const []]);
  final bool me;
  final String text;
  final List<HAct> acts;
  final List<HChoice> choices;
}

class _S extends State<HareefScreen> {
  late final HareefBrain brain = HareefBrain(repMode: widget.repMode, role: widget.role);
  final msgs = <_Msg>[];
  final ctl = TextEditingController();
  final scroll = ScrollController();
  final focus = FocusNode();
  bool secret = false, busy = false;
  int _sendId = 0; // بيتغيّر مع الإلغاء عشان نتجاهل نتيجة عملية قديمة
  static const _maxMsgs = 150;

  @override
  void dispose() {
    ctl.dispose();
    scroll.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    msgs.add(_Msg(false, HareefBrain.greeting));
  }

  Future<void> _send([String? preset]) async {
    final t = (preset ?? ctl.text).trim();
    if (t.isEmpty || busy) return;
    ctl.clear();
    final id = ++_sendId;
    setState(() {
      msgs.add(_Msg(true, secret ? '••••••' : t));
      busy = true;
    });
    focus.requestFocus(); // الكيبورد يفضل مفتوح عشان تكتب أمر ورا أمر
    HReply r;
    Timer? slow;
    try {
      // مفيش timeout بيقطع الانتظار: المهلة القديمة كانت بتقول «حصل خطأ» والعملية بتكمّل في الخلفية،
      // فالمستخدم يعيد الأمر وتتسجّل مرتين. دلوقتي بنستنى النتيجة الحقيقية، ولو اتأخرت بنطمّنه بس.
      slow = Timer(const Duration(seconds: 15), () {
        if (mounted && busy) {
          setState(() => msgs.add(_Msg(false, '⏳ لسه شغّال على العملية — متبعتش الأمر تاني عشان ما يتكررش.')));
        }
      });
      r = await brain.handle(t);
    } catch (e) {
      r = HReply('حصلت مشكلة وأنا بنفّذ: ${e is FormatException ? e.message : e.toString().split('\n').first}.\nراجع الحالة الأول قبل ما تعيد الأمر.');
    } finally {
      slow?.cancel();
    }
    if (!mounted || id != _sendId) return; // اتلغت: النتيجة القديمة متظهرش
    setState(() {
      msgs.add(_Msg(false, r.text, r.acts, r.choices));
      if (msgs.length > _maxMsgs) msgs.removeRange(0, msgs.length - _maxMsgs);
      secret = r.secret;
      busy = false;
    });
    await Future.delayed(const Duration(milliseconds: 60));
    if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Future<void> _act(HAct a) async {
    await guard(context, () async {
      switch (a.kind) {
        case 'customer':
          await Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetail(code: a.a)));
          break;
        case 'wa':
          await openWhatsapp(a.a, a.b);
          break;
        case 'receipt':
          final f = await AppDb.i.financials(code: a.a);
          if (f.isNotEmpty) await shareReceipt(f.first, double.tryParse(a.b) ?? 0);
          break;
        case 'product':
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetail(id: int.parse(a.a))));
          break;
        case 'screen':
          final Widget? w = switch (a.a) {
            'whatsapp' => const WhatsappReminders(),
            'product_home' => const StockHome(initialTab: 0),
            'regions' => const RegionsHub(),
            'reps' => crudReps(),
            'suppliers' => crudSuppliers(),
            'expenses' => crudExpenses(),
            'partners' => crudPartners(),
            'custody' => const StockHome(initialTab: 3),
            'supplier_invoices' => const SupplierInvoicesScreen(),
            'damages' => const DamagesScreen(),
            _ => null,
          };
          if (w != null) await Navigator.push(context, MaterialPageRoute(builder: (_) => w));
          break;
        case 'backup':
          final dir = (await AppDb.i.getTempDir());
          final p = await AppDb.i.backupTo(dir);
          await Share.shareXFiles([XFile(p)], text: 'نسخة احتياطية — الحريف');
          break;
        case 'rep_export':
          final p = await AppDb.i.exportRepReport();
          await Share.shareXFiles([XFile(p, mimeType: 'application/json')], text: 'تقرير ${await AppDb.i.repRole} ${await AppDb.i.repName}');
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chips = widget.repMode
        ? ['ملخص شغلي', 'مين المتأخرين', 'خلصت']
        : ['ملخص النهارده', 'مين المتأخرين', 'محصّل النهارده', 'الأصناف الناقصة', 'توقع التحصيل', 'خطة الزيارات', 'أرباح', 'أداء المناديب', 'مساعدة'];
    return Scaffold(
      appBar: AppBar(title: const Text('الحريف'), actions: [
        IconButton(
          tooltip: 'إلغاء العملية الحالية',
          icon: const Icon(Icons.cancel_outlined),
          onPressed: () => setState(() {
            final wasBusy = busy;
            brain.cancel();
            _sendId++;
            busy = false; // فك القفل حتى لو عملية علّقت
            secret = false;
            msgs.add(_Msg(false, wasBusy ? 'فكّيت القفل ✅ — لو كانت عملية تسجيل راجع الحالة قبل ما تعيدها عشان ما تتكررش.' : 'تمام، لغيت أي عملية معلّقة ✅'));
          }),
        ),
      ]),
      body: Column(children: [
        Expanded(
          child: SelectionArea(
          child: ListView.builder(
            controller: scroll, padding: const EdgeInsets.all(12), itemCount: msgs.length, cacheExtent: 600,
            itemBuilder: (_, i) {
              final m = msgs[i];
              return Align(
                alignment: m.me ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .85),
                  decoration: BoxDecoration(color: m.me ? C.purple : Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.text, style: TextStyle(color: m.me ? Colors.white : Colors.black87, height: 1.6)),
                    if (m.choices.isNotEmpty && i == msgs.length - 1 && !busy)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final c in m.choices)
                            c.kind == 'opt'
                                ? OutlinedButton(onPressed: () => _send(c.send), child: Text(c.label))
                                : FilledButton(
                                    style: FilledButton.styleFrom(backgroundColor: c.kind == 'yes' ? C.green : C.red, minimumSize: const Size(110, 44)),
                                    onPressed: () => _send(c.send),
                                    child: Text(c.label, style: const TextStyle(fontWeight: FontWeight.w800)),
                                  ),
                        ]),
                      ),
                    if (m.acts.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(spacing: 8, runSpacing: 6, children: [for (final a in m.acts) ActionChip(label: Text(a.label), onPressed: () => _act(a))]),
                      ),
                  ]),
                ),
              );
            },
          ),
          ),
        ),
        if (busy) const LinearProgressIndicator(minHeight: 2),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
            for (final c in chips) Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ActionChip(label: Text(c), onPressed: () => _send(c))),
          ]),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: ctl, focusNode: focus, obscureText: secret, onSubmitted: (_) => _send(),
                  decoration: InputDecoration(hintText: secret ? 'باسورد المدير...' : 'اكتب أمرك بالعامية...', prefixIcon: secret ? const Icon(Icons.lock_rounded) : null),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: () => _send(), icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}
