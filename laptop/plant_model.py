"""Expected closed-loop response from the plant in compare_all_methods.m.

Faithful Python port of the MATLAB simulation used to tune the PID gains:

    Plant (voltage -> angular speed in rad/s):
        G(s) = 1731.3048 / (s^2 + 472.6205 s + 3495.7927)

    Controller (filtered-derivative PID, opt.useDerivFilter = true, Tf = 1e-3):
        C(s) = Kp + Ki/s + Kd*s/(Tf*s + 1)

    Expected speed  : step of  T  = C*G / (1 + C*G),  scaled to Reference_RPM
    Expected voltage: step of  Tu = C   / (1 + C*G),  scaled by r = Ref*2pi/60

Given a gain set (Kp, Ki, Kd) and a reference in RPM, `expected_response`
returns the modelled motor speed (RPM) and control voltage (V) over time.
"""

import numpy as np
from scipy import signal


# --- constants from compare_all_methods.m ---
PLANT_NUM = [1731.3048]
PLANT_DEN = [1.0, 472.6205, 3495.7927]
TF_DERIV  = 1e-3        # opt.Tf  — derivative filter time constant [s]
VMAX      = 11.5        # opt.Vmax — motor voltage limit [V]

RPM2RADS = 2 * np.pi / 60


def _pid_num_den(kp, ki, kd, Tf=TF_DERIV):
    """C(s) = Kp + Ki/s + Kd*s/(Tf*s+1) over the common denominator s*(Tf*s+1).

        num = (Kp*Tf + Kd) s^2 + (Kp + Ki*Tf) s + Ki
        den =  Tf s^2 + s
    """
    num = [kp * Tf + kd, kp + ki * Tf, ki]
    den = [Tf, 1.0, 0.0]
    return num, den


def expected_response(kp, ki, kd, reference_rpm, t,
                      plant_num=None, plant_den=None, Tf=None):
    """Return (rpm_expected, voltage_expected) over the time vector `t`.

    Mirrors the MATLAB: y = r*step(T); plot y*rads2rpm  ->  Reference_RPM*step(T)
    and                 u = r*step(Tu) with r in rad/s.

    plant_num / plant_den / Tf override the defaults (used by the GUI so the
    plant transfer function can be edited without changing the source of truth
    for the PID gains, which is the Excel file).
    """
    t = np.asarray(t, dtype=float)
    numG = PLANT_NUM if plant_num is None else plant_num
    denG = PLANT_DEN if plant_den is None else plant_den
    Tf   = TF_DERIV  if Tf is None else Tf
    numC, denC = _pid_num_den(kp, ki, kd, Tf)

    numCG = np.polymul(numC, numG)
    denCG = np.polymul(denC, denG)

    # closed loop  T = CG / (1 + CG)
    denT = np.polyadd(denCG, numCG)
    numT = numCG

    # control effort  Tu = C / (1 + CG) = numC*denG / denT
    numTu = np.polymul(numC, denG)

    _, y = signal.step((numT, denT), T=t)
    _, u = signal.step((numTu, denT), T=t)

    rpm_expected     = reference_rpm * np.asarray(y)
    voltage_expected = (reference_rpm * RPM2RADS) * np.asarray(u)
    return rpm_expected, voltage_expected
