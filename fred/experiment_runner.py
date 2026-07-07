######### FrED experiment runner ########
#
# Headless refactor of motor_control.py (control / PID mode), aligned with the
# main fred-device spooler.py:
#   - same pins  (PWM_PIN = 5, encoder select = 1, 1000 Hz PWM),
#   - same encoder SPI protocol,
#   - RPi.GPIO from the system (apt) — imported here, NOT pip-installed,
#   - integral anti-windup and an RPM glitch guard (from spooler.py),
#   - uses the Pi's existing FrED_functions.py for motor_speed / filter /
#     linearization (your validated PID experiment math).
#
# Initialises the motor hardware ONCE (MotorHardware) and runs one closed-loop
# PID experiment at a time for a fixed duration, returning the logged data.
#
# If the Pi hardware libraries are missing (e.g. running on a laptop) it falls
# back to a SIMULATION so the networking + Excel pipeline can be tested off-Pi.

import time

# ---- hardware imports, with an off-Pi simulation fallback ----
try:
    import RPi.GPIO as GPIO           # from apt (python3-rpi.gpio)
    import board
    import busio
    import digitalio
    import spidev
    import adafruit_mcp3xxx.mcp3008 as MCP
    from adafruit_mcp3xxx.analog_in import AnalogIn
    HARDWARE = True
except Exception:                     # off-Pi: simulate
    from fake_gpio import FakeGPIO
    GPIO = FakeGPIO()
    HARDWARE = False

import FrED_functions


########## Hardware constants (identical to motor_control.py / spooler.py) ######
SLAVE_SELECT_ENC       = 1
PWM_PIN                = 5
DC_FREQ                = 1000       # Hz
PULSES_PER_REVOLUTION  = 4704
SAMPLE_TIME            = 0.02       # s -> 50 Hz default control loop (as motor_control.py)
DEFAULT_SAMPLE_RATE    = 1.0 / SAMPLE_TIME   # Hz, used when the job doesn't send one
MOTOR_PWM_CEILING      = 100        # % duty cycle ceiling

# robustness guards borrowed from the proven spooler.py
RPM_GLITCH_LIMIT = 200.0            # ignore |rpm_raw| above this (encoder glitch)
INTEGRAL_LIMIT   = 100.0            # anti-windup clamp on the PID integral term


def pid_step(reference, measurement, prev_error, error_sum,
             current_time, prev_time, kp, ki, kd):
    """One PID iteration (same math as motor_control.py) with anti-windup."""
    delta_time = current_time - prev_time
    error   = reference - measurement
    error_d = (error - prev_error) / delta_time if delta_time > 0 else 0.0
    error_i = (error * delta_time) + error_sum
    error_i = max(min(error_i, INTEGRAL_LIMIT), -INTEGRAL_LIMIT)   # anti-windup
    output  = kp * error + ki * error_i + kd * error_d
    return output, error_i, error


class MotorHardware:
    """Owns GPIO / SPI / ADC / PWM. Created once per job. Reused across runs.

    On a Pi this drives the real motor/encoder. Off-Pi (HARDWARE is False) it
    simulates a first-order motor so the pipeline can be exercised.
    """

    def __init__(self):
        GPIO.setmode(GPIO.BCM)
        GPIO.setwarnings(False)
        GPIO.setup(PWM_PIN, GPIO.OUT)
        GPIO.setup(SLAVE_SELECT_ENC, GPIO.OUT)
        GPIO.output(SLAVE_SELECT_ENC, GPIO.HIGH)

        if HARDWARE:
            # SPI bus / ADC (kept for parity with motor_control.py)
            self.spi       = busio.SPI(clock=board.SCK, MISO=board.MISO, MOSI=board.MOSI)
            self.cs        = digitalio.DigitalInOut(board.D8)
            self.mcp       = MCP.MCP3008(self.spi, self.cs)
            self.channel_0 = AnalogIn(self.mcp, MCP.P0)

        self.motor_output = GPIO.PWM(PWM_PIN, DC_FREQ)
        self.motor_output.start(0)

        # simulation state (unused on real hardware)
        self._sim_pos    = 0
        self._sim_rpm    = 0.0
        self._sim_last_t = time.perf_counter()

        if HARDWARE:
            self._initialize_encoder()

    # ----- encoder helpers (unchanged logic from motor_control.py) -----
    def _initialize_encoder(self):
        self.spi_enc = spidev.SpiDev()
        self.spi_enc.open(0, 0)
        self.spi_enc.max_speed_hz = 50000
        GPIO.output(SLAVE_SELECT_ENC, GPIO.LOW)
        self.spi_enc.xfer2([0x88, 0x03])
        GPIO.output(SLAVE_SELECT_ENC, GPIO.HIGH)
        self.clear_encoder_count()

    def clear_encoder_count(self):
        if not HARDWARE:
            self._sim_pos    = 0
            self._sim_rpm    = 0.0
            self._sim_last_t = time.perf_counter()
            return
        GPIO.output(SLAVE_SELECT_ENC, GPIO.LOW)
        self.spi_enc.xfer2([0x98, 0x00, 0x00, 0x00, 0x00])
        GPIO.output(SLAVE_SELECT_ENC, GPIO.HIGH)
        time.sleep(0.0001)
        GPIO.output(SLAVE_SELECT_ENC, GPIO.LOW)
        self.spi_enc.xfer2([0xE0])
        GPIO.output(SLAVE_SELECT_ENC, GPIO.HIGH)

    def read_encoder(self):
        if not HARDWARE:
            return self._sim_read_encoder()
        GPIO.output(SLAVE_SELECT_ENC, GPIO.LOW)
        self.spi_enc.xfer2([0x60])
        count_1 = self.spi_enc.xfer2([0x00])
        count_2 = self.spi_enc.xfer2([0x00])
        count_3 = self.spi_enc.xfer2([0x00])
        count_4 = self.spi_enc.xfer2([0x00])
        GPIO.output(SLAVE_SELECT_ENC, GPIO.HIGH)
        return (
            (count_1[0] << 24) +
            (count_2[0] << 16) +
            (count_3[0] << 8) +
            count_4[0]
        )

    def _sim_read_encoder(self):
        """Simulated encoder: first-order motor responding to the last duty %.

        100% duty -> ~60 rpm; FrED_functions.motor_speed has a leading minus, so
        positive speed corresponds to a DECREASING count (as on the real rig).
        """
        now = time.perf_counter()
        dt = now - self._sim_last_t
        self._sim_last_t = now
        duty = getattr(self.motor_output, "duty_cycle", 0) or 0
        target_rpm = 0.6 * duty                      # 100% -> 60 rpm
        tau = 0.4
        self._sim_rpm += (target_rpm - self._sim_rpm) * min(dt / tau, 1.0)
        self._sim_pos -= int(self._sim_rpm * PULSES_PER_REVOLUTION / 60.0 * dt)
        return self._sim_pos

    # ----- motor helpers -----
    def motor_off(self):
        self.motor_output.ChangeDutyCycle(0)

    def cleanup(self):
        try:
            self.motor_output.ChangeDutyCycle(0)
        except Exception:
            pass
        GPIO.cleanup()


