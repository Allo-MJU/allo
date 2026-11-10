package ai.allo.allo_phone

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import ai.allo.allo_phone.mirror.ScreenShareBridge

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ExploreBridge.attach(flutterEngine, this)
        ScreenShareBridge.attach(flutterEngine, this)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        ExploreBridge.detach()
        ScreenShareBridge.detach()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
