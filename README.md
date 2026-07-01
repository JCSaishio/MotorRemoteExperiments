# FrED Motor Remote Experiments

Run a batch of PID experiments on FrED's DC spooling motor from your laptop,
over the Raspberry Pi's own WiFi hotspot, and get back an Excel report with a
graphed sheet per experiment.

```
Laptop (Windows, Anaconda)                 Raspberry Pi 4 (Bookworm)
┌───────────────────────────┐              ┌──────────────────────────────┐
│ app.py (Tkinter)          │   WiFi       │ server.py (listener)         │
│  - load Summary sheet     │  hotspot     │  - runs 12 PID experiments   │
│  - set run/wait/reference │◀────TCP─────▶│    on the motor              │
│  - build results .xlsx    │  10.42.0.1   │  - streams data back         │
└───────────────────────────┘   :5001      └──────────────────────────────┘
```

---

## Repository layout

```
laptop/                 # runs on your Windows laptop (Anaconda)
  app.py                #   Tkinter GUI
  excel_parser.py       #   reads the 'Summary' sheet -> experiments
  comm_client.py        #   TCP/JSON client
  results_writer.py     #   builds [name]_ExperimentalResults.xlsx (+graphs)
  demo_preview.py       #   offline preview of the Excel (no Pi needed)
  requirements.txt
fred/                   # runs on the Raspberry Pi (fred-venv framework)
  server.py             #   experiment listener (foreground, Ctrl+C to stop)
  experiment_runner.py  #   headless PID motor loop (pins/PID from motor_control.py)
  fake_gpio.py          #   RPi.GPIO stand-in for off-Pi testing/simulation
  setup_install.sh      #   installer: apt deps + fred-venv + pip + SPI + verify
  setup_hotspot.sh      #   hotspot up / down / status
  start_experiments.sh  #   activate fred-venv and run the listener
  requirements.txt      #   pip packages for the venv (RPi.GPIO comes from apt)
  FrED_functions.py     #   motor_speed / filter / linearization
Example.xlsx            # sample input (its 'Summary' sheet = 12 gain sets)
motor_control.py        # original standalone script (unchanged)
```

> **Framework note.** The `fred/` side mirrors the main `fred-device`
> framework: a `fred-venv` created with `--system-site-packages`, with
> **`RPi.GPIO` installed from apt** (never pip) so the working system GPIO
> drives the motor. `experiment_runner.py` uses the same pins as
> `motor_control.py` / `spooler.py` (`PWM_PIN=5`, encoder select `1`,
> `1000 Hz`), plus the spooler's RPM-glitch guard and integral anti-windup.
> Off a Pi it auto-falls back to a motor **simulation** so the pipeline can be
> tested on any machine.

---

## The input file

The app reads the **`Summary`** sheet. It needs these columns (header row,
case-insensitive): **Metric, Algorithm, Kp, Ki, Kd**. `Example.xlsx` has 12
rows (IAE/ITAE/ISE/ITSE x PSO/EA/Bat) → 12 experiments → 12 output sheets.

---

## Commands to run (copy/paste)

### A. First time only — Raspberry Pi (needs internet, hotspot OFF)

Get the code onto the Pi with git. Either grab **only the `fred/` folder**
(sparse checkout) or clone the whole repo — pick one:

**Only the `fred/` folder (sparse checkout):**
```bash
git clone --no-checkout --depth 1 https://github.com/JCSaishio/MotorRemoteExperiments.git FrED_experiments
cd FrED_experiments
git sparse-checkout init --cone
git sparse-checkout set fred
git checkout
cd fred
```

**Or the whole repo (simplest):**
```bash
git clone https://github.com/JCSaishio/MotorRemoteExperiments.git FrED_experiments
cd FrED_experiments/fred
```

Then install (same for both):
```bash
bash setup_install.sh
```
This installs the apt system packages (incl. `python3-rpi.gpio`), creates the
`fred-venv` virtual environment with `--system-site-packages`, pip-installs the
rest into it, enables SPI, and verifies every import — plug and play.
`FrED_functions.py` must be in `fred/` (it already is in this repo).

> Later, to pull updates on the Pi: `git pull` from the repo folder.

### B. First time only — Laptop
Nothing to install (Anaconda already has everything). If you ever use a
different Python:
```bash
cd laptop
pip install -r requirements.txt
```

### C. Every experiment session

**Step 1 — Raspberry Pi:** open the hotspot and start the listener.
```bash
cd fred
bash setup_hotspot.sh          # Pi becomes AP at 192.168.4.1 (its normal WiFi pauses)
bash start_experiments.sh      # activates fred-venv + starts listener; leave it running
```

**Step 2 — Laptop:** join the `FrED_AP` WiFi (password `fred12345`), then:
```bash
cd laptop
python app.py
```
In the window: **Browse** to your Excel → set **Run time**, **Wait time**,
**Reference [RPM]** (host `192.168.4.1`, port `5001`) → **Run experiments**.
Result saved as `[YourFile]_ExperimentalResults.xlsx` next to your input file.

**Step 3 — Raspberry Pi:** when finished.
```bash
# press Ctrl+C in the start_experiments.sh terminal to stop the listener
bash setup_hotspot.sh down     # restore the Pi's normal networking
```

