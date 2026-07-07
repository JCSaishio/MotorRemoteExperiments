"""TCP / newline-delimited-JSON client that talks to the FrED listener.

Sends one 'job' message and streams back 'progress' / 'result' messages until
'done' (or 'error'). Designed to be run on a background thread; it reports
progress and results through callbacks so the GUI stays responsive.
"""

import json
import socket


DEFAULT_HOST = "192.168.4.1"   # Pi's fixed address when the hotspot is up
DEFAULT_PORT = 5001


def run_job(host, port, run_time, wait_time, reference, experiments,
            sample_rate=50.0, on_progress=None, on_result=None, timeout=None):
    """
    Connect, send the job, and pump incoming messages through callbacks.

    sample_rate            -> control-loop / sampling frequency in Hz
    on_progress(msg_dict)  -> called for each 'progress' message
    on_result(msg_dict)    -> called for each 'result' message
    Returns the list of result dicts (in the order received).
    Raises RuntimeError if the Pi reports an error, ConnectionError on
    network problems.
    """
    job = {
        "type": "job",
        "run_time": run_time,
        "wait_time": wait_time,
        "reference": reference,
        "sample_rate": sample_rate,
        "experiments": experiments,
    }

    results = []
    with socket.create_connection((host, port), timeout=timeout) as sock:
        # Keep the socket blocking with no timeout during the (long) run so a
        # slow experiment does not trip a read timeout.
        sock.settimeout(None)
        sock.sendall((json.dumps(job) + "\n").encode("utf-8"))

        reader = sock.makefile("r", encoding="utf-8")
        for line in reader:
            line = line.strip()
            if not line:
                continue
            msg = json.loads(line)
            mtype = msg.get("type")
            if mtype == "progress":
                if on_progress:
                    on_progress(msg)
            elif mtype == "result":
                results.append(msg)
                if on_result:
                    on_result(msg)
            elif mtype == "done":
                break
            elif mtype == "error":
                raise RuntimeError(msg.get("message", "unknown error from FrED"))
    return results