def run_experiment(hw, kp, ki, kd, reference, run_time,
                   sample_rate=DEFAULT_SAMPLE_RATE, progress_cb=None):
    """
    Run one closed-loop PID experiment for `run_time` seconds.

    hw          : a MotorHardware instance (hardware already initialised)
    kp, ki, kd  : PID gains
    reference   : rpm setpoint held for the whole run
    run_time    : experiment duration in seconds
    sample_rate : control-loop / sampling frequency in Hz (default 50)
    progress_cb : optional callable(current_time) for occasional updates

    Returns a dict of equal-length lists ready for JSON transport.
    """
    sample_time = 1.0 / float(sample_rate)
    hw.clear_encoder_count()

    time_data          = []
    rpm_data           = []
    rpm_raw_data       = []
    rpm_ref_data       = []
    motor_input_data   = []
    pwm_data           = []
    voltage_data       = []

    previous_time     = 0.0
    previous_PIDtime  = 0.0
    previous_rpm      = 0.0
    previous_PIDerror = 0.0
    error_sum         = 0.0

    tstart     = time.perf_counter()
    match_time = sample_time
    next_note  = 1.0

    # Prime the previous position from a real read so the first speed sample is
    # sane (avoids the huge first-sample spike; matches spooler.py behaviour).
    previous_position = hw.read_encoder()

    try:
        while True:
            current_time = time.perf_counter() - tstart
            if current_time > run_time:
                break

            # 1) measure speed
            current_position = hw.read_encoder()
            rpm_raw = FrED_functions.motor_speed(
                current_time, previous_time, previous_position, current_position)
            if abs(rpm_raw) > RPM_GLITCH_LIMIT:      # encoder glitch guard
                rpm_raw = 0.0
            previous_time     = current_time
            previous_position = current_position

            rpm          = FrED_functions.filter(rpm_raw, previous_rpm)
            previous_rpm = rpm

            # 2) PID (with anti-windup inside pid_step)
            motor_input, error_i, PIDerror = pid_step(
                reference, rpm, previous_PIDerror, error_sum,
                current_time, previous_PIDtime, kp, ki, kd)
            previous_PIDerror = PIDerror
            previous_PIDtime  = current_time
            error_sum         = error_i

            # 3) linearize + clamp + drive
            PWM_motor = FrED_functions.linearization(motor_input)
            PWM_motor = max(min(PWM_motor, MOTOR_PWM_CEILING), 0)
            hw.motor_output.ChangeDutyCycle(PWM_motor)

            # 4) log
            motor_voltage = (12 * PWM_motor) / 100
            time_data.append(round(current_time, 4))
            rpm_data.append(round(rpm, 2))
            rpm_raw_data.append(round(rpm_raw, 2))
            rpm_ref_data.append(reference)
            motor_input_data.append(round(motor_input, 2))
            pwm_data.append(round(PWM_motor, 2))
            voltage_data.append(round(motor_voltage, 2))

            if progress_cb is not None and current_time >= next_note:
                progress_cb(current_time)
                next_note += 1.0

            # 5) hold the requested sampling cadence
            wait = max(0, match_time - current_time)
            time.sleep(wait)
            match_time += sample_time
    finally:
        hw.motor_off()

    return {
        "time":        time_data,
        "rpm":         rpm_data,
        "rpm_ref":     rpm_ref_data,
        "motor_input": motor_input_data,
        "pwm":         pwm_data,
        "voltage":     voltage_data,
        "rpm_raw":     rpm_raw_data,
    }
