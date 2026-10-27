"""Category UI and the QML logic exercised with Kicker-like model doubles."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CategoryTests(unittest.TestCase):
    def test_qml_category_logic(self):
        node = shutil.which("node")
        if not node:
            self.skipTest("Node.js unavailable for QML JavaScript logic test")
        subprocess.run([node, "tests/category_logic.js"], cwd=ROOT, check=True, capture_output=True, text=True)

    def test_removed_document_path_and_kept_search(self):
        menu = (ROOT / "contents/ui/MenuRepresentation.qml").read_text()
        main = (ROOT / "contents/ui/main.qml").read_text()
        self.assertNotIn('text: i18n("Recommended")', menu)
        self.assertNotIn("refreshDocDates", menu)
        self.assertNotIn("docsWeekModel", menu)
        self.assertIn("runnerModel.query = searchField.text", menu)
        self.assertIn("showRecentDocs: false", main)
        self.assertIn("listModel: rootItem.activeCategoryRow < 0 ? allAppsListModel : categoryAppsModel", menu)


if __name__ == "__main__":
    unittest.main()
