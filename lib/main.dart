import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/pdf_fonts.dart';
import 'data/db.dart';
import 'data/license.dart';
import 'theme.dart';
import 'ui/license_screen.dart';
import 'ui/login.dart';
import 'ui/logo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HareefApp());
}

class HareefApp extends StatelessWidget {
  const HareefApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'الحريف المدير الذكي',
        debugShowCheckedModeBanner: false,
        navigatorKey: navKey,
        builder: (context, child) => LicenseShell(child: child ?? const SizedBox.shrink()),
        theme: buildTheme(),
        darkTheme: buildTheme(dark: true),
        locale: const Locale('ar', 'EG'),
        supportedLocales: const [Locale('ar', 'EG')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const _Boot(),
      );
}

/// شاشة بداية بتظهر فوراً وقاعدة البيانات بتتفتح وراها (كانت الشاشة بتفضل فاضية لحد ما تخلص)
class _Boot extends StatefulWidget {
  const _Boot();
  @override
  State<_Boot> createState() => _BootS();
}

class _BootS extends State<_Boot> {
  late final Future<void> _f = _init();

  Future<void> _init() async {
    await AppDb.open();
    await AppDb.i.warmSettings();
    await LicenseGuard.i.start(); // فحص الترخيص والوقت وتفعيل القراءة فقط عند اللزوم
    // نسخّن خط الإيصالات في الخلفية عشان أول طباعة تبقى فورية
    loadPdfFonts().then((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: _f,
        builder: (ctx, s) {
          if (s.connectionState == ConnectionState.done && !s.hasError) return const LoginScreen();
          return Scaffold(
            backgroundColor: C.navy,
            body: Center(
              child: s.hasError
                  ? Padding(padding: const EdgeInsets.all(24), child: Text('تعذّر فتح قاعدة البيانات\n${s.error}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)))
                  : const Column(mainAxisSize: MainAxisSize.min, children: [
                      HareefLogo(size: 96),
                      SizedBox(height: 28),
                      CircularProgressIndicator(color: C.gold),
                    ]),
            ),
          );
        },
      );
}
