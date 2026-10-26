package online.attomarket.atta

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class AndroidPushNotificationsBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methodChannel = MethodChannel(messenger, "atta/push_notifications")
    private val eventChannel = EventChannel(messenger, "atta/push_notification_taps")
    private var eventSink: EventChannel.EventSink? = null
    private var pendingResult: MethodChannel.Result? = null
    private var initialPayload: Map<String, Any?>? = null

    fun attach(intent: Intent?) {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        initialPayload = payloadFromIntent(intent)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestToken" -> requestToken(result)
            "getInitialNotification" -> {
                result.success(initialPayload)
                initialPayload = null
            }
            "unregister" -> {
                FirebaseMessaging.getInstance().deleteToken()
                (activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                    .cancelAll()
                initialPayload = null
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun requestToken(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(activity, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            pendingResult?.success(null)
            pendingResult = result
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST,
            )
            return
        }
        loadToken(result)
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return
        val result = pendingResult ?: return
        pendingResult = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            loadToken(result)
        } else {
            result.success(null)
        }
    }

    private fun loadToken(result: MethodChannel.Result) {
        FirebaseMessaging.getInstance().token
            .addOnSuccessListener { token -> result.success(token) }
            .addOnFailureListener { error ->
                result.error("fcm_token_failed", error.localizedMessage, null)
            }
    }

    fun handleNotificationIntent(intent: Intent?) {
        val payload = payloadFromIntent(intent) ?: return
        eventSink?.success(payload) ?: run { initialPayload = payload }
        intent?.removeExtra(NOTIFICATION_JSON_KEY)
    }

    private fun payloadFromIntent(intent: Intent?): Map<String, Any?>? {
        val raw = intent?.getStringExtra(NOTIFICATION_JSON_KEY)?.trim().orEmpty()
        if (raw.isEmpty()) return null
        return try {
            jsonObjectToMap(JSONObject(raw))
        } catch (_: Exception) {
            null
        }
    }

    private fun jsonObjectToMap(value: JSONObject): Map<String, Any?> =
        value.keys().asSequence().associateWith { key ->
            when (val item = value.opt(key)) {
                is JSONObject -> jsonObjectToMap(item)
                JSONObject.NULL -> null
                else -> item
            }
        }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
        initialPayload?.let {
            events.success(it)
            initialPayload = null
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    companion object {
        const val NOTIFICATION_JSON_KEY = "notification"
        private const val NOTIFICATION_PERMISSION_REQUEST = 9021
    }
}
