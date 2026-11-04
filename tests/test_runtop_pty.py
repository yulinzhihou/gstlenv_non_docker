"""Drive the read-only monitor in a disposable PTY, without game binaries."""
import errno
import fcntl
import os
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import time

script, game = sys.argv[1:]


def check_exit(action):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    before = termios.tcgetattr(slave)
    proc = subprocess.Popen(
        ["bash", "-c", 'source "$1"; runtop_watch "$2" 0 1', "_", script, game],
        stdin=slave, stdout=slave, stderr=slave,
        start_new_session=True, env={**os.environ, "TERM": "xterm"},
    )
    data = bytearray()
    login = None

    def receive(predicate, timeout=12):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if select.select([master], [], [], 0.2)[0]:
                try:
                    data.extend(os.read(master, 65536))
                except OSError as exc:
                    if exc.errno != errno.EIO:
                        raise
            if predicate(bytes(data)):
                return
            if proc.poll() is not None:
                break
        raise AssertionError(data.decode(errors="replace"))

    try:
        receive(lambda text: text.count(b"PROCESS") >= 2)
        assert b"\x1b[?1049h" in data and b"\x1b[?25l" in data
        assert b"Login" in data and b"STOP" in data and b"MISSING" in data
        if action == "q":
            offset = len(data)
            login = subprocess.Popen(
                [os.path.join(game, "Server", "Login"),
                 "-c", "while :; do :; done"],
                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            pattern = rb"Login +RUN/[RS] +" + str(login.pid).encode() + rb" "
            receive(lambda text: re.search(pattern, text[offset:]) is not None)
            login.terminate()
            login.wait(timeout=4)
            offset = len(data)
            receive(lambda text: re.search(rb"Login +STOP ", text[offset:]) is not None)
            os.write(master, b"q")
        elif action == "interrupt":
            os.killpg(proc.pid, signal.SIGINT)
        else:
            os.killpg(proc.pid, signal.SIGTERM)
        receive(lambda text: b"\x1b[?25h\x1b[?1049l" in text)
        code = proc.wait(timeout=4)
        assert code == {"q": 0, "interrupt": 130, "terminate": 143}[action], code
        assert termios.tcgetattr(slave) == before, "terminal modes not restored"
    finally:
        if login is not None and login.poll() is None:
            login.kill()
            login.wait()
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
        os.close(master)
        os.close(slave)


for mode in ("q", "interrupt", "terminate"):
    check_exit(mode)
print("PASS: 80x24 PTY refresh, live STOP/RUN/STOP transitions, q, signals and terminal restoration")
