package com.example.slides

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.hardware.usb.UsbManager
import android.os.Build

class UsbAttachReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val isUsbAttach =
            intent.action == UsbManager.ACTION_USB_DEVICE_ATTACHED ||
                intent.action == UsbManager.ACTION_USB_ACCESSORY_ATTACHED
        if (!isUsbAttach) {
            return
        }

        val serviceIntent = Intent(context, UsbWatcherService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
        // MainActivity is opened once by UsbWatcherService when USB transitions to connected.
    }
}
