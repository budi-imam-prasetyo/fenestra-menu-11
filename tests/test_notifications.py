"""Exercise the shipped notification reader against a D-Bus response double."""
import contextlib
import io
import json
from pathlib import Path
import re
import types
import unittest
from unittest.mock import patch


class NotificationTests(unittest.TestCase):
    def test_reader_keeps_all_notifications_including_persistent(self):
        source = (Path(__file__).resolve().parents[1] / 'contents/ui/KdeConnectPanel.qml').read_text()
        literal = re.search(r'readonly property string lecteurNotifs: ("(?:\\.|[^"\\])*")', source).group(1)
        script = json.loads(literal)

        def run(command, **kwargs):
            if 'activeNotifications' in command:
                data = [[str(i) for i in range(8)]]
            else:
                data = [{key: {'data': value} for key, value in {
                    'dismissable': not command[5].endswith('/7'),
                    'appName': 'Example', 'title': 'Message', 'text': 'Body',
                    'replyId': '', 'hasIcon': False,
                }.items()}]
            return types.SimpleNamespace(returncode=0, stdout=json.dumps({'data': data}))

        output = io.StringIO()
        with patch('subprocess.run', side_effect=run), patch('sys.argv', ['reader', 'fixture']), contextlib.redirect_stdout(output):
            exec(script, {})
        notifications = json.loads(output.getvalue())
        self.assertEqual(len(notifications), 8)
        self.assertEqual(notifications[0]['id'], '7')
        self.assertFalse(notifications[0]['dismissable'])
