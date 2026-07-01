"""RPi.GPIO stand-in for off-Pi testing.

Lets server.py / experiment_runner.py import and run on a laptop (no Pi
hardware) so the networking + control loop + Excel pipeline can be exercised.
On a real Pi the genuine RPi.GPIO (from apt) is used instead. Mirrors the
fake_gpio.py used by the main fred-device framework, with ChangeDutyCycle added.
"""


class FakeGPIO:
    """Simulate RPi.GPIO for testing purposes."""
    BCM = "BCM"
    OUT = "OUT"
    IN = "IN"
    HIGH = 1
    LOW = 0

    def __init__(self):
        self.pins = {}

    def setwarnings(self, warnings):
        pass

    def setmode(self, mode):
        pass

    def setup(self, pin, mode):
        self.pins[pin] = {"mode": mode, "state": FakeGPIO.LOW}

    def output(self, pin, state):
        if pin in self.pins:
            self.pins[pin]["state"] = state

    def input(self, pin):
        return self.pins.get(pin, {}).get("state", FakeGPIO.LOW)

    def cleanup(self):
        self.pins.clear()

    class PWM:
        def __init__(self, pin, frequency=1000):
            self.pin = pin
            self.frequency = frequency
            self.duty_cycle = 0

        def start(self, duty_cycle):
            self.duty_cycle = duty_cycle

        def ChangeDutyCycle(self, duty_cycle):
            self.duty_cycle = duty_cycle

        def stop(self):
            self.duty_cycle = 0
