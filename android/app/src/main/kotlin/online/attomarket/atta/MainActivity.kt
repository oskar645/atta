package online.attomarket.atta

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AndroidRestoreCredentialsBridge(
            this,
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "atta/restore_credentials",
            ),
        ).attach()
    }
}
