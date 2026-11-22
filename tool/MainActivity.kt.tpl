@@PACKAGE@@

import android.content.pm.PackageManager
import android.content.pm.Signature
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

// فحص سلامة التطبيق: بيرجّع بصمة SHA-256 لشهادة توقيع الـ APK اللي شغّال دلوقتي (التطبيق بيقارنها بمفتاحك).
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hareef/integrity").setMethodCallHandler { call, result ->
            if (call.method == "certs") {
                try {
                    result.success(certs())
                } catch (e: Exception) {
                    result.error("ERR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun certs(): List<String> {
        val sigs: Array<Signature> = if (Build.VERSION.SDK_INT >= 28) {
            val pi = packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            pi.signingInfo?.apkContentsSigners ?: emptyArray()
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES).signatures ?: emptyArray()
        }
        return sigs.map { s ->
            MessageDigest.getInstance("SHA-256").digest(s.toByteArray()).joinToString("") { b -> "%02x".format(b) }
        }
    }
}
