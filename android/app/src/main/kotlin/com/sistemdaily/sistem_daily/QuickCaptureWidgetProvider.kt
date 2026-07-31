package com.sistemdaily.sistem_daily

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Widget de escritorio con cuatro accesos al modal de captura rápida.
 *
 * No tiene estado ni datos que refrescar: su único trabajo es colgar un
 * PendingIntent de cada botón. Por eso `updatePeriodMillis` es 0 en
 * `widget_quick_capture_info.xml` y [onUpdate] solo se ejecuta al añadirlo,
 * redimensionarlo o reiniciar el launcher.
 */
class QuickCaptureWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, buildViews(context))
        }
    }

    private fun buildViews(context: Context): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_quick_capture)

        // El primer botón abre sin tipo: lo decide el parser por lo escrito.
        views.setOnClickPendingIntent(R.id.capture_free, captureIntent(context, null))
        views.setOnClickPendingIntent(R.id.capture_expense, captureIntent(context, "expense"))
        views.setOnClickPendingIntent(R.id.capture_task, captureIntent(context, "task"))
        views.setOnClickPendingIntent(R.id.capture_note, captureIntent(context, "note"))

        return views
    }

    private fun captureIntent(context: Context, kind: String?): PendingIntent {
        val intent = Intent(context, QuickCaptureActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra(QuickCaptureActivity.EXTRA_KIND, kind)

        // Los extras NO entran en la identidad de un PendingIntent, así que sin
        // un requestCode distinto por botón los cuatro compartirían el mismo
        // objeto y todos abrirían con el tipo del último registrado.
        val requestCode = when (kind) {
            "expense" -> 1
            "task" -> 2
            "note" -> 3
            else -> 0
        }

        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }
}
