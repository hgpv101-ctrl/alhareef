import 'package:flutter/material.dart';
import '../data/db.dart';
import '../theme.dart';

void toast(BuildContext c, String m, {bool err = false}) {
  ScaffoldMessenger.of(c).hideCurrentSnackBar();
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(
    content: Text(m), backgroundColor: err ? C.red : C.green, behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));
}

String errText(Object e) {
  if (e is FormatException) return e.message;
  final t = e.toString();
  if (t.contains('LICENSE_READONLY')) return 'الاشتراك منتهي أو غير مفعّل — البرنامج للقراءة فقط. فعّل أو جدّد من «الاشتراك والترخيص».';
  return t;
}

Future<void> guard(BuildContext c, Future<void> Function() f, {String? ok}) async {
  try {
    await f();
    if (ok != null && c.mounted) toast(c, ok);
  } catch (e) {
    if (c.mounted) toast(c, errText(e), err: true);
  }
}

Future<bool> confirm(BuildContext c, String msg) async =>
    (await showDialog<bool>(
      context: c,
      builder: (_) => AlertDialog(title: const Text('تأكيد'), content: Text(msg), actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('لأ')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('أيوه')),
      ]),
    )) ?? false;

/// كان بيطلب باسورد المدير قبل التعديل والحذف. اتلغى: كلمة السر الوحيدة دلوقتي هي اللي عند فتح التطبيق.
/// (سبناه بنفس الاسم عشان كل الشاشات اللي بتناديه تفضل شغّالة من غير أي تغيير)
Future<bool> adminGate(BuildContext c, [String why = '']) async => true;

class Field extends StatelessWidget {
  const Field(this.label, this.ctl, {super.key, this.num = false, this.lines = 1, this.hint});
  final String label;
  final TextEditingController ctl;
  final bool num;
  final int lines;
  final String? hint;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: ctl, maxLines: lines,
          keyboardType: num ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
      );
}

class Stat extends StatelessWidget {
  const Stat(this.icon, this.label, this.value, this.color, {super.key, this.onTap});
  final String icon, label, value;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(icon, style: const TextStyle(fontSize: 24)),
            const Spacer(),
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: const TextStyle(fontSize: 12)),
          ]),
        ),
      );
}

class Pill extends StatelessWidget {
  const Pill(this.t, this.c, {super.key});
  final String t;
  final Color c;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: .15), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

class Empty extends StatelessWidget {
  const Empty(this.t, {super.key});
  final String t;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(40), child: Text(t, style: const TextStyle(color: Colors.grey))));
}
