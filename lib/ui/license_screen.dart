// شاشة الاشتراك والترخيص + شريط التنبيه اللي بيظهر في كل الشاشات لما الترخيص مش شغّال أو قرّب ينتهي
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../data/license.dart';
import '../theme.dart';
import 'widgets.dart';

final navKey = GlobalKey<NavigatorState>();

/// بيغلّف التطبيق كله: من غير ترخيص ساري بيقفل البرنامج بالكامل ويعرض شاشة التفعيل بس.
/// (التطبيق بيفضل موجود تحتها عشان حالته متضيعش، بس مش ظاهر ولا بيستقبل لمس.)
class LicenseShell extends StatefulWidget {
  const LicenseShell({super.key, required this.child});
  final Widget child;
  @override
  State<LicenseShell> createState() => _LicenseShellState();
}

class _LicenseShellState extends State<LicenseShell> with WidgetsBindingObserver {
  // GlobalKey عشان حالة التطبيق (الملاحة والشاشة الحالية) متضيعش لما الشكل بيتبدّل بين قفل/عادي/شريط تنبيه
  final _k = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // أول ما التطبيق يرجع من الخلفية بنفحص الترخيص فوراً (من غير ما نستنى الدقيقة)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) LicenseGuard.i.refresh();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: LicenseGuard.i,
        builder: (ctx, _) {
          final g = LicenseGuard.i;
          final child = KeyedSubtree(key: _k, child: widget.child);
          if (!g.ready) return child; // لسه بيفحص — شاشة البداية بس (مفيش دخول للبرنامج قبل الفحص)
          if (!g.canWrite) {
            return Stack(children: [
              Visibility(visible: false, maintainState: true, child: child),
              // Navigator خاص بالشاشة دي عشان خانة اللصق والرسايل تشتغل
              Positioned.fill(child: Navigator(onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const LicenseScreen(gate: true)))),
            ]);
          }
          if (!g.warnSoon) return child;
          return Column(children: [
            Material(
              color: C.orange,
              child: InkWell(
                onTap: () => navKey.currentState?.push(MaterialPageRoute(builder: (_) => const LicenseScreen())),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: Row(children: [
                      const Icon(Icons.schedule_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(g.message, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700))),
                      const Text('اضغط', style: TextStyle(color: Colors.white70, fontSize: 11.5)),
                    ]),
                  ),
                ),
              ),
            ),
            Expanded(child: MediaQuery.removePadding(context: ctx, removeTop: true, child: child)),
          ]);
        },
      );
}

class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key, this.gate = false});
  final bool gate;
  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final ctl = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData('text/plain');
    if (d?.text != null) setState(() => ctl.text = d!.text!.trim());
  }

  Future<void> _activate() async {
    if (ctl.text.trim().isEmpty) return;
    setState(() => busy = true);
    await guard(context, () async {
      final m = await LicenseGuard.i.activate(ctl.text);
      if (mounted) {
        ctl.clear();
        toast(context, m);
      }
    });
    if (mounted) setState(() => busy = false);
  }

  String _date(DateTime? d) => d == null ? '—' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.gate ? 'تفعيل البرنامج' : 'الاشتراك والترخيص'), automaticallyImplyLeading: !widget.gate),
        body: ListenableBuilder(
          listenable: LicenseGuard.i,
          builder: (ctx, _) {
            final g = LicenseGuard.i;
            final ok = g.canWrite;
            return ListView(padding: const EdgeInsets.all(16), children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: (ok ? C.green : C.red).withOpacity(.12), borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  Icon(ok ? Icons.verified_rounded : Icons.lock_outline_rounded, color: ok ? C.green : C.red, size: 32),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(g.message, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    if (g.expiry != null) Text('ينتهي في ${_date(g.expiry)}', style: const TextStyle(fontSize: 12.5)),
                  ])),
                ]),
              ),
              const SizedBox(height: 16),
              const Text('كود الجهاز', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  Expanded(child: SelectableText(g.deviceCode, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1.5))),
                  IconButton(onPressed: () { Clipboard.setData(ClipboardData(text: g.deviceCode)); toast(context, 'اتنسخ الكود'); }, icon: const Icon(Icons.copy_rounded)),
                  IconButton(onPressed: () => Share.share('كود جهازي للتفعيل: ${g.deviceCode}'), icon: const Icon(Icons.share_rounded)),
                ]),
              ),
              const SizedBox(height: 6),
              const Text('ابعت الكود ده للمالك عشان يديك كود التفعيل (أو كود تصحيح الوقت لو ساعة الجهاز اتلخبطت).', style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 18),
              const Text('كود التفعيل / التجديد', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              TextField(
                controller: ctl, minLines: 3, maxLines: 6, textDirection: TextDirection.ltr,
                decoration: InputDecoration(hintText: 'HRF1-....', border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: _paste, icon: const Icon(Icons.paste_rounded), label: const Text('لصق'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton.icon(onPressed: busy ? null : _activate, icon: const Icon(Icons.key_rounded), label: const Text('تفعيل'))),
              ]),
              const SizedBox(height: 18),
              const Text('لما الاشتراك أو الفترة المجانية تنتهي البرنامج بيتقفل لحد التجديد. بياناتك بتفضل محفوظة على جهازك وتظهر تاني بمجرد التفعيل.', style: TextStyle(fontSize: 12, color: Colors.black54)),
            ]);
          },
        ),
      );
}
