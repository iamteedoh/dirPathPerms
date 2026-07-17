#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
#
## Author: Tito Valentin
## Name of Program: dirPathPerms interactive test
## Date Created: 2026-07-16
## Description: Drives dirPathPerms.sh through a real pseudo-terminal to cover
##              the two behaviors that only exist interactively: entering a path
##              to check at the prompt, and recalling earlier entries with the
##              arrow keys. Both need a tty, so they cannot be tested by piping.

import os
import pty
import select
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, "dirPathPerms.sh")

PROMPT = "Path or list file:"
WHO_PROMPT = "(O)wner"
PERM_PROMPT = "(R)ead"


class Session:
    """A dirPathPerms.sh process attached to a pty."""

    def __init__(self, *args):
        self.buf = ""
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.execvp(SCRIPT, [SCRIPT, "--no-color", *args])

    def expect(self, marker, timeout=15):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if marker in self.buf:
                return
            if select.select([self.fd], [], [], 0.2)[0]:
                try:
                    chunk = os.read(self.fd, 8192)
                except OSError:
                    break
                if not chunk:
                    break
                self.buf += chunk.decode(errors="replace").replace("\r", "")
        raise AssertionError(
            "timed out waiting for %r\n--- output so far ---\n%s" % (marker, self.buf)
        )

    def send(self, data):
        os.write(self.fd, data)

    def drain(self, timeout=2.5):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if select.select([self.fd], [], [], 0.2)[0]:
                try:
                    chunk = os.read(self.fd, 8192)
                except OSError:
                    break
                if not chunk:
                    break
                self.buf += chunk.decode(errors="replace").replace("\r", "")
        return self.buf

    def close(self):
        try:
            os.close(self.fd)
        except OSError:
            pass
        try:
            os.waitpid(self.pid, 0)
        except OSError:
            pass


results = []


def check(name, condition, detail=""):
    results.append((name, condition, detail))
    if condition:
        print("  PASS  %s" % name)
    else:
        print("  FAIL  %s" % name)
        if detail:
            print("        " + detail.replace("\n", "\n        "))


def test_path_at_prompt():
    """A path typed at the prompt is checked directly, tilde and all."""
    d = tempfile.mkdtemp(prefix=".dirpathperms_it_", dir=os.path.expanduser("~"))
    rel = os.path.basename(d)
    s = Session()
    try:
        s.expect(PROMPT)
        s.send(("~/%s\n" % rel).encode())
        s.expect(WHO_PROMPT)
        s.send(b"u\n")
        s.expect(PERM_PROMPT)
        s.send(b"r\n")
        s.expect("Summary:")
        out = s.drain()
        check("a ~ path typed at the prompt is checked directly", d in out,
              "expected the resolved path %r in the output" % d)
        check("that path reports a result rather than an error",
              "1 granted" in out and "file not found" not in out,
              "output:\n%s" % out)
    finally:
        s.close()
        os.rmdir(d)


def test_arrow_key_history():
    """Up-arrow recalls what was typed earlier in the session."""
    s = Session()
    try:
        s.expect(PROMPT)
        s.send(b"/nope/typo/path\n")
        s.expect("No such path")
        before = s.buf.count("No such path")
        # Up-arrow, then Enter: readline should resubmit the recalled line.
        s.send(b"\x1b[A\n")
        time.sleep(0.6)
        s.drain(timeout=1.5)
        after = s.buf.count("No such path")
        check("up-arrow recalls the previous entry", after > before,
              "saw %d 'No such path' errors, expected more than %d\n%s"
              % (after, before, s.buf))
        check("the recalled text is the original entry",
              s.buf.count("/nope/typo/path") >= 2,
              "output:\n%s" % s.buf)
    finally:
        s.send(b"\x03")
        s.close()


def main():
    print("\ndirPathPerms interactive (pty) tests\n")
    test_path_at_prompt()
    test_arrow_key_history()
    failed = [n for n, ok, _ in results if not ok]
    print("\nSummary: %d passed, %d failed\n" % (len(results) - len(failed), len(failed)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
