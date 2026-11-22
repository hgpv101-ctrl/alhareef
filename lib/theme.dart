import 'package:flutter/material.dart';

class C {
  static const navy = Color(0xFF1E1B4B), purple = Color(0xFF7C3AED), blue = Color(0xFF2563EB), pink = Color(0xFFDB2777),
      bg = Color(0xFFF6F4FF), red = Color(0xFFF43F5E), orange = Color(0xFFEA580C), green = Color(0xFF059669), gold = Color(0xFFFBBF24),
      line = Color(0xFFECE8FF);
  static const grad = LinearGradient(colors: [navy, purple, pink], begin: Alignment.topRight, end: Alignment.bottomLeft);
  static const gradSoft = LinearGradient(colors: [Color(0xFF2E2A7A), purple], begin: Alignment.topRight, end: Alignment.bottomLeft);
  static List<BoxShadow> get shadow => [BoxShadow(color: purple.withValues(alpha: .10), blurRadius: 18, offset: const Offset(0, 6))];
}

ThemeData buildTheme({bool dark = false}) {
  final scheme = ColorScheme.fromSeed(seedColor: C.purple, brightness: dark ? Brightness.dark : Brightness.light, surfaceTint: Colors.transparent);
  final base = ThemeData(useMaterial3: true, fontFamily: 'DejaVu', colorScheme: scheme, scaffoldBackgroundColor: dark ? null : C.bg);
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'DejaVu'),
    appBarTheme: AppBarTheme(
      centerTitle: true, backgroundColor: C.navy, foregroundColor: Colors.white, elevation: 0, scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(fontFamily: 'DejaVu', fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(24))),
    ),
    cardTheme: CardThemeData(
      elevation: 0, margin: EdgeInsets.zero, color: dark ? null : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: dark ? Colors.white12 : C.line)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: dark ? null : Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: C.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: dark ? Colors.white24 : C.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: C.purple, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: C.purple, textStyle: TextStyle(fontFamily: 'DejaVu', fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), minimumSize: const Size(0, 52))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        foregroundColor: C.purple, side: const BorderSide(color: Color(0xFFC4B5FD)), textStyle: TextStyle(fontFamily: 'DejaVu', fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), minimumSize: const Size(0, 48))),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: C.pink, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
    chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), side: const BorderSide(color: C.line), selectedColor: C.purple.withValues(alpha: .18)),
    navigationBarTheme: NavigationBarThemeData(
      height: 68, backgroundColor: dark ? null : Colors.white, indicatorColor: C.purple.withValues(alpha: .15), surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontFamily: 'DejaVu', fontSize: 11, fontWeight: FontWeight.w700)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))), showDragHandle: true),
    dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
    listTileTheme: const ListTileThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20)))),
  );
}
