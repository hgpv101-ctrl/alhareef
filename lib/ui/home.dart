import 'package:flutter/material.dart';
import '../core/security.dart';
import '../core/utils.dart';
import '../data/db.dart';
import '../theme.dart';
import '../version.dart';
import 'collection.dart';
import 'concepts.dart';
import 'regions.dart';
import 'crud.dart';
import 'customers.dart';
import 'followup.dart';
import 'hareef.dart';
import 'login.dart';
import 'logo.dart';
import 'print_screen.dart';
import 'ops_screens.dart';
import 'outreach.dart';
import 'rep_review.dart';
import 'reports.dart';
import 'settings.dart';
import 'stock.dart';

class _Item {
  const _Item(this.key, this.icon, this.title, this.sub, this.builder, this.color);
  final String key, title, sub;
  final IconData icon;
  final Widget Function() builder;
  final Color color;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.role});
  final String role;
  @override
  State<HomeScreen> createState() => _S();
}

class _S extends State<HomeScreen> {
  Map<String, String> k = {};
  int tab = 0;
  late final List<MapEntry<String, List<_Item>>> groups;
  final Set<int> _seen = {0}; // التبويبات اللي اتفتحت (الباقي مابيتبناش لحد ما تدوس عليه)

  @override
  void initState() {
    super.initState();
    groups = [
      MapEntry('المندوبين والمحصلين', [
        _Item('admin', Icons.visibility_rounded, 'متابعة المندوبين', 'استيراد ملفاتهم وكشف الأخطاء والاعتماد', () => const RepFollowScreen(), C.pink),
        _Item('admin', Icons.badge_rounded, 'متابعة المحصّلين', 'أداء كل محصّل وتحصيلاته', () => const CollectorsScreen(), C.green),
        _Item('admin', Icons.flag_rounded, 'أهداف المناديب', 'التارجت الشهري ونسبة التحقيق', () => const TargetsScreen(), C.orange),
      ]),
      MapEntry('المخزن والفريق', [
        _Item('warehouse', Icons.warehouse_rounded, 'المخزن', 'الأصناف والوارد والمتابعة والعهدة', () => const StockHome(), C.navy),
        _Item('reps', Icons.local_shipping_rounded, 'مناديب ومحصلين', 'الفريق وأمناء المخازن', () => crudReps(), C.blue),
        _Item('custody', Icons.assignment_rounded, 'إدارة العهدة', 'تسليم بضاعة للمناديب بأكتر من صنف وإرجاعها', () => const StockHome(initialTab: 3), C.purple),
        _Item('regions', Icons.place_rounded, 'المناطق', 'تسجيل المناطق وبياناتها وتوزيعها على المحصّلين', () => const RegionsHub(), C.green),
      ]),
      MapEntry('عمليات إضافية', [
        _Item('customers', Icons.receipt_rounded, 'فواتير البيع', 'فاتورة لكل عقد', () => const SalesInvoicesScreen(), C.purple),
        _Item('customers', Icons.undo_rounded, 'المرتجعات', 'تحديث حساب العميل والمخزن', () => const ReturnsScreen(), C.orange),
        _Item('customers', Icons.chat_rounded, 'رسائل واتساب للعملاء', 'تذكير أو رسالة لكل العملاء على دفعات مع تتبّع مين اتبعتله', () => const BulkMessageScreen(), C.green),
        _Item('customers', Icons.near_me_rounded, 'العملاء الأقرب ليك', 'ترتيب بالمسافة وجولة على خرائط جوجل', () => const NearbyCustomersScreen(), C.blue),
        _Item('customers', Icons.sell_rounded, 'الخصومات', 'خصم على إجمالي العميل', () => const DiscountsScreen(), C.blue),
        _Item('products', Icons.heart_broken_rounded, 'التالف', 'تالف وتكلفته', () => const DamagesScreen(), C.red),
        _Item('suppliers', Icons.factory_rounded, 'فواتير الموردين', 'فواتير وسدادات', () => const SupplierInvoicesScreen(), C.navy),
        _Item('admin', Icons.apartment_rounded, 'الفروع', 'فروع الشركة', () => const BranchesScreen(), C.green),
        _Item('admin', Icons.manage_accounts_rounded, 'المستخدمين والصلاحيات', 'محاسب / أمين مخزن', () => const UsersScreen(), C.purple),
      ]),
      MapEntry('المال', [
        _Item('suppliers', Icons.store_rounded, 'الموردين', 'بيانات الموردين', () => crudSuppliers(), C.orange),
        _Item('expenses', Icons.money_off_rounded, 'المصروفات', 'مصاريف اليوم والشهر', () => crudExpenses(), C.red),
        _Item('partners', Icons.handshake_rounded, 'المساهمين والأرباح', 'رأس المال والنِّسب', () => crudPartners(), C.pink),
        _Item('settlement', Icons.calculate_rounded, 'تصفية المناديب', 'العمولات والتسوية', () => const SettlementScreen(), C.green),
      ]),
      MapEntry('الطباعة', [
        _Item('receipts', Icons.print_rounded, 'الطباعة', 'طباعة إيصالات اليوم / الشهر / السنة / فترة', () => const PrintScreen(), C.purple),
      ]),
      MapEntry('التقارير', [
        _Item('reports', Icons.insights_rounded, 'التقارير الشاملة', 'الصورة الكاملة للشركة', () => const GeneralReport(), C.purple),
        _Item('reports', Icons.schedule_rounded, 'متأخرات التقسيط', 'مين متأخر وكام', () => const LateReport(), C.red),
        _Item('whatsapp', Icons.chat_rounded, 'تذكير واتساب', 'رسالة جاهزة بضغطة', () => const WhatsappReminders(), C.green),
        _Item('reports', Icons.directions_run_rounded, 'تقرير المندوبين', 'أداء كل مندوب', () => const RepsReport(), C.blue),
        _Item('reports', Icons.calendar_month_rounded, 'التجميعات الشهرية', 'ملخص كل شهر', () => const MonthlyReport(), C.navy),
        _Item('inout', Icons.swap_vert_rounded, 'الداخل والخارج', 'حركة المخزن', () => const InOutReport(), C.orange),
        _Item('receipts', Icons.receipt_long_rounded, 'دفتر الإيصالات', 'كل الإيصالات وPDF', () => const ReceiptsBook(), C.pink),
      ]),
      MapEntry('النظام', [
        _Item('customers', Icons.menu_book_rounded, 'مفاهيم', 'شرح كل خانة ومصطلح في البرنامج', () => const ConceptsScreen(), C.blue),
        _Item('admin', Icons.history_rounded, 'سجل العمليات', 'مين عمل إيه ومتى', () => const AuditScreen(), C.navy),
        _Item('admin', Icons.settings_rounded, 'الإعدادات', 'الشركة والإيصال والأمان والنسخ الاحتياطي', () => const SettingsScreen(), C.purple),
      ]),
    ];
    _load();
    dataRev.addListener(_load);
  }

