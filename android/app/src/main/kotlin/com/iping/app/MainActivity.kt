package com.iping.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var sharingChannel: MethodChannel? = null

    /// Người dùng bấm "Dừng chia sẻ" trên thông báo nhưng Dart chưa xử lý (app vừa mở / chưa sẵn sàng).
    private var pendingStop = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createSosChannel()
        // Activity được tạo lại (sau khi hệ thống thu hồi) thì intent cũ không còn là thao tác mới.
        if (savedInstanceState == null) handleStopIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleStopIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sharingChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARING_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takePendingStop" -> {
                        val pending = pendingStop
                        pendingStop = false
                        result.success(pending)
                    }
                    "attachStopAction" -> {
                        val title = call.argument<String>("title") ?: "Dừng chia sẻ"
                        // Dịch vụ nền của geolocator có thể chưa kịp đăng thông báo: thử lại sau một lúc.
                        if (attachStopAction(title)) {
                            result.success(true)
                        } else {
                            Handler(Looper.getMainLooper()).postDelayed({
                                result.success(attachStopAction(title))
                            }, 1500)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        sharingChannel?.setMethodCallHandler(null)
        sharingChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // ---- Nút "Dừng chia sẻ" trên thông báo chia sẻ vị trí ----

    private fun handleStopIntent(intent: Intent?) {
        if (intent == null || intent.action != ACTION_STOP_SHARING) return
        // Mở lại từ danh sách ứng dụng gần đây: không dừng chia sẻ lần nữa.
        if ((intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return
        // Không xử lý lại khi Activity được tạo lại (xoay màn hình, mở lại từ danh sách gần đây).
        intent.action = Intent.ACTION_MAIN
        pendingStop = true
        val channel = sharingChannel ?: return // Dart sẽ hỏi "takePendingStop" khi khởi động.
        channel.invokeMethod("stopSharing", null, object : MethodChannel.Result {
            override fun success(result: Any?) {
                if (result == true) pendingStop = false
            }

            override fun error(code: String, message: String?, details: Any?) {
                Log.w(TAG, "stopSharing: $code $message")
            }

            override fun notImplemented() {}
        })
    }

    /// Tìm thông báo cố định của dịch vụ vị trí (geolocator) và đăng lại kèm nút "Dừng chia sẻ".
    /// Không tìm thấy (dịch vụ chưa chạy / đã dừng) thì trả về false, không lỗi.
    private fun attachStopAction(title: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        return try {
            val manager = getSystemService(NotificationManager::class.java) ?: return false
            val active = manager.activeNotifications.firstOrNull {
                it.packageName == packageName &&
                    (it.id == GEOLOCATOR_NOTIFICATION_ID ||
                        (it.notification.flags and Notification.FLAG_FOREGROUND_SERVICE) != 0)
            } ?: return false
            val existing = active.notification
            if (existing.actions?.any { it.title?.toString() == title } == true) return true
            val stopIntent = Intent(this, MainActivity::class.java).apply {
                action = ACTION_STOP_SHARING
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
            }
            val pending = PendingIntent.getActivity(
                this, STOP_REQUEST_CODE, stopIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val notification = Notification.Builder.recoverBuilder(this, existing)
                .setActions() // bỏ nút cũ (nếu có) trước khi thêm
                .addAction(Notification.Action.Builder(null, title, pending).build())
                .setOngoing(true)
                .build()
            manager.notify(active.tag, active.id, notification)
            true
        } catch (e: Exception) {
            Log.w(TAG, "attachStopAction: $e")
            false
        }
    }

    /// Kênh "sos" phát tiếng còi riêng (res/raw/sos_siren). FCM gửi SOS vào kênh này (channelId "sos").
    /// Kênh tồn tại vĩnh viễn sau lần mở app đầu tiên, nên push vẫn hú còi khi app đã tắt.
    private fun createSosChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(SOS_CHANNEL) != null) return
        val sound = Uri.parse("android.resource://$packageName/raw/sos_siren")
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val channel = NotificationChannel(SOS_CHANNEL, "Cảnh báo SOS", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "SOS và cảnh báo khẩn cấp từ thành viên trong nhóm"
            setSound(sound, attrs)
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 800, 400, 800, 400, 800)
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val SOS_CHANNEL = "sos"
        const val SHARING_CHANNEL = "iping/sharing"
        const val ACTION_STOP_SHARING = "com.iping.app.STOP_SHARING"
        private const val STOP_REQUEST_CODE = 7301
        /// `GeolocatorLocationService.ONGOING_NOTIFICATION_ID` (geolocator_android).
        private const val GEOLOCATOR_NOTIFICATION_ID = 75415
        private const val TAG = "IPing"
    }
}
