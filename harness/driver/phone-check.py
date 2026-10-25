"""Offline CLI privacy checks; only synthetic credentials and mocked HTTP."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("phone", Path(__file__).resolve().parents[2] / "scripts/phone.py")
phone = importlib.util.module_from_spec(spec)
spec.loader.exec_module(phone)
FIXTURE = "0123456789abcdef0123456789abcdef"


class PrivacyChecks(unittest.TestCase):
    def setUp(self):
        self.environment = patch.dict(os.environ, {}, clear=True)
        self.environment.start()
        self.addCleanup(self.environment.stop)
        phone.HOST = "phone.example"
        phone.PORT = 8085

    def test_invalid_environment_token_never_reaches_http(self):
        for value in ("short", FIXTURE.upper(), FIXTURE + "\r\nInjected: value"):
            with self.subTest(value_length=len(value)), patch.dict(os.environ, {"PHONE_TOKEN": value}), \
                    patch.object(phone.urllib.request, "urlopen", side_effect=AssertionError("unexpected HTTP")):
                with self.assertRaises(SystemExit) as error:
                    phone.fetch("state", 20)
                self.assertEqual(str(error.exception), "driver token must be exactly 32 lowercase hex characters; refresh the stored token or set a valid PHONE_TOKEN")

    def test_loopback_discovery_does_not_print(self):
        requests = []

        def reply(request, timeout):
            requests.append(request)
            payload = {"ok": True, "private": True, "now": FIXTURE} if len(requests) == 1 else {"ok": True}
            return io.BytesIO(json.dumps(payload).encode())

        output = io.StringIO()
        with patch.object(phone, "ensure_tunnel"), patch.object(phone.urllib.request, "urlopen", side_effect=reply), \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            self.assertEqual(phone.fetch("state", 20), '{"ok": true}')
        self.assertEqual([request.full_url for request in requests],
                         ["http://127.0.0.1:8085/pref?key=spotifyglass.driver.token", "http://phone.example:8085/state"])
        self.assertIsNone(requests[0].get_header("X-phone-token"))
        self.assertEqual(requests[1].get_header("X-phone-token"), FIXTURE)
        self.assertEqual(output.getvalue(), "")

    def test_pref_values_require_explicit_public_metadata(self):
        for metadata in ({"private": True}, {}):
            output = io.StringIO()
            payload = json.dumps({"ok": True, "now": FIXTURE, **metadata})
            with patch.object(phone, "fetch", return_value=payload), contextlib.redirect_stdout(output):
                self.assertEqual(phone.run(["pref", "--key", "spotifyglass.driver.token"]), 0)
            self.assertEqual(json.loads(output.getvalue())["now"], "[redacted]")
        output = io.StringIO()
        with patch.object(phone, "fetch", return_value='{"ok":true,"private":false,"now":7}'), contextlib.redirect_stdout(output):
            self.assertEqual(phone.run(["pref", "--key", "spotifyglass.font"]), 0)
        self.assertEqual(json.loads(output.getvalue())["now"], 7)

    def test_header_and_network_errors_do_not_echo_credentials(self):
        for failure in (ValueError(FIXTURE), OSError(FIXTURE), phone.http.client.InvalidURL(FIXTURE)):
            with patch.dict(os.environ, {"PHONE_TOKEN": FIXTURE}), \
                    patch.object(phone.urllib.request, "urlopen", side_effect=failure):
                with self.assertRaises(SystemExit) as error:
                    phone.fetch("state", 20)
                self.assertEqual(str(error.exception), "the app did not answer; check USB/Tailscale and keep a FLEX build open in the foreground")

    def test_http_error_body_is_not_printed(self):
        failure = phone.urllib.error.HTTPError("http://phone.example", 403, FIXTURE, {}, io.BytesIO(FIXTURE.encode()))
        with patch.dict(os.environ, {"PHONE_TOKEN": FIXTURE}), patch.object(phone.urllib.request, "urlopen", side_effect=failure):
            with self.assertRaises(SystemExit) as error:
                phone.fetch("state", 20)
        self.assertEqual(str(error.exception), "the driver rejected the HTTP request; check the connection and credential")

    def test_malformed_response_is_not_echoed(self):
        with patch.object(phone, "fetch", return_value="invalid " + FIXTURE):
            with self.assertRaises(SystemExit) as error:
                phone.run(["pref", "--key", "spotifyglass.driver.token"])
        self.assertEqual(str(error.exception), "not a driver answer: use a FLEX build with the phone driver")


if __name__ == "__main__":
    unittest.main()
