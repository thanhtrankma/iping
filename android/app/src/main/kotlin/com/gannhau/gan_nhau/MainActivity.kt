package com.gannhau.gan_nhau

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createSosChannel()
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
    }
}
