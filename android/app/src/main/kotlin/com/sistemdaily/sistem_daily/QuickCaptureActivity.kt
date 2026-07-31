package com.sistemdaily.sistem_daily

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Modal de captura rápida.
 *
 * Es una Activity aparte de [MainActivity] y con su propio entrypoint de Dart
 * (`quickCaptureMain`) por una razón de velocidad: `main()` levanta Supabase,
 * la sesión, las alarmas y los providers, y eso son segundos. Este atajo se
 * abre desde el desplegable para anotar algo en dos segundos, así que arranca
 * un engine mínimo que solo pinta el modal y escribe en una cola local.
 *
 * En Android no existe una "ventana flotante" que no sea una Activity, así que
 * la sensación de modal se consigue con [BackgroundMode.transparent] más un
 * tema translúcido: la app de debajo se sigue viendo y al cerrar se vuelve
 * exactamente a donde se estaba.
 */
class QuickCaptureActivity : FlutterActivity() {

    companion object {
        /** Tipo con el que se abre: "expense", "income", "task" o "note". */
        const val EXTRA_KIND = "quick_capture_kind"

        private const val CHANNEL = "com.sistemdaily/quick_capture"
    }

    override fun getDartEntrypointFunctionName(): String = "quickCaptureMain"

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Sin animación de entrada de Activity: la que se ve es la del propio
        // modal en Flutter, y encadenar las dos se siente lento.
        overridePendingTransition(0, 0)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // El tile abre sin tipo (lo detecta el parser); los botones
                    // del widget y los atajos del icono sí lo traen fijado.
                    "getLaunchKind" -> result.success(intent?.getStringExtra(EXTRA_KIND))
                    else -> result.notImplemented()
                }
            }
    }

    override fun finish() {
        super.finish()
        overridePendingTransition(0, 0)
    }
}
