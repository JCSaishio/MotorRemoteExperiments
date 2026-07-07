"""Sampling-rate validator.

Checks whether the FrED control loop actually sampled at the frequency the
user requested, using the timestamps logged during the run. Used by the app
(log warnings) and by results_writer (per-sheet 'Sampling validation' block).

Pass criteria:
  - the average achieved frequency is within TOLERANCE (5%) of the request, and
  - no more than MAX_SLOW_FRACTION of the sample periods were longer than
    1.5x the requested period (occasional OS hiccups are tolerated).
"""

TOLERANCE         = 0.05   # +/-5% on the average achieved frequency
SLOW_DT_FACTOR    = 1.5    # a period longer than 1.5x nominal counts as "slow"
MAX_SLOW_FRACTION = 0.02   # up to 2% slow periods still passes


def analyze(time_data, requested_hz):
    """
    time_data    : list of sample timestamps [s] from one experiment
    requested_hz : sampling frequency the user asked for [Hz]

    Returns a dict:
      requested_hz, actual_hz, deviation_pct, n_samples,
      mean_dt, max_dt, slow_fraction, ok (bool), message (one-line summary)
    """
    requested_hz = float(requested_hz)
    t = [float(x) for x in time_data if x is not None]
    n = len(t)

    if n < 2 or requested_hz <= 0:
        return {
            "requested_hz": requested_hz, "actual_hz": 0.0,
            "deviation_pct": 100.0, "n_samples": n,
            "mean_dt": 0.0, "max_dt": 0.0, "slow_fraction": 0.0,
            "ok": False,
            "message": "Sampling check FAILED: not enough samples to validate.",
        }

    duration  = t[-1] - t[0]
    actual_hz = (n - 1) / duration if duration > 0 else 0.0
    dts       = [t[i + 1] - t[i] for i in range(n - 1)]
    mean_dt   = sum(dts) / len(dts)
    max_dt    = max(dts)

    nominal_dt    = 1.0 / requested_hz
    slow          = sum(1 for dt in dts if dt > SLOW_DT_FACTOR * nominal_dt)
    slow_fraction = slow / len(dts)
    deviation_pct = abs(actual_hz - requested_hz) / requested_hz * 100.0

    ok = (deviation_pct <= TOLERANCE * 100.0
          and slow_fraction <= MAX_SLOW_FRACTION)

    if ok:
        message = (f"Sampling OK: requested {requested_hz:g} Hz, achieved "
                   f"{actual_hz:.2f} Hz ({deviation_pct:.1f}% off, "
                   f"{slow} slow periods).")
    else:
        message = (f"Sampling WARNING: requested {requested_hz:g} Hz but achieved "
                   f"{actual_hz:.2f} Hz ({deviation_pct:.1f}% off); "
                   f"{slow}/{len(dts)} periods slower than "
                   f"{SLOW_DT_FACTOR:g}x the nominal {nominal_dt * 1000:.1f} ms.")

    return {
        "requested_hz": requested_hz,
        "actual_hz": actual_hz,
        "deviation_pct": deviation_pct,
        "n_samples": n,
        "mean_dt": mean_dt,
        "max_dt": max_dt,
        "slow_fraction": slow_fraction,
        "ok": ok,
        "message": message,
    }
