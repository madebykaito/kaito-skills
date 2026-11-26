"""Send one fixture answer after the child prints its terminal prompt."""
import errno
import os
import pty
import select
import signal
import sys
import time

prompt, *command = sys.argv[1:]
marker = prompt.encode()
answer = sys.stdin.buffer.readline()
pid, terminal = pty.fork()
if pid == 0:
    os.execvp(command[0], command)

deadline = time.monotonic() + 45
tail = b""
answered = False
try:
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([terminal], [], [], remaining)[0]:
            os.kill(pid, signal.SIGKILL)
            print("fixture terminal timed out", file=sys.stderr)
            break
        try:
            output = os.read(terminal, 4096)
        except OSError as error:
            if error.errno != errno.EIO:
                raise
            break
        if not output:
            break
        sys.stdout.buffer.write(output)
        sys.stdout.buffer.flush()
        if not answered:
            tail += output
            if marker in tail:
                os.write(terminal, answer)
                answered = True
            tail = tail[-len(marker):]
finally:
    os.close(terminal)
    _, status = os.waitpid(pid, 0)
sys.exit(os.waitstatus_to_exitcode(status) if answered else 1)
