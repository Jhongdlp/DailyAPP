package com.sistemdaily.sistem_daily

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * Botón de captura rápida en el desplegable de ajustes rápidos.
 *
 * Abre [QuickCaptureActivity] sin tipo fijado: desde el tile se escribe en
 * lenguaje natural y el parser decide si es gasto, tarea o nota. Los botones
 * con tipo concreto están en el widget de escritorio y en los atajos del icono.
 */
class QuickCaptureTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        // El tile es una acción, no un interruptor: no tiene estado encendido.
        // INACTIVE lo pinta apagado en vez de atenuado como UNAVAILABLE.
        qsTile?.apply {
            state = Tile.STATE_INACTIVE
            updateTile()
        }
    }

    override fun onClick() {
        super.onClick()

        // Con el móvil bloqueado el panel no puede lanzar la Activity: hay que
        // pedir el desbloqueo primero o el toque no haría nada.
        if (isLocked) {
            unlockAndRun { launchCapture() }
        } else {
            launchCapture()
        }
    }

    private fun launchCapture() {
        val intent = Intent(this, QuickCaptureActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(
                PendingIntent.getActivity(
                    this,
                    0,
                    intent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                ),
            )
        } else {
            @Suppress("DEPRECATION", "StartActivityAndCollapseDeprecated")
            startActivityAndCollapse(intent)
        }
    }
}
