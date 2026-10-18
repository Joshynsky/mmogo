package app.mmogo

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * §AUTOREAD.RECEIVER (AutoReadBridge skeleton, AR1). Channel `app.mmogo/autoread`. Every call
 * answers notImplemented: nothing here reads, stores or logs anything yet.
 */
class AutoReadBridge : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "app.mmogo/autoread"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        result.notImplemented()
    }
}
