package com.example.slides

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.hardware.usb.UsbManager
import android.os.Build

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val shouldStart =
            action == Intent.ACTION_BOOT_COMPLETED ||
                action == Intent.ACTION_LOCKED_BOOT_COMPLETED ||
                action == Intent.ACTION_MY_PACKAGE_REPLACED ||
                action == Intent.ACTION_POWER_CONNECTED ||
                action == Intent.ACTION_POWER_DISCONNECTED ||
                action == Intent.ACTION_USER_UNLOCKED
        if (!shouldStart) return

        val serviceIntent = Intent(context, UsbWatcherService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }

        val pendingResult = goAsync()
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        handler.postDelayed({
            if (isUsbConnected(context)) {
                val launchIntent = Intent(context, MainActivity::class.java).apply {
                    setAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    putExtra("is_boot_launch", true)
                }
                try {
                    val options = android.app.ActivityOptions.makeBasic()
                    if (Build.VERSION.SDK_INT >= 34) {
                        options.setPendingIntentBackgroundActivityStartMode(android.app.ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED)
                    }
                    context.startActivity(launchIntent, options.toBundle())
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
            pendingResult.finish()
        }, 2500)
    }

    private fun isUsbConnected(context: Context): Boolean {
        val usbManager = context.getSystemService(Context.USB_SERVICE) as? UsbManager ?: return false
        val hasDevice = usbManager.deviceList.isNotEmpty()
        val hasAccessory =
            @Suppress("DEPRECATION")
            (usbManager.accessoryList?.isNotEmpty() == true)
        return hasDevice || hasAccessory
    }
}
