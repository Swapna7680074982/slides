package com.example.slides

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private val closeReceiver =
        object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action == UsbWatcherService.ACTION_CLOSE_SLIDES) {
                    finishAndRemoveTask()
                }
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as android.app.KeyguardManager
            keyguardManager.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                android.view.WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
        super.onCreate(savedInstanceState)
        val serviceIntent = Intent(this, UsbWatcherService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
        registerCloseReceiver()

        if (intent?.getBooleanExtra("is_boot_launch", false) == true) {
            checkUsbAndPotentiallyClose()
        }
    }

    override fun onResume() {
        super.onResume()
        // Keep sending the user to "Display over other apps" until they enable it.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName"),
                ),
            )
            return
        }
        val refresh = Intent(this, UsbWatcherService::class.java).apply {
            putExtra(UsbWatcherService.EXTRA_REFRESH_FROM_ACTIVITY, true)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(refresh)
        } else {
            startService(refresh)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    override fun onDestroy() {
        runCatching { unregisterReceiver(closeReceiver) }
        super.onDestroy()
    }

    private fun registerCloseReceiver() {
        val filter = IntentFilter(UsbWatcherService.ACTION_CLOSE_SLIDES)
        ContextCompat.registerReceiver(
            this,
            closeReceiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
    }

    private fun checkUsbAndPotentiallyClose() {
        val usbManager = getSystemService(Context.USB_SERVICE) as? android.hardware.usb.UsbManager ?: return
        val hasDevice = usbManager.deviceList.isNotEmpty()
        @Suppress("DEPRECATION")
        val hasAccessory = usbManager.accessoryList?.isNotEmpty() == true
        if (!hasDevice && !hasAccessory) {
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                val currentDevice = usbManager.deviceList.isNotEmpty()
                @Suppress("DEPRECATION")
                val currentAccessory = usbManager.accessoryList?.isNotEmpty() == true
                if (!currentDevice && !currentAccessory) {
                    finishAndRemoveTask()
                }
            }, 10000)
        }
    }
}
