package com.example.run_walk_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine


class MainActivity: FlutterActivity() {
    private lateinit var wearHealthChannel: WearHealthChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        wearHealthChannel = WearHealthChannel(application)
        wearHealthChannel.onAttachedToEngine(flutterEngine.plugins.getPluginBinding())
    }
}
