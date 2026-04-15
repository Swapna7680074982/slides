package com.example.slides

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

class UsbWatcherService : Service() {
    private val monitorHandler = Handler(Looper.getMainLooper())
    private var lastUsbState: Boolean? = null
    private val monitorRunnable =
        object : Runnable {
            override fun run() {
                handleUsbStateChange()
                monitorHandler.postDelayed(this, MONITOR_INTERVAL_MS)
            }
        }

    private val usbReceiver =
        object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val action = intent.action
                val isAttach =
                    action == UsbManager.ACTION_USB_DEVICE_ATTACHED ||
                        action == UsbManager.ACTION_USB_ACCESSORY_ATTACHED
                val isDetach =
                    action == UsbManager.ACTION_USB_DEVICE_DETACHED ||
                        action == UsbManager.ACTION_USB_ACCESSORY_DETACHED
                when {
                    isAttach -> handleUsbStateChange(sourceIntent = intent)
                    isDetach -> handleUsbStateChange(forceClose = true)
                }
            }
        }

    override fun onCreate() {
        super.onCreate()
        startForeground(NOTIFICATION_ID, buildNotification(false))
        registerUsbReceiver()
        handleUsbStateChange()
        monitorHandler.post(monitorRunnable)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.getBooleanExtra(EXTRA_REFRESH_FROM_ACTIVITY, false) == true) {
            // User returned to the app (e.g. after changing settings); try opening again if USB is present.
            val source = Intent(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            retryBringSlidesIfUsbConnected(source)
        } else {
            handleUsbStateChange()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        runCatching { unregisterReceiver(usbReceiver) }
        monitorHandler.removeCallbacks(monitorRunnable)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun registerUsbReceiver() {
        val filter =
            IntentFilter().apply {
                addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
                addAction(UsbManager.ACTION_USB_ACCESSORY_ATTACHED)
                addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
                addAction(UsbManager.ACTION_USB_ACCESSORY_DETACHED)
            }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(usbReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(usbReceiver, filter)
        }
    }

    private fun handleUsbStateChange(
        forceClose: Boolean = false,
        sourceIntent: Intent = Intent(UsbManager.ACTION_USB_DEVICE_ATTACHED),
    ) {
        val usbManager = getSystemService(USB_SERVICE) as? UsbManager ?: return
        val hasDevice = usbManager.deviceList.isNotEmpty()
        val hasAccessory =
            @Suppress("DEPRECATION")
            (usbManager.accessoryList?.isNotEmpty() == true)
        val isConnected = hasDevice || hasAccessory
        val previousState = lastUsbState
        lastUsbState = isConnected

        if (previousState != isConnected) {
            val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            if (!isConnected) {
                manager.notify(NOTIFICATION_ID, buildNotification(false))
            }
        }

        if (forceClose || (!isConnected && previousState != false)) {
            closeSlides()
            return
        }

        // Open only on transition to connected (null/false -> true), not on every attach broadcast
        // or while USB stays plugged in.
        if (isConnected && previousState != true) {
            triggerAggressiveLaunch(sourceIntent)
        }
    }

    private fun triggerAggressiveLaunch(sourceIntent: Intent) {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val alarmId = NOTIFICATION_ID + 1
        
        manager.cancel(alarmId)
        manager.notify(alarmId, buildNotification(true, sourceIntent))
        launchSlides(this, sourceIntent)
        // Right after install, startActivity from a service is often blocked until the user has
        // interacted with the app; retries catch USB once the system allows background launches.
        scheduleLaunchRetries(sourceIntent)
    }

    private fun scheduleLaunchRetries(sourceIntent: Intent) {
        val action = sourceIntent.action ?: UsbManager.ACTION_USB_DEVICE_ATTACHED
        val retryIntent = Intent(sourceIntent).apply { this.action = action }
        val run = { retryBringSlidesIfUsbConnected(retryIntent) }
        monitorHandler.postDelayed(run, LAUNCH_RETRY_MS_1)
        monitorHandler.postDelayed(run, LAUNCH_RETRY_MS_2)
        monitorHandler.postDelayed(run, LAUNCH_RETRY_MS_3)
    }

    /** Extra launch attempts when USB is connected (no-op if unplugged). Safe with singleTask activity. */
    private fun retryBringSlidesIfUsbConnected(sourceIntent: Intent) {
        val usbManager = getSystemService(USB_SERVICE) as? UsbManager ?: return
        val hasDevice = usbManager.deviceList.isNotEmpty()
        val hasAccessory =
            @Suppress("DEPRECATION")
            (usbManager.accessoryList?.isNotEmpty() == true)
        if (!hasDevice && !hasAccessory) return
        launchSlides(this, sourceIntent)
    }

    private fun buildNotification(isConnected: Boolean, sourceIntent: Intent? = null): Notification {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val title = if (isConnected) "USB connected" else "Slides USB watcher"
        val text = if (isConnected) "Opening Slides…" else "Monitoring USB…"
        
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = sourceIntent?.action ?: UsbManager.ACTION_USB_DEVICE_ATTACHED
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT,
            )
            if (sourceIntent != null) putExtras(sourceIntent)
        }
        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        } else {
            android.app.PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent =
            android.app.PendingIntent.getActivity(this, PENDING_INTENT_REQUEST_OPEN, launchIntent, pendingIntentFlags)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = if (isConnected) CHANNEL_ID_HIGH else CHANNEL_ID_LOW
            val priority = if (isConnected) NotificationManager.IMPORTANCE_HIGH else NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(channelId, "USB Watcher", priority)
            manager.createNotificationChannel(channel)
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setPriority(if (isConnected) Notification.PRIORITY_HIGH else Notification.PRIORITY_LOW)
        }

        builder.setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)

        // Do not use setFullScreenIntent here: the service already calls launchSlides for USB connect,
        // and a full-screen PendingIntent would start MainActivity a second time.

        return builder.build()
    }

    private fun launchSlides(context: Context, sourceIntent: Intent) {
        val launchIntent =
            Intent(context, MainActivity::class.java).apply {
                action = sourceIntent.action ?: UsbManager.ACTION_USB_DEVICE_ATTACHED
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT,
                )
                putExtras(sourceIntent)
            }

        try {
            val options = android.app.ActivityOptions.makeBasic()
            if (Build.VERSION.SDK_INT >= 34) {
                options.setPendingIntentBackgroundActivityStartMode(
                    android.app.ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED,
                )
            }
            context.startActivity(launchIntent, options.toBundle())
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun closeSlides() {
        val closeIntent = Intent(ACTION_CLOSE_SLIDES).apply {
            setPackage(packageName)
        }
        sendBroadcast(closeIntent)
    }

    companion object {
        private const val CHANNEL_ID_LOW = "slides_usb_watcher_low"
        private const val CHANNEL_ID_HIGH = "slides_usb_watcher_high_v2"
        private const val NOTIFICATION_ID = 1001
        private const val PENDING_INTENT_REQUEST_OPEN = 2002
        private const val MONITOR_INTERVAL_MS = 1000L
        private const val LAUNCH_RETRY_MS_1 = 400L
        private const val LAUNCH_RETRY_MS_2 = 2000L
        private const val LAUNCH_RETRY_MS_3 = 6000L

        const val EXTRA_REFRESH_FROM_ACTIVITY = "com.example.slides.EXTRA_REFRESH_FROM_ACTIVITY"
        const val ACTION_CLOSE_SLIDES = "com.example.slides.ACTION_CLOSE_SLIDES"
    }
}
