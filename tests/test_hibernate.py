#!/usr/bin/env python3
"""Regression tests for the Fenestra Menu 11 hibernate integration.

The applet has no QML runtime in CI, so these tests check the QML wiring,
configuration schema, translations and the pure login1 reply parser.
"""

from __future__ import annotations

import gettext
import json
import re
import shutil
import subprocess
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCALE = ROOT / "contents" / "locale"
LANGUAGES = ("de", "es", "fr", "it", "ja", "nl", "pl", "pt", "ru", "tr", "zh")


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def qml_block(text: str, marker: str, opening: str) -> str:
    """Return the brace-balanced block containing marker."""
    marker_pos = text.index(marker)
    start = text.rfind(opening, 0, marker_pos)
    if start < 0:
        raise AssertionError(f"no {opening!r} before {marker!r}")

    depth = 0
    for pos in range(start, len(text)):
        char = text[pos]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[start : pos + 1]
    raise AssertionError(f"unbalanced QML block for {marker!r}")


class HibernateUiTests(unittest.TestCase):
    def setUp(self) -> None:
        self.footer = read("contents/ui/Footer.qml")

    def test_hibernate_item_is_in_the_power_menu(self) -> None:
        block = qml_block(self.footer, 'text: i18n("Hibernate")', "PlasmaComponents3.ItemDelegate {")
        self.assertIn("visible: hibernateAvailable && Plasmoid.configuration.showHibernateButton", block)
        self.assertIn('icon.source: Qt.resolvedUrl("../icons/status/system-hibernate-v2.svg")', block)
        self.assertIn('text: i18n("Hibernate")', block)
        self.assertIn("onClicked: requestHibernate()", block)
        self.assertNotIn("sessionManager.suspend()", block)

    def test_hibernate_item_is_between_sleep_and_shutdown(self) -> None:
        sleep = self.footer.index('text: i18n("Sleep")')
        hibernate = self.footer.index('text: i18n("Hibernate")')
        shutdown = self.footer.index('text: i18n("Shut down")')
        self.assertLess(sleep, hibernate)
        self.assertLess(hibernate, shutdown)

    def test_power_button_stays_visible_on_hibernate_only_systems(self) -> None:
        block = qml_block(self.footer, 'text: i18n("Power")', "PlasmaComponents3.ToolButton {")
        visible_line = next(line for line in block.splitlines() if "visible: sessionManager" in line)
        self.assertIn("hibernateAvailable && Plasmoid.configuration.showHibernateButton", visible_line)
        for capability in (
            "sessionManager.canLock",
            "sessionManager.canSuspend",
            "hibernateAvailable",
            "sessionManager.canReboot",
            "sessionManager.canShutdown",
        ):
            self.assertIn(capability, visible_line)

    def test_hibernate_refreshes_detection_when_menu_opens(self) -> None:
        block = qml_block(self.footer, 'text: i18n("Power")', "PlasmaComponents3.ToolButton {")
        self.assertIn("hibernateProbe.refresh()", block)
        self.assertLess(block.index("hibernateProbe.refresh()"), block.index("powerMenu.visible = true"))

    def test_kde_action_is_used_before_logind_fallback(self) -> None:
        function = qml_block(self.footer, "sessionManager.hibernate()", "function requestHibernate()")
        self.assertIn("sessionManager.canHibernate", function)
        self.assertIn("sessionManager.hibernate()", function)
        self.assertIn("hibernateProbe.requestHibernate()", function)
        self.assertLess(function.index("sessionManager.hibernate()"), function.index("hibernateProbe.requestHibernate()"))
        self.assertIn("try {", function)
        self.assertIn("catch (e)", function)

    def test_existing_power_actions_are_untouched(self) -> None:
        for call in (
            "sessionManager.lock()",
            "sessionManager.suspend()",
            "sessionManager.requestShutdown()",
            "sessionManager.requestReboot()",
            "sessionManager.requestLogout()",
        ):
            self.assertIn(call, self.footer)

    def test_probe_is_instantiated_with_the_session_manager(self) -> None:
        self.assertIn("HibernateProbe {", self.footer)
        self.assertIn("powerSession: sessionManager", self.footer)
        self.assertIn("readonly property bool hibernateAvailable: hibernateProbe.hibernateAvailable", self.footer)


class HibernateProbeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.probe = read("contents/ui/HibernateProbe.qml")

    def test_uses_login1_can_hibernate(self) -> None:
        self.assertIn("org.freedesktop.login1", self.probe)
        self.assertIn("CanHibernate", self.probe)
        self.assertIn("PowerLogic.parseCanHibernate", self.probe)
        self.assertIn("PowerLogic.isHibernateAvailable", self.probe)

    def test_fallback_uses_login1_hibernate(self) -> None:
        self.assertIn("Hibernate b true", self.probe)
        self.assertIn("--system", self.probe)

    def test_commands_are_fixed_and_do_not_bypass_policy(self) -> None:
        self.assertIn("busctl", self.probe)
        for forbidden in ("systemctl", "sudo", "pkexec", "ignore-inhibit", "--force"):
            self.assertNotIn(forbidden, self.probe)

    def test_probe_failure_falls_back_to_kde(self) -> None:
        self.assertIn("known ? available : sessionAvailable", self.probe)
        self.assertIn("root.known = false", self.probe)
        self.assertIn("probeTimeout", self.probe)

    def test_action_fallback_uses_the_same_availability_rule(self) -> None:
        function = qml_block(self.probe, "if (!hibernateAvailable)", "function requestHibernate()")
        self.assertIn("if (!hibernateAvailable)", function)
        self.assertIn("bus.connectSource(actionCommand", function)


class ConfigurationTests(unittest.TestCase):
    def test_config_schema_has_hibernate_option(self) -> None:
        tree = ET.parse(ROOT / "contents/config/main.xml")
        entries = {element.attrib.get("name"): element for element in tree.iter() if element.tag.endswith("entry")}
        self.assertIn("showHibernateButton", entries)
        entry = entries["showHibernateButton"]
        self.assertEqual(entry.attrib.get("type"), "Bool")
        default = next(child for child in entry if child.tag.endswith("default"))
        self.assertEqual(default.text.strip(), "true")

    def test_config_page_exposes_hibernate_option(self) -> None:
        config = read("contents/ui/ConfigGeneral.qml")
        self.assertIn("property alias cfg_showHibernateButton: showHibernateCb.checked", config)
        block = qml_block(config, 'id: showHibernateCb', "CheckBox {")
        self.assertIn('text: i18n("Hibernate")', block)


class TranslationTests(unittest.TestCase):
    def test_template_contains_hibernate(self) -> None:
        self.assertIn('msgid "Hibernate"', read("translate/template.pot"))

    def test_all_translations_define_hibernate(self) -> None:
        for language in LANGUAGES:
            po = read(f"translate/{language}.po")
            match = re.search(r'msgid "Hibernate"\nmsgstr "([^"]*)"', po)
            self.assertIsNotNone(match, language)
            self.assertTrue(match.group(1).strip(), language)

    def test_compiled_catalogs_contain_hibernate(self) -> None:
        for language in LANGUAGES:
            mo = LOCALE / language / "LC_MESSAGES" / "plasma_applet_org.fenestra.menu11.mo"
            self.assertTrue(mo.is_file(), mo)
            with mo.open("rb") as handle:
                catalog = gettext.GNUTranslations(handle)
            self.assertNotEqual(catalog.gettext("Hibernate"), "Hibernate", language)


class Login1ParserTests(unittest.TestCase):
    def test_parser_and_capability_matrix(self) -> None:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")

        source = read("contents/ui/code/power.js")
        source = re.sub(r"^\s*\.pragma library\s*$", "", source, flags=re.MULTILINE)
        cases = [
            ('s "yes"', True, "yes", True),
            ('s "challenge"', True, "challenge", True),
            ('s "inhibited"', True, "inhibited", True),
            ('s "inhibitor-blocked"', True, "inhibitor-blocked", True),
            ('s "inhibited-blocked"', True, "inhibited-blocked", True),
            ('s "challenge-inhibitor-blocked"', True, "challenge-inhibitor-blocked", True),
            ('s "no"', True, "no", False),
            ('s "na"', True, "na", False),
            ('s "maybe"', False, "maybe", False),
            ("yes", True, "yes", True),
            ("maybe", False, "maybe", False),
            ("", False, "", False),
        ]
        script = source + """
const cases = %s;
const results = cases.map(([raw]) => {
    const parsed = parseCanHibernate(raw);
    return [parsed.known, parsed.status, isHibernateAvailable(parsed.status)];
});
console.log(JSON.stringify(results));
""" % json.dumps([[case[0]] for case in cases])
        output = subprocess.check_output([node, "-e", script], text=True)
        results = json.loads(output)
        expected = [list(case[1:]) for case in cases]
        self.assertEqual(results, expected)


class PackagingTests(unittest.TestCase):
    def test_version_is_semver_and_was_bumped(self) -> None:
        metadata = json.loads(read("metadata.json"))
        version = metadata["KPlugin"]["Version"]
        self.assertRegex(version, r"^\d+\.\d+\.\d+$")
        self.assertGreater(tuple(int(part) for part in version.split(".")), (1, 1, 0))

    def test_hibernate_icon_is_valid_svg(self) -> None:
        icon = ROOT / "contents/icons/status/system-hibernate-v2.svg"
        text = icon.read_text(encoding="utf-8")
        root = ET.fromstring(text)
        self.assertTrue(root.tag.endswith("svg"))
        self.assertIn("currentColor", text)
        self.assertIn("viewBox", root.attrib)

    def test_readme_documents_hibernate(self) -> None:
        self.assertIn("hibernate", read("README.md").lower())


if __name__ == "__main__":
    unittest.main(verbosity=2)
