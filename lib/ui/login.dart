import 'package:flutter/material.dart';
import '../data/db.dart';
import '../theme.dart';
import '../version.dart';
import '../data/ops.dart';
import 'home.dart';
import 'logo.dart';
import 'rep_mode.dart';
import 'widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.skipAuto = false});
  final bool skipAuto;
  @override
  State<LoginScreen> createState() => _S();
}

class _S extends State<LoginScreen> {
  final pw = TextEditingController(), user = TextEditingController(text: 'admin');
  bool busy = false, remember = false;

  @override
  void initState() {
    super.initState();
    if (widget.skipAuto) return;
    () async {
      final db = AppDb.i;
      if (await db.getSetting('require_login') != 'نعم') {
        if (mounted) _enter('Admin');
        return;
      }
      // دخول سريع: لو المستخدم اختار «ابقَ مسجّلًا» قبل كده بندخله على طول
      final ru = await db.getSetting('remember_user');
      if (ru.isNotEmpty) {
        final role = await db.roleOf(ru);
        if (role != null && mounted) {
          db.who = ru;
          _enter(role);
        }
      }
    }();
  }

  void _enter(String role) => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomeScreen(role: role)));

  Future<void> _go() async {
    setState(() => busy = true);
    final role = await AppDb.i.login(user.text, pw.text);
    if (!mounted) return;
    setState(() => busy = false);
    if (role != null) {
      await AppDb.i.setSetting('remember_user', remember ? (user.text.trim().isEmpty ? 'admin' : user.text.trim()) : '');
      _enter(role);
    } else {
      toast(context, 'كلمة السر غلط', err: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: C.grad),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(children: [
                const HareefLogo(size: 100),
                const SizedBox(height: 14),
                const Text('الحريف المدير الذكي', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                const Text('إدارة المبيعات والتقسيط', style: TextStyle(color: Colors.white70)),
                const Text('الإصدار $appVersion', style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 30),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(children: [
                      TextField(controller: user, decoration: const InputDecoration(labelText: 'المستخدم', prefixIcon: Icon(Icons.person_rounded))),
                      const SizedBox(height: 10),
                      TextField(
                        controller: pw, obscureText: true, keyboardType: TextInputType.number, onSubmitted: (_) => _go(),
                        decoration: const InputDecoration(labelText: 'كلمة سر المدير', prefixIcon: Icon(Icons.lock_rounded)),
                      ),
                      CheckboxListTile(
                        value: remember, onChanged: (v) => setState(() => remember = v ?? false), dense: true, contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading, title: const Text('ابقَ مسجّلًا على الجهاز (دخول سريع)', style: TextStyle(fontSize: 13)),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(width: double.infinity, child: FilledButton(onPressed: busy ? null : _go, child: Text(busy ? '...' : 'دخول'))),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const RepHomeScreen())),
                          icon: const Icon(Icons.directions_walk_rounded),
                          label: const Text('دخول كمندوب / محصّل'),
                        ),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
}
