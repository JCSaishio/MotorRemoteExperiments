######### FrED experiment runner ########
#
# Headless refactor of motor_control.py (control / PID mode).
# Initialises the motor hardware ONCE (MotorHardware), then runs one
# closed-loop PID experiment at a time for a fixed duration and returns
# the logged data as plain Python lists (ready to serialise to JSON).
#
# Reuses the Pi's existing FrED_functions.py for motor_speed / filter /
# linearization, exactly like the original script.

import time

import RPi.GPIO as GPIO
import board
import busio
import digitalio
import spidev
import adafruit_mcp3xxx.mcp3008 as MCP
from adafruit_mcp3xxx.analog_in import AnalogIn

import FrED_functions


########## Hardware constants (from motor_control.py) ##########
SLAVE_SELECT_ENC  = 1
motorPin          = 5
tm                = 0.02      # sample period (s) -> 50 Hz
MATCH_TIME_INIT   = 0.020
dcFreq            = 1000
MOTOR_PWM_CEILING = 100       # % duty cycle ceiling


def pid_step(reference, measurement, prev_error, error_sum,
             current_time, prev_time, kp, ki, kd):
    """One PID iteration with gains passed as arguments (same as original)."""
    delta_time = current_time - prev_time
    error   = reference - measurement
    error_d = (error - prev_error) / delta_time if delta_time > 0 else 0.0
    error_i = (error * delta_time) + error_sum
    output  = kp * error + ki * error_i + kd * error_d
    return output, error_i, error


class MotorHardware:
    """Owns the GPIO / SPI / ADC / PWM setup. Created once per job."""

    def __init__(self):
        GPIO.setmode(GPIO.BCM)
        GPIO.setwarnings(False)
        GPIO.setup(motorPin, GPIO.OUT)

        # SPI bus / ADC (kept for parity with the original script)
        self.spi       = busio.SPI(clock=board.SCK, MISO=board.MISO, MOSI=board.MOSI)
        self.cs        = digitalio.DigitalInOut(board.D8)
        self.mcp       = MCP.MCP3008(self.spi, self.cs)
        self.channel_0 = AnalogIn(self.mcp, MCP.P0)

        # Motor PWM
        self.motor_output = GPIO.PWM(motorPin, dcFreq)
        self.motor_output.start(0)

        # Encoder slave-select
        GPIO.setup(SLAVE_SELECT_ENC, GPIO.OUT)
        GPIO.output(SLAVE_SELECT_ENC, GPIO.HIGH)

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
        GPIO.output(SLAVE_SELECT_ENC, GPIO.LOW)
        self.spi_enc.xfer2([0x98, 0x00, 0x00, 0x00, 0x00])
        GPIO.output(SLAVE_SELECT_ENC, GPIO.HIGH)
        time.sleep(0.0001)
        GPIO.output(SLAVE_SELECT_ENC, GPIO.LOW)
        self.spi_enc.xfer2([0xE0])
        GPIO.output(SLAVE_SELECT_ENC, GPIO.HIGH)

    def read_encoder(self):
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

    # ----- motor helpers -----
    def motor_off(self):
        self.motor_output.ChangeDutyCycle(0)

    def cleanup(self):
        try:
            self.motor_output.ChangeDutyCycle(0)
        except Exception:
            pass
        GPIO.cleanup()


def run_experiment(hw, kp, ki, kd, reference, run_time, progress_cb=None):
    """
    Run one closed-loop PID experiment for `run_time` seconds.

    hw          : a MotorHardware instance (hardware already initialised)
    kp, ki, kd  : PID gains
    reference   : rpm setpoint held for the whole run
    run_time    : experiment duration in seconds
    progress_cb : optional callable(current_time) for occasional updates

    Returns a dict of equal-length lists ready for JSON transport.
    """
    # Fresh encoder + controller state for every experiment
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

    previous_position = 4294967269
    first_sample      = True

    tstart     = time.perf_counter()
    match_time = MATCH_TIME_INIT
    next_note  = 1.0

    try:
        while True:
            current_time = time.perf_counter() - tstart
            if current_time > run_time:
                break

            current_position = hw.read_encoder()
            if first_sample:
                current_position = 4294967265
                first_sample     = False

            # 1) measure speed
            rpm_raw           = FrED_functions.motor_speed(
                current_time, previous_time, previous_position, current_position)
            previous_time     = current_time
            previous_position = current_position

            rpm          = FrED_functions.filter(rpm_raw, previous_rpm)
            previous_rpm = rpm

            # 2) PID
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

            # 5) hold 50 Hz cadence
            wait = max(0, match_time - current_time)
            time.sleep(wait)
            match_time += tm
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
