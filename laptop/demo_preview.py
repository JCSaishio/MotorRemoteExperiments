"""Offline preview: build a sample results workbook from synthetic motor data,
so you can see the Excel layout WITHOUT the Pi or motor.

    python demo_preview.py            # uses ../Example.xlsx, writes a *_DEMO file
"""

import os
import sys
import math

import excel_parser
import results_writer


def fake_run(reference, run_time, dt=0.02, tau=2.0):
    n = int(run_time / dt)
    d = {k: [] for k in ["time", "rpm", "rpm_ref", "motor_input",
                         "pwm", "voltage", "rpm_raw"]}
    for i in range(n):
        t = round(i * dt, 4)
        y = reference * (1 - math.exp(-t / tau))
        pwm = max(min(30 + 0.2 * (reference - y), 100), 0)
        d["time"].append(t)
        d["rpm"].append(round(y, 2))
        d["rpm_ref"].append(reference)
        d["motor_input"].append(round(0.3 * (reference - y), 2))
        d["pwm"].append(round(pwm, 2))
        d["voltage"].append(round(12 * pwm / 100, 2))
        d["rpm_raw"].append(round(y + 0.6, 2))
    return d


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join("..", "Example.xlsx")
    reference, run_time = 45.0, 30.0
    exps = excel_parser.parse_experiments(src)
    results = []
    for e in exps:
        results.append(dict(index=e["index"], metric=e["metric"], algorithm=e["algorithm"],
                            kp=e["kp"], ki=e["ki"], kd=e["kd"], reference=reference,
                            run_time=run_time, wait_time=5.0,
                            data=fake_run(reference, run_time)))
    base = os.path.splitext(os.path.basename(src))[0]
    out = os.path.join(os.path.dirname(os.path.abspath(src)), f"{base}_ExperimentalResults_DEMO.xlsx")
    results_writer.build_results_workbook(results, out)
    print("Demo workbook written to:", out)


if __name__ == "__main__":
    main()
