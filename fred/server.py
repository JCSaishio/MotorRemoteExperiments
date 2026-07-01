######### FrED experiment listener ########
#
# Runs ONLY while you want to perform experiments. Start it with
# run_experiments.sh (after ./hotspot_on.sh), stop it with Ctrl+C.
#
# Protocol: newline-delimited JSON over TCP.
#   Laptop -> Pi   : one "job" message (experiments + run_time + wait_time + reference)
#   Pi -> Laptop   : "progress" messages, one "result" per experiment, then "done"
#                    (or an "error" message on failure).

import json
import socket

import experiment_runner as er

HOST = "0.0.0.0"    # listen on all interfaces (reachable at 10.42.0.1 over the hotspot)
PORT = 5001


def send_msg(conn, obj):
    conn.sendall((json.dumps(obj) + "\n").encode("utf-8"))


def handle(conn, addr):
    reader = conn.makefile("r", encoding="utf-8")

    line = reader.readline()
    if not line:
        print("  client disconnected before sending a job")
        return
    job = json.loads(line)
    if job.get("type") != "job":
        send_msg(conn, {"type": "error", "message": "expected a 'job' message"})
        return

    run_time    = float(job["run_time"])
    wait_time   = float(job["wait_time"])
    reference   = float(job["reference"])
    experiments = job["experiments"]
    total       = len(experiments)

    print(f"  job: {total} experiments | run={run_time}s wait={wait_time}s ref={reference} rpm")

    hw = er.MotorHardware()
    try:
        for i, exp in enumerate(experiments, start=1):
            label = f"{exp['metric']}/{exp['algorithm']}"
            msg = (f"[{i}/{total}] {label}  "
                   f"Kp={exp['kp']} Ki={exp['ki']} Kd={exp['kd']}")
            print("  running", msg)
            send_msg(conn, {"type": "progress", "experiment": i, "total": total,
                            "phase": "running", "message": msg})

            data = er.run_experiment(
                hw,
                float(exp["kp"]), float(exp["ki"]), float(exp["kd"]),
                reference, run_time)

            # diagnostics: if the motor never turned, PWM stayed ~0
            pwm = data.get("pwm") or [0]
            rpm = data.get("rpm") or [0]
            print(f"    samples={len(data['time'])}  "
                  f"PWM max={max(pwm):.1f}% min={min(pwm):.1f}%  "
                  f"rpm final={rpm[-1]:.1f} max={max(rpm):.1f}")
            if max(pwm) <= 0:
                print("    WARNING: PWM stayed at 0% - motor was never driven "
                      "(check reference > 0 and encoder/SPI wiring).")

            send_msg(conn, {
                "type": "result",
                "index": exp.get("index", i),
                "metric": exp["metric"],
                "algorithm": exp["algorithm"],
                "kp": exp["kp"], "ki": exp["ki"], "kd": exp["kd"],
                "reference": reference,
                "run_time": run_time,
                "wait_time": wait_time,
                "data": data,
            })

            if i < total:
                hw.motor_off()
                send_msg(conn, {"type": "progress", "experiment": i, "total": total,
                                "phase": "waiting",
                                "message": f"waiting {wait_time}s before next experiment"})
                print(f"  waiting {wait_time}s ...")
                import time
                time.sleep(wait_time)

        send_msg(conn, {"type": "done"})
        print("  job complete.")
    except Exception as e:
        print("  ERROR:", e)
        try:
            send_msg(conn, {"type": "error", "message": str(e)})
        except Exception:
            pass
    finally:
        hw.cleanup()


def main():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((HOST, PORT))
        s.listen(1)
        mode = "REAL HARDWARE" if er.HARDWARE else "SIMULATION (no Pi hardware detected)"
        print("=" * 60)
        print(" FrED experiment listener")
        print(f" Mode      : {mode}")
        print(f" Listening on {HOST}:{PORT}  (reach it at 192.168.4.1:{PORT})")
        print(" Waiting for the laptop app to connect...  (Ctrl+C to stop)")
        print("=" * 60)
        try:
            while True:
                conn, addr = s.accept()
                print(f"Connection from {addr[0]}")
                with conn:
                    try:
                        handle(conn, addr)
                    except Exception as e:
                        print("Connection error:", e)
                print("Ready for next job (Ctrl+C to stop).")
        except KeyboardInterrupt:
            print("\nListener stopped.")


if __name__ == "__main__":
    main()
