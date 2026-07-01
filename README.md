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
fred/                   # runs on the Raspberry Pi
  server.py             #   experiment listener (foreground, Ctrl+C to stop)
  experiment_runner.py  #   headless PID motor loop (from motor_control.py)
  install.sh            #   one-time setup: venv + hotspot profile
  hotspot_on.sh         #   bring hotspot up
  hotspot_off.sh        #   bring hotspot down
  run_experiments.sh    #   start the listener
  requirements.txt
  FrED_functions.py     #   <-- YOU add this (copy from your existing project)
Example.xlsx            # sample input (its 'Summary' sheet = 12 gain sets)
motor_control.py        # original standalone script (unchanged)
```

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
chmod +x *.sh
./install.sh
```
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
./hotspot_on.sh          # Pi becomes AP at 10.42.0.1 (its normal WiFi pauses)
./run_experiments.sh     # listener starts; leave this terminal running
```

**Step 2 — Laptop:** join the `FrED_AP` WiFi (password `fred12345`), then:
```bash
cd laptop
python app.py
```
In the window: **Browse** to your Excel → set **Run time**, **Wait time**,
**Reference [RPM]** → **Run experiments**.
Result saved as `[YourFile]_ExperimentalResults.xlsx` next to your input file.

**Step 3 — Raspberry Pi:** when finished.
```bash
# press Ctrl+C in the run_experiments.sh terminal to stop the listener
./hotspot_off.sh         # restore the Pi's normal networking
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
- **`fred/install.sh`** creates a `--system-site-packages` virtualenv (`.venv`)
  that reuses the Adafruit/RPi.GPIO stack already driving your motor, and
  creates the `FrED_AP` hotspot profile with **autoconnect OFF** (so it never
  comes up on its own and the Pi stays free for everything else).
- **`FrED_functions.py`** must be in `fred/` (`experiment_runner.py` imports it
  for `motor_speed` / `filter` / `linearization`). It already is in this repo.

> Default hotspot: SSID `FrED_AP`, password `fred12345`, Pi IP `10.42.0.1`.
> Change SSID/password at the top of `install.sh` before running it (or edit
> the profile later with `nmcli connection modify FrED_AP ...`).
> The app defaults its host/port to `10.42.0.1:5001`.

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

- **Install needs internet; the hotspot removes it.** Always run `install.sh`
  *before* `hotspot_on.sh`. To update packages later, run `hotspot_off.sh`
  first so the Pi is back online.
- **Reference / run time / wait time are the same for all 12 experiments**
  (set once in the app). The motor is driven to 0 % during the wait between
  experiments and on shutdown.
- **Can't connect from the laptop?** Confirm you're on the `FrED_AP` network,
  the listener is running, and try `ping 10.42.0.1`. The firewall on the Pi is
  off by default on Bookworm; if you enabled one, allow TCP 5001.
- **`FrED_functions.py` not found** on the Pi → copy it into `fred/`.
- **`ModuleNotFoundError: No module named 'board'`** (or `busio`, `digitalio`,
  `adafruit_mcp3xxx`, `RPi`, `spidev`) when starting the listener → the venv
  can't see your system Adafruit stack (it was likely installed under
  `~/.local`). Install the hardware libs **into the venv** (needs internet, so
  run `./hotspot_off.sh` first if the hotspot is up):
  ```bash
  cd fred
  ./.venv/bin/pip install -r requirements.txt
  ```
  These libs are now in `requirements.txt`, so a fresh `./install.sh` also
  covers it. If `RPi.GPIO` later errors at runtime on Bookworm, install the
  drop-in replacement: `./.venv/bin/pip install rpi-lgpio`.
```
