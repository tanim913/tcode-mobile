package dev.tcode.mobile

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Host activity for the Flutter engine.
 *
 * Registers the Storage Access Framework channel, which is the only native code
 * the app has: everything else reaches the platform through Flutter plugins.
 */
class MainActivity : FlutterActivity() {

    private var saf: SafPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val plugin = SafPlugin(this)
        saf = plugin
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SafPlugin.CHANNEL,
        ).setMethodCallHandler(plugin)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // The plugin reports whether it owned this result; anything else still
        // has to reach the Flutter plugins that registered for it.
        if (saf?.onActivityResult(requestCode, resultCode, data) == true) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
