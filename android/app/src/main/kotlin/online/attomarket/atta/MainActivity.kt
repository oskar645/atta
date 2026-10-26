package online.attomarket.atta

import android.content.Intent
import android.os.Bundle
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var pushBridge: AndroidPushNotificationsBridge

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AndroidRestoreCredentialsBridge(
            this,
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "atta/restore_credentials",
            ),
        ).attach()
        pushBridge = AndroidPushNotificationsBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        pushBridge.attach(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (::pushBridge.isInitialized) pushBridge.handleNotificationIntent(intent)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (::pushBridge.isInitialized) {
            pushBridge.onRequestPermissionsResult(requestCode, grantResults)
        }
    }
}
