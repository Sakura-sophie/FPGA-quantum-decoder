# FPGA-quantum-decoder
# Neutral Atom Array Image Processing (Red Pitaya STEMlab 125-14)
 
FPGA-based image processing pipeline for real-time detection, counting, and rearrangement of neutral atoms in an optical tweezer array, implemented on a Red Pitaya STEMlab 125-14 (Xilinx Zynq-7010). The system processes camera image data to locate atoms, determines a rearrangement sequence to fill a target grid pattern, and outputs control signals via the onboard DAC to drive the rearrangement hardware (e.g. AOD/AOM).
 
## Table of Contents
- [Overview](#overview)
- [Architecture / Block Design](#architecture--block-design)
- [Repository Structure](#repository-structure)
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
