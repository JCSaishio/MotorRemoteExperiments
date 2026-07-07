"""FrED Motor Remote Experiments - laptop desktop app.

Pick an Excel file (its 'Summary' sheet is the source of truth for the PID
gains Kp/Ki/Kd), set run time, wait time and reference RPM, optionally adjust
the plant transfer-function parameters used for the expected-response graphs,
then Run. The app connects to the FrED listener over the Pi's hotspot, runs the
experiments, and writes '[UploadedName]_ExperimentalResults.xlsx' with one
sheet + graphs per run.
"""

import os
import queue
import threading
import tkinter as tk
from tkinter import ttk, filedialog, messagebox

import excel_parser
import comm_client
import results_writer
import plant_model
import sampling_validator


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("FrED Motor Remote Experiments")
        self.geometry("680x660")
        self.minsize(660, 620)

        self.xlsx_path   = tk.StringVar()
        self.run_time    = tk.StringVar(value="30")
        self.wait_time   = tk.StringVar(value="5")
        self.reference   = tk.StringVar(value="45")
        self.sample_freq = tk.StringVar(value="50")
        self.host        = tk.StringVar(value=comm_client.DEFAULT_HOST)
        self.port        = tk.StringVar(value=str(comm_client.DEFAULT_PORT))

        # Plant transfer-function parameters for the expected-response graphs.
        # G(s) = num / (s^2 + a1*s + a0); filtered-derivative PID time const Tf;
        # motor voltage limit Vmax. Defaults come from compare_all_methods.m.
        self.tf_num  = tk.StringVar(value=str(plant_model.PLANT_NUM[0]))
        self.tf_a1   = tk.StringVar(value=str(plant_model.PLANT_DEN[1]))
        self.tf_a0   = tk.StringVar(value=str(plant_model.PLANT_DEN[2]))
        self.tf_tf   = tk.StringVar(value=str(plant_model.TF_DERIV))
        self.tf_vmax = tk.StringVar(value=str(plant_model.VMAX))

        self.experiments = []
        self.msg_queue = queue.Queue()
        self.worker = None

        self._build_ui()
        self.after(100, self._drain_queue)

    # ---------------- UI ----------------
    def _build_ui(self):
        pad = {"padx": 8, "pady": 4}

        frm = ttk.LabelFrame(self, text="1. Experiment file (Summary sheet = PID gains)")
        frm.pack(fill="x", **pad)
        ttk.Entry(frm, textvariable=self.xlsx_path, width=60).grid(row=0, column=0, padx=6, pady=6)
        ttk.Button(frm, text="Browse...", command=self._browse).grid(row=0, column=1, padx=6)
        self.file_info = ttk.Label(frm, text="No file loaded.")
        self.file_info.grid(row=1, column=0, columnspan=2, sticky="w", padx=6, pady=(0, 6))

        frm2 = ttk.LabelFrame(self, text="2. Settings (applied to all experiments)")
        frm2.pack(fill="x", **pad)
        ttk.Label(frm2, text="Run time [s]:").grid(row=0, column=0, sticky="e", padx=6, pady=6)
        ttk.Entry(frm2, textvariable=self.run_time, width=10).grid(row=0, column=1, sticky="w")
        ttk.Label(frm2, text="Wait time [s]:").grid(row=0, column=2, sticky="e", padx=6)
        ttk.Entry(frm2, textvariable=self.wait_time, width=10).grid(row=0, column=3, sticky="w")
        ttk.Label(frm2, text="Reference [RPM]:").grid(row=0, column=4, sticky="e", padx=6)
        ttk.Entry(frm2, textvariable=self.reference, width=10).grid(row=0, column=5, sticky="w")
        ttk.Label(frm2, text="Sampling freq [Hz]:").grid(row=1, column=0, sticky="e", padx=6, pady=(0, 6))
        ttk.Entry(frm2, textvariable=self.sample_freq, width=10).grid(row=1, column=1, sticky="w", pady=(0, 6))
        ttk.Label(frm2, text="(control-loop rate on the Pi; validated after each run)"
                  ).grid(row=1, column=2, columnspan=4, sticky="w", padx=6, pady=(0, 6))

        # ---- editable plant transfer function (expected-response graphs) ----
        frm_tf = ttk.LabelFrame(
            self, text="3. Plant model for expected-response graphs   "
                       "G(s) = num / (s² + a1·s + a0)")
        frm_tf.pack(fill="x", **pad)
        ttk.Label(frm_tf, text="num:").grid(row=0, column=0, sticky="e", padx=6, pady=6)
        ttk.Entry(frm_tf, textvariable=self.tf_num, width=13).grid(row=0, column=1, sticky="w")
        ttk.Label(frm_tf, text="a1:").grid(row=0, column=2, sticky="e", padx=6)
        ttk.Entry(frm_tf, textvariable=self.tf_a1, width=13).grid(row=0, column=3, sticky="w")
        ttk.Label(frm_tf, text="a0:").grid(row=0, column=4, sticky="e", padx=6)
        ttk.Entry(frm_tf, textvariable=self.tf_a0, width=13).grid(row=0, column=5, sticky="w")
        ttk.Label(frm_tf, text="Tf [s]:").grid(row=1, column=0, sticky="e", padx=6, pady=6)
        ttk.Entry(frm_tf, textvariable=self.tf_tf, width=13).grid(row=1, column=1, sticky="w")
        ttk.Label(frm_tf, text="Vmax [V]:").grid(row=1, column=2, sticky="e", padx=6)
        ttk.Entry(frm_tf, textvariable=self.tf_vmax, width=13).grid(row=1, column=3, sticky="w")
        ttk.Button(frm_tf, text="Reset defaults", command=self._reset_tf).grid(
            row=1, column=5, padx=6, sticky="w")

        frm3 = ttk.LabelFrame(self, text="4. FrED connection")
        frm3.pack(fill="x", **pad)
        ttk.Label(frm3, text="Pi host:").grid(row=0, column=0, sticky="e", padx=6, pady=6)
        ttk.Entry(frm3, textvariable=self.host, width=16).grid(row=0, column=1, sticky="w")
        ttk.Label(frm3, text="Port:").grid(row=0, column=2, sticky="e", padx=6)
        ttk.Entry(frm3, textvariable=self.port, width=8).grid(row=0, column=3, sticky="w")

        self.run_btn = ttk.Button(self, text="Run experiments", command=self._start)
        self.run_btn.pack(pady=8)

        self.progress = ttk.Progressbar(self, mode="determinate")
        self.progress.pack(fill="x", padx=8)

        logf = ttk.LabelFrame(self, text="Log")
        logf.pack(fill="both", expand=True, **pad)
        self.log = tk.Text(logf, height=9, wrap="word", state="disabled")
        self.log.pack(side="left", fill="both", expand=True, padx=(6, 0), pady=6)
        sb = ttk.Scrollbar(logf, command=self.log.yview)
        sb.pack(side="right", fill="y", pady=6)
        self.log.config(yscrollcommand=sb.set)

    def _reset_tf(self):
        self.tf_num.set(str(plant_model.PLANT_NUM[0]))
        self.tf_a1.set(str(plant_model.PLANT_DEN[1]))
        self.tf_a0.set(str(plant_model.PLANT_DEN[2]))
        self.tf_tf.set(str(plant_model.TF_DERIV))
        self.tf_vmax.set(str(plant_model.VMAX))

    def _read_model(self):
        return {
            "num":  float(self.tf_num.get()),
            "a1":   float(self.tf_a1.get()),
            "a0":   float(self.tf_a0.get()),
            "Tf":   float(self.tf_tf.get()),
            "vmax": float(self.tf_vmax.get()),
        }

    # ---------------- actions ----------------
    def _browse(self):
        path = filedialog.askopenfilename(
            title="Select experiment Excel file",
            filetypes=[("Excel files", "*.xlsx *.xlsm"), ("All files", "*.*")])
        if not path:
            return
        self.xlsx_path.set(path)
        try:
            self.experiments = excel_parser.parse_experiments(path)
            self.file_info.config(
                text=f"Loaded {len(self.experiments)} experiments from 'Summary'.")
            self._logline(f"Loaded {len(self.experiments)} experiments from {os.path.basename(path)}")
        except Exception as e:
            self.experiments = []
            self.file_info.config(text="Could not read file.")
            messagebox.showerror("File error", str(e))

    def _start(self):
        if self.worker and self.worker.is_alive():
            return
        if not self.experiments:
            messagebox.showwarning("No file", "Load a valid experiment file first.")
            return
        try:
            run_time    = float(self.run_time.get())
            wait_time   = float(self.wait_time.get())
            reference   = float(self.reference.get())
            sample_freq = float(self.sample_freq.get())
            port        = int(self.port.get())
        except ValueError:
            messagebox.showerror("Invalid input",
                                 "Run time, wait time, reference, sampling frequency "
                                 "and port must be numbers.")
            return
        if not (0 < sample_freq <= 1000):
            messagebox.showerror("Invalid sampling frequency",
                                 "Sampling frequency must be between 0 and 1000 Hz "
                                 "(the motor loop was validated at 50 Hz).")
            return
        try:
            model = self._read_model()
        except ValueError:
            messagebox.showerror("Invalid plant model",
                                 "Plant model fields (num, a1, a0, Tf, Vmax) must be numbers.")
            return
        host = self.host.get().strip()

        self.run_btn.config(state="disabled")
        self.progress.config(maximum=len(self.experiments), value=0)
        self._logline("-" * 50)
        self._logline(f"Connecting to FrED at {host}:{port} ...")

        self.worker = threading.Thread(
            target=self._run_job,
            args=(host, port, run_time, wait_time, reference, sample_freq, model),
            daemon=True)
        self.worker.start()

    def _run_job(self, host, port, run_time, wait_time, reference, sample_freq, model):
        results = []

        def on_progress(msg):
            self.msg_queue.put(("log", msg.get("message", "")))
            if msg.get("phase") == "running":
                self.msg_queue.put(("progress", msg.get("experiment", 0) - 1))

        def on_result(msg):
            msg.setdefault("sample_rate", sample_freq)  # older listeners don't echo it
            results.append(msg)
            self.msg_queue.put(("log", f"  -> got data for {msg['metric']}/{msg['algorithm']} "
                                       f"({len(msg['data']['time'])} samples)"))
            stats = sampling_validator.analyze(msg["data"]["time"], sample_freq)
            self.msg_queue.put(("log", "     " + stats["message"]))
            self.msg_queue.put(("progress", msg.get("index", len(results))))

        try:
            comm_client.run_job(
                host, port, run_time, wait_time, reference, self.experiments,
                sample_rate=sample_freq,
                on_progress=on_progress, on_result=on_result, timeout=15)
            self.msg_queue.put(("log", "All experiments finished. Building Excel..."))
            out_path = results_writer.default_output_name(self.xlsx_path.get())
            results_writer.build_results_workbook(results, out_path, model=model)
            self.msg_queue.put(("done", out_path))
        except Exception as e:
            self.msg_queue.put(("error", str(e)))

    # ---------------- queue pump (GUI thread) ----------------
    def _drain_queue(self):
        try:
            while True:
                kind, payload = self.msg_queue.get_nowait()
                if kind == "log":
                    self._logline(payload)
                elif kind == "progress":
                    self.progress.config(value=payload)
                elif kind == "done":
                    self.progress.config(value=self.progress["maximum"])
                    self._logline(f"DONE. Saved: {payload}")
                    self.run_btn.config(state="normal")
                    messagebox.showinfo("Complete", f"Results saved to:\n{payload}")
                elif kind == "error":
                    self._logline(f"ERROR: {payload}")
                    self.run_btn.config(state="normal")
                    messagebox.showerror("Error", payload)
        except queue.Empty:
            pass
        self.after(100, self._drain_queue)

    def _logline(self, text):
        self.log.config(state="normal")
        self.log.insert("end", text + "\n")
        self.log.see("end")
        self.log.config(state="disabled")


if __name__ == "__main__":
    App().mainloop()
