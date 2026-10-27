import QtQuick
import QtTest

// Verifies the optional-accelerator fallback: Core.qml must load (and report
// `available === false`) when the native module is not staged next to it.
TestCase {
    name: "FenestraCoreFallback"

    function test_missing_module_does_not_break_core() {
        var component = Qt.createComponent(Qt.resolvedUrl("../../contents/ui/Core.qml"))
        compare(component.status, Component.Ready)
        var core = component.createObject(null)
        verify(core !== null)
        compare(core.available, false)
        compare(core.version(), "")
        compare(core.hibernateParse('s "yes"'), null)
        compare(core.hibernateAvailable("yes"), null)
        compare(core.fuzzyRank([], "x"), null)
        compare(core.launchRecord("{}", "a", 1, 1, 1), null)
        compare(core.cmdRing("device"), "")
        // The quoting primitive is always available, even without Rust.
        compare(core.shellQuote("it's"), "'it'\\''s'")
        core.destroy()
    }
}
