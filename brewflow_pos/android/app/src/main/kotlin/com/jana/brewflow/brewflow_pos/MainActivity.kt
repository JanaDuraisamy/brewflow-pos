package com.jana.brewflow.brewflow_pos

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "brewflow_pos/upi"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledUpiApps" -> result.success(installedUpiApps())
                "launchUpiApp" -> {
                    val packageName = call.argument<String>("packageName")
                    val amount = call.argument<String>("amountRupees")
                    val currency = call.argument<String>("currency") ?: "INR"
                    val note = call.argument<String>("note")
                    if (packageName.isNullOrEmpty() || amount.isNullOrEmpty()) {
                        result.error(
                            "INVALID_ARGUMENT",
                            "A UPI app and a valid amount are required.",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    try {
                        launchUpiApp(packageName, amount, currency, note)
                        result.success(null)
                    } catch (e: ActivityNotFoundException) {
                        result.error(
                            "APP_NOT_FOUND",
                            "The selected UPI app is no longer available.",
                            null
                        )
                    } catch (e: Exception) {
                        result.error(
                            "LAUNCH_FAILED",
                            "Could not open the selected UPI app.",
                            null
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Apps that resolve a UPI payment VIEW intent. Only packages the OS
     * reports for this exact intent are returned (see the narrow `<queries>`
     * declarations in AndroidManifest.xml) — never a hard-coded list, and
     * never a broad package enumeration, so no extra permission is needed.
     */
    private fun installedUpiApps(): List<Map<String, String>> {
        val intents = listOf(
            Intent(Intent.ACTION_VIEW, Uri.parse("upi://pay")),
            Intent(Intent.ACTION_VIEW, Uri.parse("tez://upi/pay"))
        )
        val seen = linkedMapOf<String, String>()
        for (intent in intents) {
            val infos = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.queryIntentActivities(
                    intent,
                    PackageManager.ResolveInfoFlags.of(
                        PackageManager.MATCH_DEFAULT_ONLY.toLong()
                    )
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.queryIntentActivities(
                    intent,
                    PackageManager.MATCH_DEFAULT_ONLY
                )
            }
            for (info in infos) {
                val packageName = info.activityInfo?.packageName ?: continue
                // Never offer BrewFlow itself, however it got here.
                if (packageName == applicationContext.packageName) continue
                val label = info.loadLabel(packageManager)?.toString()
                if (label.isNullOrEmpty()) continue
                seen.putIfAbsent(packageName, label)
            }
        }
        return seen.entries
            .sortedBy { it.value.lowercase() }
            .map { mapOf("packageName" to it.key, "displayName" to it.value) }
    }

    /**
     * Opens [packageName] with a best-effort UPI payment URI. The payee
     * address is unknown to BrewFlow, so this is a handoff — the owner
     * completes the payment in the UPI app and confirms it back in BrewFlow,
     * which never treats the launch (or the return) as payment success.
     */
    private fun launchUpiApp(
        packageName: String,
        amount: String,
        currency: String,
        note: String?
    ) {
        val builder = Uri.parse("upi://pay").buildUpon()
            .appendQueryParameter("am", amount)
            .appendQueryParameter("cu", currency)
        if (!note.isNullOrEmpty()) {
            builder.appendQueryParameter("tn", note)
        }
        val intent = Intent(Intent.ACTION_VIEW, builder.build())
            .setPackage(packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }
}