### Preview the Excel output without any hardware (laptop)
```bash
cd laptop
python demo_preview.py
```

---

## How it works (background)

The commands above are all you need. This section just explains what they do.

- **Laptop:** the Anaconda base env already has `openpyxl, pandas, matplotlib,
  numpy, pillow` and `tkinter`, so there's nothing to install.
- **`setup_install.sh`** mirrors the main `fred-device` installer: apt installs
  `python3-rpi.gpio` (+ venv/pip/dev, `libatlas-base-dev`), creates `fred-venv`
  **with `--system-site-packages`** (so the apt `RPi.GPIO` is visible), pip
  installs `numpy` / `adafruit-blinka` / `adafruit-circuitpython-mcp3xxx` /
  `spidev` into it, enables SPI, and verifies every import.
- **Why not pip-install `RPi.GPIO`?** Pip-installing it into the venv shadows
  the working apt build and can stop the motor from being driven — this was the
  actual cause of the "motor didn't turn on" failure. The venv reuses the apt
  `RPi.GPIO` instead, exactly like the main framework.
- **`start_experiments.sh`** activates `fred-venv` and runs `server.py`.
- **`experiment_runner.py`** is a headless port of `motor_control.py`'s control
  mode: identical pins (`PWM_PIN=5`, encoder select `1`), `1000 Hz` PWM, PID
  step, and `FrED_functions` calls (`motor_speed` / `filter` / `linearization`),
  plus the `spooler.py` RPM-glitch guard and integral anti-windup. It runs a
  fixed duration and returns the data. Off a Pi it simulates the motor.
- **`setup_hotspot.sh`** creates the `FrED_AP` profile with **autoconnect OFF**
  (fixed IP `192.168.4.1`), so the hotspot only comes up when you ask and the
  Pi stays free for everything else. `down` / `status` subcommands included.

> Default hotspot: SSID `FrED_AP`, password `fred12345`, Pi IP `192.168.4.1`.
> Change SSID/password at the top of `setup_hotspot.sh` (keep them in sync with
> `laptop/comm_client.py`). The app defaults its host/port to `192.168.4.1:5001`.

### Running it manually with the venv (on the Pi)
```bash
cd fred
source fred-venv/bin/activate     # prompt shows (fred-venv)
python server.py                  # same as start_experiments.sh
deactivate                        # when done
```

---

## The output file

`[YourFile]_ExperimentalResults.xlsx` — one sheet per experiment
(`IAE_PSO`, `IAE_EA`, ... `ITSE_Bat`). Each sheet:

- **Top-left:** metric, algorithm, reference, Kp/Ki/Kd, run/wait time.
- **Below that:** achieved **IAE / ITAE / ISE / ITSE** computed from the
  measured run.
- **Upper-right (next to that block):** *Motor Speed vs Time* (with the
  reference line) and *Motor Voltage vs Time*.
- **Below:** the full time-series data table
  (time, rpm, rpm_ref, motor_input, PWM, voltage, rpm_raw).

### Preview it now (no Pi needed)
```bash
cd laptop
python demo_preview.py
```
Writes `Example_ExperimentalResults_DEMO.xlsx` from synthetic data so you can
see the exact layout before touching hardware.

---

## Notes & troubleshooting

- **Install needs internet; the hotspot removes it.** Always run
  `bash setup_install.sh` *before* `bash setup_hotspot.sh`. To update packages
  later, run `bash setup_hotspot.sh down` first so the Pi is back online.
- **Listener says `Mode : SIMULATION`.** The Pi hardware libraries didn't
  import, so it's simulating the motor (fine on a laptop, wrong on the Pi). On
  the Pi, re-run `bash setup_install.sh` and confirm the import check passes.
- **Motor doesn't turn on.** The listener prints a per-experiment line like
  `PWM max=...% rpm final=...`. If `PWM max=0%`, the motor was never driven —
  check that the **Reference [RPM] is > 0**, that SPI is enabled
  (`sudo raspi-config nonint do_spi 0`), and that the encoder is wired. The
  runner uses the same pins/PID as your validated `motor_control.py`, run from
  `fred-venv` which reuses the apt `RPi.GPIO`; if `motor_control.py` turns the
  motor and this doesn't, capture the listener output and compare.
- **Reference / run time / wait time are the same for all 12 experiments**
  (set once in the app). The motor is driven to 0 % during the wait between
  experiments and on shutdown.
- **Can't connect from the laptop?** Confirm you're on the `FrED_AP` network,
  the listener is running, and try `ping 192.168.4.1`. The firewall on the Pi
  is off by default on Bookworm; if you enabled one, allow TCP 5001.
- **`FrED_functions.py` not found** on the Pi → copy it into `fred/`.
- **`cannot import RPi.GPIO` / import check fails** → the apt package is
  missing. Re-run `bash setup_install.sh` (it runs `apt install
  python3-rpi.gpio`) with internet. If `RPi.GPIO` errors at runtime on
  Bookworm, install the drop-in replacement into the venv:
  `source fred-venv/bin/activate && pip install rpi-lgpio`.
- **Re-running `setup_install.sh` is safe** — it reuses an existing `fred-venv`
  and only installs what's missing.
