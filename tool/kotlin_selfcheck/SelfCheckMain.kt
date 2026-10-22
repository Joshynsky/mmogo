package app.mmogo.autoread

import java.io.File

/** Entry point for tool/kotlin_selfcheck/run.ps1: runs every self-check and exits non-zero on any failure. */
fun main() {
    var failed = 0

    val dir = File(System.getProperty("java.io.tmpdir"), "heldcheck_" + System.nanoTime())
    val held = HeldStoreSelfCheck.run(dir)
    println("HeldStore: " + (if (held.isEmpty()) "ALL PASS" else "FAILS=" + held.size))
    held.forEach { println("  FAIL: $it") }
    failed += held.size

    val notifier = NotifierSelfCheck.runAll()
    notifier.forEach { println("  FAIL: $it") }
    println("Notifier: " + (if (notifier.isEmpty()) "ALL PASS" else "FAILS=" + notifier.size))
    failed += notifier.size

    val sms = SmsReceiverSelfCheck.runAll()
    sms.forEach { println("  FAIL: $it") }
    println("SmsReceiverLogic: " + (if (sms.isEmpty()) "ALL PASS" else "FAILS=" + sms.size))
    failed += sms.size

    val bridge = BridgeSelfCheck.runAll()
    bridge.forEach { println("  FAIL: $it") }
    println("BridgeLogic: " + (if (bridge.isEmpty()) "ALL PASS" else "FAILS=" + bridge.size))
    failed += bridge.size

    val parse = ParseSelfCheck.runAll()
    parse.forEach { println("  FAIL: $it") }
    println("ParsePolicy (stage 2): " + (if (parse.isEmpty()) "ALL PASS" else "FAILS=" + parse.size))
    failed += parse.size

    if (failed != 0) System.exit(1)
}
