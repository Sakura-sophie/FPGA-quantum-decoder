# FPGA-quantum-decoder
# Neutral Atom Array Image Processing (Red Pitaya STEMlab 125-14)
 
FPGA-based image processing pipeline for real-time detection, counting, and rearrangement of neutral atoms in an optical tweezer array, implemented on a Red Pitaya STEMlab 125-14 (Xilinx Zynq-7010). The system processes camera image data to locate atoms, determines a rearrangement sequence to fill a target grid pattern, and outputs control signals via the onboard DAC to drive the rearrangement hardware (e.g. AOD/AOM).
 
## Table of Contents
- [Overview](#overview)
- [Repository Structure](#repository-structure)
- [Architecture / Block Design](#architecture--block-design)
- [Requirements](#requirements)
- [Getting Started](#getting-started)
- [Constraints](#constraints)
- [Algorithm](#algorithm)
- [Simulation & Testbenches](#simulation--testbenches)
- [Building & Programming the Red Pitaya](#building--programming-the-red-pitaya)
- [Results / Verification](#results--verification)
- [Future Work](#future-work)
- [License](#license)
## Overview

- **Application:** Real-time image processing for neutral atom arrays in quantum computing
- **Target device:** [Red Pitaya STEMlab 125-14 (Xilinx Zynq-7010, dual-core ARM Cortex-A9 + programmable logic)](https://redpitaya.readthedocs.io/en/latest/developerGuide/hardware/ORIG_GEN/125-14/top.html#top-125-14)
- **Toolchain:**  [AMD Vivado 2026.1](https://www.xilinx.com/support/download.html) — download the **Self Extracting Web Installer** (~286 MB for Windows, ~394 MB for Linux), not the full offline SFD image (~98 GB). The web installer lets you select only the components you need (WebPACK license, Zynq-7000 device support) and downloads them on demand — no need for the full package.
- **Language:** VHDL
- **I/O:** 2x 14-bit ADC input channels (125 MSPS), 2x 14-bit DAC output channels (125 MSPS)
- **Pipeline:** Camera image in → atom detection/thresholding → counting → grid rearrangement decision → DAC output to rearrangement optics.

## Repository Structure
 
```
.
├── src/            # VHDL source files (RTL)
├── testbench/      # VHDL testbenches
├── constraints/    # Pin and timing constraints (.xdc)
├── docs/           # Block diagrams, waveforms, screenshots
├── sim/            # Simulation scripts / waveform configs
├── .gitignore
└── README.md
```
## Architecture / Block Design
 
Insert your block diagram here:
 
```
![Block Diagram](docs/block_diagram.png)
```
 
Describe the pipeline stages, e.g.:
 
- **Image input interface** — how camera frame data enters the FPGA (via ADC channels directly, via PS-side capture and AXI stream into PL, GigE/CameraLink bridged through the ARM core, etc. — specify your actual interface)
- **Atom detection block** — thresholding / peak-finding logic that identifies atom presence at each expected lattice site from the image data
- **Counting block** — tallies detected atoms and produces the current occupancy grid
- **Rearrangement algorithm block** — compares current occupancy to the target pattern and computes the move sequence needed to fill it
- **DAC output stage** — converts the rearrangement move sequence into the analog control waveform(s) sent to the AOD/AOM driving the tweezer rearrangement
- **PS/PL interface** — what the ARM core (Zynq PS) handles vs. what runs in FPGA fabric (PL) — e.g. PS for configuration/monitoring, PL for the real-time detection and DAC pipeline
If there's a top-level state machine (e.g. IDLE → CAPTURE → DETECT → DECIDE → OUTPUT), a state diagram here is worth including.



## Getting Started
 
1. Clone the repository:
```bash
   git clone https://github.com/<your-username>/<repo-name>.git
   cd <repo-name>
```
2. If building on the Red Pitaya base project, clone/reference it separately and follow their setup instructions for generating the base block design before adding this project's custom IP.
3. Open the project in Vivado (or recreate it from the provided `.tcl` build script, if included).
4. Set the top-level VHDL file as the top module.
5. Run synthesis, implementation, and generate the bitstream.
## Constraints
 
The `.xdc` file(s) in `constraints/` define the Red Pitaya's fixed pin mapping for:
 
- **ADC input pins** — connects to the onboard 14-bit ADC channels carrying camera/image signal data
- **DAC output pins** — connects to the onboard 14-bit DAC channels driving the rearrangement control signal
- **System clock** — the Red Pitaya's onboard clock source and PLL configuration
- **GPIO / expansion connector pins** — if using the extension header for additional camera or trigger I/O
Red Pitaya's official repository provides a reference `.xdc` for the STEMlab 125-14 — reuse it as the base rather than remapping pins from scratch, since the ADC/DAC/clock connections are fixed by the board layout

## Algorithm
 
Describe the detection and rearrangement algorithm in more detail here, e.g.:
 
- **Detection:** how a site is classified as occupied/empty from the raw image (thresholding method, filtering, calibration approach)
- **Counting:** how the total atom count and occupancy grid are represented in hardware (e.g. bit vector, register array)
- **Rearrangement strategy:** the logic used to decide which atoms move where to fill the target pattern (e.g. row-by-row, column compaction, or a specific published rearrangement algorithm you implemented/adapted)
- **Timing:** how fast this runs end-to-end (important for atom trapping — rearrangement usually needs to happen within the atom lifetime/trap coherence window)
