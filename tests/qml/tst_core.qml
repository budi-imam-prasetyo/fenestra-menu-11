import QtQuick
import QtTest
import org.fenestra.menu11.core

// Exercises the CXX-Qt bridge directly. Run with:
//   qmltestrunner -import build/native/qml -input tests/qml/tst_core.qml
TestCase {
    name: "FenestraCoreBridge"

    function test_version_is_reported() {
        verify(FenestraCore.version().length > 0)
    }

    function test_hibernate_parsing_and_availability() {
        var yes = JSON.parse(FenestraCore.hibernate_parse('s "yes"'))
        compare(yes.known, true)
        compare(yes.status, "yes")
        compare(FenestraCore.hibernate_available(yes.status), true)

        var blocked = JSON.parse(FenestraCore.hibernate_parse('s "inhibited"'))
        compare(blocked.known, true)
        compare(blocked.status, "inhibited")
        compare(FenestraCore.hibernate_available(blocked.status), true)

        var no = JSON.parse(FenestraCore.hibernate_parse('s "no"'))
        compare(no.known, true)
        compare(FenestraCore.hibernate_available(no.status), false)

        var unknown = JSON.parse(FenestraCore.hibernate_parse('s "maybe"'))
        compare(unknown.known, false)
    }

    function test_launch_history_round_trip() {
        var counts = JSON.parse(FenestraCore.launch_parse_counts("{}"))
        compare(Object.keys(counts).length, 0)

        var updated = JSON.parse(FenestraCore.launch_record("{}", "dolphin", 2, 9, 1700000000000))
        compare(updated.dolphin.total, 1)
        compare(updated.dolphin.buckets["2-1"], 1)
        compare(updated.dolphin.last, 1700000000000)

        var migrated = JSON.parse(FenestraCore.launch_record('{"firefox":4}', "firefox", 6, 22, 42))
        compare(migrated.firefox.total, 5)
        compare(migrated.firefox.buckets["6-3"], 1)

        var stored = JSON.stringify({ a: { total: 3, buckets: { "2-1": 2 } } })
        compare(FenestraCore.launch_has_workflow(stored, 2, 9, 6), true)
        compare(FenestraCore.launch_has_workflow(stored, 2, 9, 8), false)
        compare(FenestraCore.launch_top_total(stored), 3)
    }

    function test_new_apps_bookkeeping() {
        var difference = JSON.parse(FenestraCore.new_apps_diff(
            '["a.desktop","b.desktop"]', '["b.desktop","c.desktop"]'))
        compare(difference.changed, true)
        compare(difference.added.length, 1)
        compare(difference.added[0], "c.desktop")
        compare(difference.removed.length, 1)
        compare(difference.removed[0], "a.desktop")

        var stored = '{"keep":{"t":1,"cat":"A","name":"Keep"}}'
        var marked = JSON.parse(FenestraCore.new_apps_mark(
            stored, '[{"id":"x.desktop","name":"X","cat":"C"}]', 99))
        compare(marked.keep.name, "Keep")
        compare(marked["x.desktop"].t, 99)
        compare(marked["x.desktop"].cat, "C")

        var forgotten = JSON.parse(FenestraCore.new_apps_forget(JSON.stringify(marked), "x.desktop"))
        compare(forgotten["x.desktop"], undefined)
        compare(forgotten.keep.name, "Keep")

        var pending = JSON.parse(FenestraCore.new_apps_missing('["a","b","c"]', '["b","c","d"]'))
        compare(JSON.stringify(pending), '["a"]')

        var now = 10000000000
        var week = 7 * 86400000
        var pruned = JSON.parse(FenestraCore.new_apps_prune(
            '{"fresh":{"t":9999999999},"old":{"t":1},"bad":3}', now, week))
        compare(pruned.fresh.t, 9999999999)
        compare(pruned.old, undefined)
        compare(pruned.bad, undefined)
    }

    function test_command_palette_ranking() {
        var commands = [
            { name: "settings", desc: "Open System Settings" },
            { name: "files", desc: "Open file manager" },
            { name: "set", desc: "Set something" },
            { name: "terminal", desc: "Open a terminal" }
        ]
        var ranked = JSON.parse(FenestraCore.fuzzy_rank(JSON.stringify(commands), "set"))
        compare(ranked.length, 2)
        compare(ranked[0].name, "settings")
        compare(ranked[1].name, "set")

        var byDescription = JSON.parse(FenestraCore.fuzzy_rank(JSON.stringify(commands), "manager"))
        compare(byDescription.length, 1)
        compare(byDescription[0].name, "files")

        var empty = JSON.parse(FenestraCore.fuzzy_rank(JSON.stringify(commands), "  "))
        compare(empty.length, commands.length)

        var accented = JSON.parse(FenestraCore.fuzzy_rank(
            '[{"name":"Préférences système","desc":""}]', "pref"))
        compare(accented.length, 1)
    }

    function test_document_ordering() {
        var rows = [
            { i: 0, url: "file:///a", t: 100 },
            { i: 1, url: "file:///b", t: 300 },
            { i: 2, url: "file:///c", t: 300 },
            { i: 3, url: "file:///d", t: 0 }
        ]
        var lists = JSON.parse(FenestraCore.docs_rank(JSON.stringify(rows), 1000))
        compare(JSON.stringify(lists.order), JSON.stringify([1, 2, 0, 3]))
        compare(JSON.stringify(lists.top), JSON.stringify([1, 2, 0, 3]))
        verify(lists.week.indexOf(1) >= 0)
        compare(lists.week.indexOf(3), -1)

        // The page limit and the seven-day window live in the core.
        var now = 1000000
        var many = []
        for (var i = 0; i < 9; i++) many.push({ i: i, t: now - i * 10 })
        many.push({ i: 9, t: now - 7 * 86400 })
        var ranked = JSON.parse(FenestraCore.docs_rank(JSON.stringify(many), now))
        compare(ranked.top.length, 6)
        compare(ranked.week.length, 9)
        compare(ranked.order.length, 10)
    }

    function test_shell_quoting() {
        compare(FenestraCore.shell_quote("hello"), "'hello'")
        compare(FenestraCore.shell_quote("it's"), "'it'\\''s'")
        compare(FenestraCore.shell_quote("$(rm -rf /); echo pwned"),
                "'$(rm -rf /); echo pwned'")
    }

    function test_command_builders_validate_input() {
        compare(FenestraCore.cmd_ring("0123456789abcdef"),
                "kdeconnect-cli -d '0123456789abcdef' --ring")
        compare(FenestraCore.cmd_ring("../etc"), "")
        compare(FenestraCore.cmd_ring("a;b"), "")
        compare(FenestraCore.cmd_dismiss_notification("device-1", "12"),
                "sh -c " + FenestraCore.shell_quote(
                    "Q=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus); " +
                    "\"$Q\" org.kde.kdeconnect '/modules/kdeconnect/devices/device-1/notifications/12' " +
                    "'org.kde.kdeconnect.device.notifications.notification.dismiss'"))
        compare(FenestraCore.cmd_dismiss_notification("device-1", "1; rm -rf /"), "")
    }

    function test_kdeconnect_parsing() {
        var row = ["abc", "Phone", "phone", "true", "80", "true",
                   "kdeconnect_notifications,kdeconnect_photo", "5G", "3",
                   "Song", "Artist", "true", "200000", "5000", "true", "40"].join("\t")
        var devices = JSON.parse(FenestraCore.kdeconnect_parse_devices(row))
        compare(devices.length, 1)
        compare(devices[0].id, "abc")
        compare(devices[0].name, "Phone")
        compare(devices[0].reachable, true)
        compare(devices[0].charge, 80)
        compare(devices[0].plugins.length, 2)
        compare(devices[0].mTitle, "Song")
        compare(devices[0].mVolume, 40)

        var contacts = JSON.parse(FenestraCore.kdeconnect_parse_contacts(
            "Marie\t06 35 93 98 41\tmobile\nPaul\t+33 6 12 34 56 78\t"))
        compare(contacts.length, 2)
        compare(contacts[0].digits, "0635939841")
        compare(contacts[0].key, "marie")

        compare(FenestraCore.kdeconnect_format_number("0635939841"), "06 35 93 98 41")
        compare(FenestraCore.kdeconnect_format_number("+33635939841"), "+336 35 93 98 41")
    }

    function test_vcard_load_tolerates_missing_directory() {
        var contacts = JSON.parse(FenestraCore.kdeconnect_vcard_load("0123456789abcdef"))
        compare(contacts.length, 0)
        var guarded = JSON.parse(FenestraCore.kdeconnect_vcard_load("../etc"))
        compare(guarded.length, 0)
    }
}
