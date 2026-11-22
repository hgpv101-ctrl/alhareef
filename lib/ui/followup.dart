import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../core/engine.dart';
import '../core/followup.dart';
import '../core/utils.dart';
import '../data/db.dart';
import '../theme.dart';
import 'customers.dart';
import 'widgets.dart';

class FollowUpScreen extends StatefulWidget {
  const FollowUpScreen({super.key});
  @override
  State<FollowUpScreen> createState() => _S();
}

class _S extends State<FollowUpScreen> {
  List<CustFin> all = [];
  @override
  void initState() {
    super.initState();
    AppDb.i.financials().then((v) => mounted ? setState(() => all = v) : null);
  }

  @override
  Widget build(BuildContext context) {
    final g = dueGroups(all, today());
    final (rows, lateNow) = forecast(all, today(), months: 6);
    final plan = visitPlan(g.late);
    Widget cust(CustFin c, double amt, Color col) => Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetail(code: c.code))),
            title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${c.region} • ${c.phone}'),
            trailing: Text(fmtMoney(amt), style: TextStyle(color: col, fontWeight: FontWeight.w800)),
          ),
        );
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('🧭 مركز المتابعة'),
          bottom: const TabBar(isScrollable: true, labelColor: Colors.white, unselectedLabelColor: Colors.white60, indicatorColor: C.gold,
              tabs: [Tab(text: 'ملخص الصبح'), Tab(text: 'توقع التحصيل'), Tab(text: 'خطة الزيارات'), Tab(text: 'تذكير بكرة')]),
        ),
        body: TabBarView(children: [
          ListView(padding: const EdgeInsets.all(12), children: [
            SizedBox(
              height: 100,
              child: Row(children: [
                Expanded(child: Stat('📅', 'مستحق النهارده', '${g.today.length} • ${fmtMoney(g.todayAmt)}', C.blue)),
                const SizedBox(width: 8),
                Expanded(child: Stat('⏰', 'متأخرين', '${g.late.length} • ${fmtMoney(g.lateAmt)}', C.red)),
              ]),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: () => Share.share(summaryText(g)), icon: const Icon(Icons.share), label: const Text('شارك الملخص')),
            const Padding(padding: EdgeInsets.all(8), child: Text('مستحقين النهارده', style: TextStyle(fontWeight: FontWeight.w800))),
            for (final c in g.today) cust(c, g.dueAmt[c.code] ?? 0, C.blue),
            const Padding(padding: EdgeInsets.all(8), child: Text('المتأخرين', style: TextStyle(fontWeight: FontWeight.w800))),
            for (final c in g.late) cust(c, c.arrears, C.red),
          ]),
          ListView(padding: const EdgeInsets.all(12), children: [
            for (final r in rows)
              Card(child: ListTile(title: Text(r.ym, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('${r.count} قسط'), trailing: Text(fmtMoney(r.amount), style: const TextStyle(color: C.green, fontWeight: FontWeight.w800, fontSize: 16)))),
            Card(color: C.orange.withValues(alpha: .12), child: ListTile(title: const Text('متأخرات حالية (لسه ما اتحصلتش)'), trailing: Text(fmtMoney(lateNow), style: const TextStyle(color: C.orange, fontWeight: FontWeight.w800)))),
            const Padding(padding: EdgeInsets.all(8), child: Text('التوقع حسابي من جدول الأقساط ولا يحسب تأخير العملاء.', style: TextStyle(color: Colors.grey, fontSize: 12))),
          ]),
          plan.isEmpty
              ? const Empty('مفيش متأخرين محتاجين زيارة 🎉')
              : ListView(padding: const EdgeInsets.all(12), children: [
                  for (final (rep, regs) in plan) ...[
                    Padding(padding: const EdgeInsets.all(8), child: Text('🚚 $rep', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
                    for (final (reg, cs) in regs) ...[
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('$reg — ${cs.length} عميل (${fmtMoney(cs.fold<double>(0.0, (s, c) => s + c.arrears))})', style: const TextStyle(color: C.purple, fontWeight: FontWeight.w700))),
                      for (final c in cs) cust(c, c.arrears, C.red),
                    ],
                  ],
                ]),
          ListView(padding: const EdgeInsets.all(12), children: [
            Text('أقساط بكرة (${g.tomorrow.length}) — اضغط واتساب للتذكير', style: const TextStyle(fontWeight: FontWeight.w800)),
            for (final c in g.tomorrow)
              Card(
                child: ListTile(
                  title: Text(c.name),
                  subtitle: Text(fmtMoney(g.dueAmt[c.code] ?? 0)),
                  trailing: IconButton(
                    icon: const Icon(Icons.chat, color: C.green),
                    onPressed: c.phone.isEmpty ? null : () => openWhatsapp(c.phone, 'السلام عليكم ورحمة الله ${c.name} 🌹\nبنفكّرك إن قسطك مستحق بكرة:\n💰 ${fmtMoney(g.dueAmt[c.code] ?? 0)} جنيه\n📅 ${isoDate(today().add(const Duration(days: 1)))}\nياريت تجهّزه، وشكراً لتعاملك معانا 🌹'),
                  ),
                ),
              ),
          ]),
        ]),
      ),
    );
  }
}
