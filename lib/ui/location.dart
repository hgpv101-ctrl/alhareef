// موقع العميل: «خذ عنوان هذا المكان» (GPS + اسم الشارع تلقائي) • لصق رابط/إحداثيات من خرائط جوجل • فتح الموقع في خرائط جوجل والملاحة له.
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import 'widgets.dart';

typedef GeoPt = ({double lat, double lng});

String geoText(GeoPt p) => '${p.lat.toStringAsFixed(6)}, ${p.lng.toStringAsFixed(6)}';

bool _valid(double lat, double lng) => lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180 && !(lat == 0 && lng == 0);

/// بيطلّع الإحداثيات من رابط خرائط جوجل (…@30.04,31.23 / ?q=30.04,31.23 / !3d30.04!4d31.23) أو من نص «30.04, 31.23»
GeoPt? parseMapsText(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  final pats = <RegExp>[
    RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)'),
    RegExp(r'@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)'),
    RegExp(r'[?&](?:q|ll|query|destination|center)=(-?\d+(?:\.\d+)?)(?:,|%2C)\s*(-?\d+(?:\.\d+)?)'),
    RegExp(r'^\s*(-?\d{1,3}(?:\.\d+)?)\s*[,;\s]\s*(-?\d{1,3}(?:\.\d+)?)\s*$'),
  ];
  for (final p in pats) {
    final m = p.firstMatch(t);
    if (m == null) continue;
    final a = double.tryParse(m.group(1)!), b = double.tryParse(m.group(2)!);
    if (a != null && b != null && _valid(a, b)) return (lat: a, lng: b);
  }
  return null;
}

/// الموقع الحالي بالـ GPS (بيطلب الإذن لو لازم). بيرمي FormatException برسالة واضحة لو مش متاح.
Future<GeoPt> currentGeo() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    await Geolocator.openLocationSettings(); // بيفتح شاشة تشغيل الموقع
    throw const FormatException('شغّل خدمة الموقع (GPS) من الشاشة اللي اتفتحت، وارجع اضغط الزرار تاني.');
  }
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
  if (perm == LocationPermission.denied) throw const FormatException('لازم تسمح للتطبيق بالوصول للموقع.');
  if (perm == LocationPermission.deniedForever) {
    await Geolocator.openAppSettings(); // بيفتح إعدادات التطبيق عشان يسمح بالموقع
    throw const FormatException('فعّل إذن «الموقع» للتطبيق من الشاشة اللي اتفتحت، وارجع اضغط الزرار تاني.');
  }
  final p = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 25)),
  );
  return (lat: p.latitude, lng: p.longitude);
}

/// اسم المكان/الشارع من الإحداثيات (بيشتغل بالنت؛ لو فشل بيرجّع null والإحداثيات بتتحفظ برضه)
Future<String?> addressFromGeo(GeoPt p) async {
  try {
    final list = await placemarkFromCoordinates(p.lat, p.lng).timeout(const Duration(seconds: 12));
    if (list.isEmpty) return null;
    final m = list.first;
    final parts = <String>[];
    for (final s in [m.street, m.subLocality, m.locality, m.subAdministrativeArea, m.administrativeArea]) {
      final v = (s ?? '').trim();
      if (v.isNotEmpty && !parts.contains(v)) parts.add(v);
    }
    return parts.isEmpty ? null : parts.join('، ');
  } catch (_) {
    return null;
  }
}

Future<bool> _open(Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);

/// يفتح مكان العميل في خرائط جوجل
Future<void> openInMaps(BuildContext c, GeoPt p) async {
  final ok = await _open(Uri.parse('https://www.google.com/maps/search/?api=1&query=${p.lat},${p.lng}')).catchError((_) => false);
  if (!ok && c.mounted) toast(c, 'مش قادر أفتح خرائط جوجل', err: true);
}

