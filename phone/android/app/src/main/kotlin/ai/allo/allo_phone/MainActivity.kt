package ai.allo.allo_phone

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ExploreBridge.attach(flutterEngine, this)
        EggInputBridge.attach(flutterEngine, this)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        EggInputBridge.detach()
        ExploreBridge.detach()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
