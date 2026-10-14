package com.iping.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

/** Widget màn hình chính: tối đa 4 thành viên của nhóm đang chọn. Dữ liệu do app đẩy qua home_widget. */
class MembersWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val summary = widgetData.getString("summary", null)
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, buildViews(context, summary))
        }
    }

    private fun buildViews(context: Context, summary: String?): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.iping_members_widget)
        views.setOnClickPendingIntent(R.id.widget_root, openAppIntent(context))

        val data = try {
            summary?.let { JSONObject(it) }
        } catch (e: Exception) {
            null
        }
        val members = data?.optJSONArray("members")
        if (data == null || members == null || members.length() == 0) {
            views.setViewVisibility(R.id.empty, View.VISIBLE)
            views.setViewVisibility(R.id.members, View.GONE)
            return views
        }

        views.setTextViewText(R.id.group_name, data.optString("group", "IPing"))
        views.setViewVisibility(R.id.empty, View.GONE)
        views.setViewVisibility(R.id.members, View.VISIBLE)
        val now = System.currentTimeMillis()
        for (i in ROWS.indices) {
            val row = ROWS[i]
            val m = members.optJSONObject(i)
            if (m == null) {
                views.setViewVisibility(row[0], View.GONE)
                continue
            }
            views.setViewVisibility(row[0], View.VISIBLE)
            views.setInt(row[1], "setColorFilter", m.optInt("color", BRAND))
            views.setTextViewText(row[2], m.optString("initial", "?"))
            views.setTextViewText(row[3], m.optString("name"))
            val at = m.optLong("at", 0L)
            val status = m.optString("status")
            views.setTextViewText(row[4], if (at > 0) "$status · ${timeAgo(now - at)}" else status)
        }
        return views
    }

    /** Chạm vào widget → mở app. */
    private fun openAppIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
        }
        return PendingIntent.getActivity(
            context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** Giống timeAgo() trong lib/utils/format.dart. */
    private fun timeAgo(ms: Long): String {
        val minutes = ms / 60_000
        return when {
            minutes < 1 -> "vừa xong"
            minutes < 60 -> "$minutes phút trước"
            minutes < 60 * 24 -> "${minutes / 60} giờ trước"
            else -> "${minutes / (60 * 24)} ngày trước"
        }
    }

    companion object {
        private const val BRAND = 0xFF3B5BFD.toInt()

        // Mỗi dòng: [dòng, nền avatar, chữ cái, tên, trạng thái].
        private val ROWS = arrayOf(
            intArrayOf(R.id.row_1, R.id.avatar_1, R.id.initial_1, R.id.name_1, R.id.status_1),
            intArrayOf(R.id.row_2, R.id.avatar_2, R.id.initial_2, R.id.name_2, R.id.status_2),
            intArrayOf(R.id.row_3, R.id.avatar_3, R.id.initial_3, R.id.name_3, R.id.status_3),
            intArrayOf(R.id.row_4, R.id.avatar_4, R.id.initial_4, R.id.name_4, R.id.status_4),
        )
    }
}
