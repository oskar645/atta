package online.attomarket.atta

import android.app.Activity
import android.os.Build
import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CreateRestoreCredentialRequest
import androidx.credentials.CreateRestoreCredentialResponse
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetRestoreCredentialOption
import androidx.credentials.RestoreCredential
import androidx.credentials.exceptions.ClearCredentialException
import androidx.credentials.exceptions.CreateCredentialException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import androidx.credentials.exceptions.restorecredential.E2eeUnavailableException
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class AndroidRestoreCredentialsBridge(
    private val activity: Activity,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler {
    private val credentialManager by lazy { CredentialManager.create(activity) }
    private val scope = CoroutineScope(Dispatchers.Main)

    fun attach() {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "create" -> create(call, result)
            "get" -> get(call, result)
            "clear" -> clear(result)
            "isSupported" -> result.success(isSupported())
            else -> result.notImplemented()
        }
    }

    private fun create(call: MethodCall, result: MethodChannel.Result) {
        val requestJson = call.argument<String>("requestJson")?.trim().orEmpty()
        if (!isSupported()) {
            result.success(notAvailable("unsupported_android_version"))
            return
        }
        if (requestJson.isEmpty()) {
            result.success(error("invalid_request", "requestJson is required"))
            return
        }

        scope.launch {
            try {
                val response = createRestoreCredential(requestJson, true)
                result.success(successCreate(response, true))
            } catch (e: E2eeUnavailableException) {
                try {
                    val response = createRestoreCredential(requestJson, false)
                    result.success(successCreate(response, false))
                } catch (fallbackError: CreateCredentialException) {
                    result.success(notAvailable(fallbackError.type))
                } catch (fallbackError: IllegalArgumentException) {
                    result.success(error("invalid_request", fallbackError.message))
                } catch (fallbackError: Throwable) {
                    result.success(error(fallbackError.javaClass.simpleName, fallbackError.message))
                }
            } catch (e: CreateCredentialException) {
                result.success(notAvailable(e.type))
            } catch (e: IllegalArgumentException) {
                result.success(error("invalid_request", e.message))
            } catch (e: Throwable) {
                result.success(error(e.javaClass.simpleName, e.message))
            }
        }
    }

    private suspend fun createRestoreCredential(
        requestJson: String,
        cloudBackupEnabled: Boolean,
    ): CreateRestoreCredentialResponse {
        val request = CreateRestoreCredentialRequest(requestJson, cloudBackupEnabled)
        val response = credentialManager.createCredential(activity, request)
        return response as CreateRestoreCredentialResponse
    }

    private fun get(call: MethodCall, result: MethodChannel.Result) {
        val requestJson = call.argument<String>("requestJson")?.trim().orEmpty()
        if (!isSupported()) {
            result.success(notAvailable("unsupported_android_version"))
            return
        }
        if (requestJson.isEmpty()) {
            result.success(error("invalid_request", "requestJson is required"))
            return
        }

        scope.launch {
            try {
                val option = GetRestoreCredentialOption(requestJson)
                val request = GetCredentialRequest(listOf(option))
                val response = credentialManager.getCredential(activity, request)
                val credential = response.credential
                if (credential is RestoreCredential) {
                    result.success(
                        mapOf(
                            "status" to "success",
                            "responseJson" to credential.authenticationResponseJson,
                        ),
                    )
                } else {
                    result.success(notAvailable("unexpected_credential_type"))
                }
            } catch (e: NoCredentialException) {
                result.success(notAvailable(e.type))
            } catch (e: GetCredentialException) {
                result.success(notAvailable(e.type))
            } catch (e: IllegalArgumentException) {
                result.success(error("invalid_request", e.message))
            } catch (e: Throwable) {
                result.success(error(e.javaClass.simpleName, e.message))
            }
        }
    }

    private fun clear(result: MethodChannel.Result) {
        if (!isSupported()) {
            result.success(notAvailable("unsupported_android_version"))
            return
        }

        scope.launch {
            try {
                credentialManager.clearCredentialState(
                    ClearCredentialStateRequest(
                        ClearCredentialStateRequest.TYPE_CLEAR_RESTORE_CREDENTIAL,
                    ),
                )
                result.success(mapOf("status" to "success"))
            } catch (e: ClearCredentialException) {
                result.success(notAvailable(e.type))
            } catch (e: Throwable) {
                result.success(error(e.javaClass.simpleName, e.message))
            }
        }
    }

    private fun isSupported() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P

    private fun successCreate(
        response: CreateRestoreCredentialResponse,
        cloudBackupEnabled: Boolean,
    ) = mapOf(
        "status" to "success",
        "responseJson" to response.responseJson,
        "cloudBackupEnabled" to cloudBackupEnabled,
    )

    private fun notAvailable(reason: String?) = mapOf(
        "status" to "notAvailable",
        "reason" to (reason ?: "not_available"),
    )

    private fun error(code: String, message: String?) = mapOf(
        "status" to "error",
        "code" to code,
        "message" to (message ?: "Restore credentials failed"),
    )
}
