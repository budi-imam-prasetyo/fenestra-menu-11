import QtQuick
import QtTest
import org.fenestra.menu11.core

// Compares the native core with the JavaScript fallbacks the widget uses when
// the module is not installed. Both paths run in the same process, on the same
// data, through the same QML/JS engine.
//
// Run with:
//   QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
//       -import build/native/qml -input tests/qml/bench_core.qml
//
// The native path includes the JSON stringify/parse that `Core.qml` performs
// at the boundary, because that is what the widget actually pays. These are
// microbenchmarks: they do not measure widget startup, plasmashell CPU or
// memory, which need a real Plasma session (see docs/native-core.md).
TestCase {
    name: "FenestraCoreBench"

    property var commands: []
    property var commandsJson: ""
    property var rows: []
    property var rowsJson: ""
    readonly property int commandCount: 200
    readonly property int rowCount: 60

    function initTestCase() {
        for (var i = 0; i < commandCount; i++) {
            commands.push({
                name: ["settings", "files", "terminal", "calculator", "browser",
                       "editor", "monitor", "screenshot", "printer", "network"][i % 10] + " " + i,
                desc: "Open a system utility number " + i
            })
        }
        for (var r = 0; r < rowCount; r++) rows.push({ i: r, url: "file:///doc" + r, t: 1700000000 - r * 3600 })
        commandsJson = JSON.stringify(commands)
        rowsJson = JSON.stringify(rows)
    }

    // ── JavaScript fallbacks (kept identical to the widget's QML) ──────────

    function jsFuzzy(commandList, query) {
        function fuzzyMatch(str, needle) {
            var qi = 0
            for (var ci = 0; ci < str.length && qi < needle.length; ci++) {
                if (str[ci] === needle[qi]) qi++
            }
            return qi === needle.length
        }
        var matches = commandList.filter(function(c) {
            var searchStr = c.name + " " + c.desc.toLowerCase()
            return c.name.startsWith(query) || fuzzyMatch(searchStr, query)
        })
        matches.sort(function(a, b) {
            var aPrefix = a.name.startsWith(query) ? 0 : 1
            var bPrefix = b.name.startsWith(query) ? 0 : 1
            return aPrefix - bPrefix
        })
        return matches
    }

    // Same work as the QML fallback in rebuildDocModels(): stable sort, the
    // six-row page and the seven-day window.
    function jsDocs(list) {
        var now = 1700003600
        var sorted = list.slice().sort(function(a, b) { return (b.t - a.t) || (a.i - b.i) })
        var top = 0, week = 0
        for (var k = 0; k < sorted.length; k++) {
            if (k < 6) top++
            if (sorted[k].t > 0 && now - sorted[k].t < 7 * 86400) week++
        }
        return top + week
    }

    // ── Benchmarks ─────────────────────────────────────────────────────────

    function benchmark_js_command_palette() {
        return jsFuzzy(commands, "set").length
    }

    function benchmark_rust_command_palette() {
        return JSON.parse(FenestraCore.fuzzy_rank(commandsJson, "set")).length
    }

    function benchmark_js_document_ordering() {
        return jsDocs(rows).length
    }

    function benchmark_rust_document_ordering() {
        return JSON.parse(FenestraCore.docs_rank(rowsJson, 1700003600)).top.length
    }
}
