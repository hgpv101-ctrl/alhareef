import 'package:flutter/material.dart';
import '../theme.dart';

/// شعار الحريف المدير الذكي: تاج ذهبي على خلفية متدرجة
class HareefLogo extends StatelessWidget {
  const HareefLogo({super.key, this.size = 96, this.shadow = true});
  final double size;
  final bool shadow;
  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [C.navy, C.purple, C.pink]),
          borderRadius: BorderRadius.circular(size * .3),
          boxShadow: shadow ? [BoxShadow(color: Colors.black.withValues(alpha: .28), blurRadius: size * .25, offset: Offset(0, size * .1))] : null,
        ),
        child: CustomPaint(painter: _LogoPainter()),
      );
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final k = s.width / 100;
    Offset p(double x, double y) => Offset(x * k, y * k);
    final gold = Paint()..color = C.gold..style = PaintingStyle.fill;
    final crown = Path()
      ..moveTo(24 * k, 68 * k)
      ..lineTo(19 * k, 40 * k)
      ..lineTo(38 * k, 54 * k)
      ..lineTo(50 * k, 34 * k)
      ..lineTo(62 * k, 54 * k)
      ..lineTo(81 * k, 40 * k)
      ..lineTo(76 * k, 68 * k)
      ..close();
    canvas.drawPath(crown, gold);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(24 * k, 72 * k, 52 * k, 8 * k), Radius.circular(4 * k)), gold);
    for (final c in [p(19, 38), p(50, 32), p(81, 38)]) {
      canvas.drawCircle(c, 3.6 * k, gold);
    }
    // نجمة صغيرة
    final spark = Path()
      ..moveTo(50 * k, 9 * k)
      ..quadraticBezierTo(51.5 * k, 16.5 * k, 59 * k, 18 * k)
      ..quadraticBezierTo(51.5 * k, 19.5 * k, 50 * k, 27 * k)
      ..quadraticBezierTo(48.5 * k, 19.5 * k, 41 * k, 18 * k)
      ..quadraticBezierTo(48.5 * k, 16.5 * k, 50 * k, 9 * k)
      ..close();
    canvas.drawPath(spark, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