  @override
  void dispose() {
    dataRev.removeListener(_load);
    super.dispose();
  }

  bool can(String key) => canOpen(widget.role, key);

  Future<void> _load() async {
    final db = AppDb.i;
    final fin = await db.financials();
    final t = isoDate(today());
    final col = await db.db.rawQuery("SELECT IFNULL(SUM(amount_paid),0) s FROM payments WHERE pay_date=? AND IFNULL(due_month,'')!=?", [t, downLabel]);
    final low = await db.db.rawQuery('SELECT COUNT(*) n FROM products WHERE IFNULL(qty,0) <= IFNULL(min_qty,3)');
    final val = await db.db.rawQuery('SELECT IFNULL(SUM(qty*buy_price),0) s FROM products WHERE qty>0');
    if (!mounted) return;
    setState(() => k = {
          'today': fmtMoney(col.first['s'] as num),
          'late': '${fin.where((f) => f.late).length}',
          'low': '${low.first['n']}',
          'val': fmtMoney(val.first['s'] as num),
          'remain': fmtMoney(fin.fold<double>(0, (s, f) => s + f.remaining)),
          'n': '${fin.length}',
        });
  }

  Future<void> _logout() async {
    await AppDb.i.setSetting('remember_user', '');
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen(skipAuto: true)), (_) => false);
  }

  void push(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w)).then((_) => _load());

  Widget _stat(IconData i, String label, String value, Color c, VoidCallback? f) => InkWell(
        onTap: f, borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: C.shadow),
          child: Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: c.withValues(alpha: .13), borderRadius: BorderRadius.circular(14)), child: Icon(i, color: c)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c))),
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ])),
          ]),
        ),
      );

  Widget _quick(IconData i, String t, Color c, VoidCallback f) => InkWell(
        onTap: f, borderRadius: BorderRadius.circular(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 62, height: 62,
            decoration: BoxDecoration(gradient: LinearGradient(colors: [c, c.withValues(alpha: .7)], begin: Alignment.topRight, end: Alignment.bottomLeft), borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: c.withValues(alpha: .3), blurRadius: 12, offset: const Offset(0, 5))]),
            child: Icon(i, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 6),
          Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _homeTab() => RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(gradient: C.grad, borderRadius: BorderRadius.vertical(bottom: Radius.circular(36))),
              padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 26),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const HareefLogo(size: 46, shadow: false),
                  const SizedBox(width: 12),
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('أهلاً يا باشا', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text('الحريف المدير الذكي', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                  ])),
                  Text('v$appVersion', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  IconButton(tooltip: 'تسجيل خروج', onPressed: _logout, icon: const Icon(Icons.logout_rounded, color: Colors.white70, size: 20)),
                ]),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white24)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('إجمالي المتبقي عند العملاء', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text('${k['remain'] ?? '...'} جنيه', style: const TextStyle(color: C.gold, fontSize: 28, fontWeight: FontWeight.w900)),
                    Text('${k['n'] ?? '-'} عميل', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  ]),
                ),
              ]),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
            sliver: SliverToBoxAdapter(
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                if (can('customers')) _quick(Icons.groups_rounded, 'العملاء', C.purple, () => setState(() => tab = 1)),
                if (can('collection')) _quick(Icons.payments_rounded, 'التحصيل', C.green, () => setState(() => tab = 2)),
                if (can('followup')) _quick(Icons.explore_rounded, 'المتابعة', C.blue, () => push(const FollowUpScreen())),
                _quick(Icons.smart_toy_rounded, 'الحريف', C.pink, () => setState(() => tab = 3)),
              ]),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid.count(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.0, children: [
              _stat(Icons.account_balance_wallet_rounded, 'المحصّل النهارده', k['today'] ?? '-', C.green, can('collection') ? () => setState(() => tab = 2) : null),
              _stat(Icons.alarm_rounded, 'عملاء متأخرين', k['late'] ?? '-', C.orange, can('reports') ? () => push(const LateReport()) : null),
              _stat(Icons.warning_amber_rounded, 'أصناف ناقصة', k['low'] ?? '-', C.red, can('warehouse') ? () => push(const StockHome()) : null),
              _stat(Icons.warehouse_rounded, 'قيمة المخزن', k['val'] ?? '-', C.purple, can('warehouse') ? () => push(const StockHome()) : null),
            ]),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ]),
      );

  Widget _moreTab() => Scaffold(
        appBar: AppBar(title: const Text('المزيد')),
        body: ListView(padding: const EdgeInsets.all(14), children: [
          for (final g in groups)
            if (g.value.any((i) => can(i.key)))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    shape: const Border(), collapsedShape: const Border(),
                    title: Text(g.key, style: const TextStyle(fontWeight: FontWeight.w800)),
                    children: [
                      for (final it in g.value.where((i) => can(i.key)))
                        ListTile(
                          onTap: () => push(it.builder()),
                          leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: it.color.withValues(alpha: .13), borderRadius: BorderRadius.circular(13)), child: Icon(it.icon, color: it.color, size: 22)),
                          title: Text(it.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          subtitle: Text(it.sub, style: const TextStyle(fontSize: 11)),
                          trailing: const Icon(Icons.chevron_left_rounded),
                        ),
                    ],
                  ),
                ),
              ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final tabs = <(String, IconData, Widget)>[
      ('الرئيسية', Icons.home_rounded, _homeTab()),
      if (can('customers')) ('العملاء', Icons.groups_rounded, const CustomersScreen()),
      if (can('collection')) ('التحصيل', Icons.payments_rounded, const CollectionScreen()),
      ('الحريف', Icons.smart_toy_rounded, HareefScreen(role: widget.role)),
      ('المزيد', Icons.grid_view_rounded, _moreTab()),
    ];
    final int i = tab.clamp(0, tabs.length - 1).toInt();
    _seen.add(i);
    return Scaffold(
      body: IndexedStack(index: i, children: [for (var n = 0; n < tabs.length; n++) _seen.contains(n) ? tabs[n].$3 : const SizedBox.shrink()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: i,
        onDestinationSelected: (v) {
          setState(() => tab = v);
          if (v == 0) _load();
        },
        destinations: [for (final t in tabs) NavigationDestination(icon: Icon(t.$2), label: t.$1)],
      ),
    );
  }
}
