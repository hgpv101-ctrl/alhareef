#!/bin/sh
# تجهيز مشروع الأندرويد: اسم التطبيق + الأيقونة. شغّله مرة واحدة من مجلد المشروع.
set -e
flutter create . --platforms=android --org com.hareef --project-name hareef_app
sed -i 's#android:label="[^"]*"#android:label="الحريف المدير الذكي"#' android/app/src/main/AndroidManifest.xml
M=android/app/src/main/AndroidManifest.xml
grep -q 'android.permission.INTERNET' $M || sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/><application#' $M
grep -q 'android.permission.ACCESS_FINE_LOCATION' $M || sed -i 's#<application#<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/><uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/><application#' $M
mkdir -p $HOME/.android && [ -f $HOME/.android/debug.keystore ] || cp tool/hareef_debug.keystore $HOME/.android/debug.keystore
F=$(find android/app/src/main -name MainActivity.kt | head -1)
PKG=$(grep -m1 '^package ' "$F")
sed "s#@@PACKAGE@@#$PKG#" tool/MainActivity.kt.tpl > "$F"
flutter pub get
dart run flutter_launcher_icons
echo "تمام — دلوقتي: flutter run"