/// يبدأ الملاحة من مكانك الحالي لمكان العميل
Future<void> navigateTo(BuildContext c, GeoPt p) async {
  final ok = await _open(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${p.lat},${p.lng}&travelmode=driving')).catchError((_) => false);
  if (!ok && c.mounted) toast(c, 'مش قادر أفتح خرائط جوجل', err: true);
}

/// بحث بنص العنوان في خرائط جوجل (لعميل ملوش موقع متحدد بس عنده عنوان مكتوب)
Future<void> searchAddressInMaps(BuildContext c, String text) async {
  final ok = await _open(Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(text)}')).catchError((_) => false);
  if (!ok && c.mounted) toast(c, 'مش قادر أفتح خرائط جوجل', err: true);
}

/// بيتحط تحت خانة العنوان في تسجيل العميل (مالك أو مندوب)
class LocationField extends StatefulWidget {
  const LocationField({super.key, required this.addr, required this.point, required this.onChanged});
  final TextEditingController addr; // خانة العنوان المكتوب (بتتملّى لو العنوان فاضي)
  final GeoPt? point;
  final ValueChanged<GeoPt?> onChanged;
  @override
  State<LocationField> createState() => _LF();
}

class _LF extends State<LocationField> {
  bool busy = false;

  Future<void> _here() async {
    setState(() => busy = true);
    try {
      final p = await currentGeo();
      widget.onChanged(p);
      final a = await addressFromGeo(p);
      if (!mounted) return;
      if (a != null && a.isNotEmpty) {
        // لو العنوان مكتوب قبل كده بنسأل قبل ما نستبدله، غير كده بنكتبه على طول
        if (widget.addr.text.trim().isEmpty || await confirm(context, 'أستبدل العنوان المكتوب بعنوان المكان ده؟\n$a')) {
          widget.addr.text = a;
        }
      }
      if (mounted) toast(context, a == null ? 'اتحدد الموقع ✅ (العنوان النصي ما اتجابش — اكتبه بإيدك)' : 'اتحدد الموقع والعنوان ✅');
    } on FormatException catch (e) {
      if (mounted) toast(context, e.message, err: true);
    } catch (e) {
      if (mounted) toast(context, 'ما قدرتش أجيب الموقع: ${errText(e)}', err: true);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _paste() async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('لصق موقع من خرائط جوجل'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('الصق رابط الموقع (من «مشاركة» في خرائط جوجل) أو الإحداثيات زي: 30.0444, 31.2357', style: TextStyle(fontSize: 12.5)),
          const SizedBox(height: 8),
          TextField(controller: ctl, autofocus: true, maxLines: 3, decoration: const InputDecoration(hintText: 'https://www.google.com/maps/...')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('تأكيد')),
        ],
      ),
    );
    final txt = ctl.text;
    ctl.dispose();
    if (ok != true || !mounted) return;
    final p = parseMapsText(txt);
    if (p == null) {
      toast(context, 'مش قادر أقرا إحداثيات من النص ده. الروابط المختصرة (goo.gl) افتحها الأول وانسخ الرابط الطويل أو الإحداثيات.', err: true);
      return;
    }
    widget.onChanged(p);
    toast(context, 'اتحدد الموقع ✅');
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.point;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: C.blue.withValues(alpha: .07), borderRadius: BorderRadius.circular(14), border: Border.all(color: C.blue.withValues(alpha: .25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(p == null ? Icons.location_off_rounded : Icons.location_on_rounded, color: p == null ? Colors.grey : C.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(p == null ? 'موقع العميل على الخريطة: لسه ما اتحددش' : 'اتحدد الموقع: ${geoText(p)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          if (p != null) IconButton(tooltip: 'مسح الموقع', visualDensity: VisualDensity.compact, onPressed: () => widget.onChanged(null), icon: const Icon(Icons.close_rounded, size: 20)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          FilledButton.icon(
            onPressed: busy ? null : _here,
            icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.my_location_rounded, size: 18),
            label: const Text('خذ عنوان هذا المكان'),
          ),
          OutlinedButton.icon(onPressed: _paste, icon: const Icon(Icons.link_rounded, size: 18), label: const Text('لصق رابط / إحداثيات')),
          if (p != null) OutlinedButton.icon(onPressed: () => openInMaps(context, p), icon: const Icon(Icons.map_rounded, size: 18), label: const Text('عرض على الخريطة')),
        ]),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('وانت واقف عند العميل اضغط «خذ عنوان هذا المكان» — بيحفظ مكانه بالظبط ويكتب اسم الشارع. تقدر تكتب العنوان بإيدك برضه.', style: TextStyle(color: Colors.grey, fontSize: 11.5)),
        ),
      ]),
    );
  }
}
