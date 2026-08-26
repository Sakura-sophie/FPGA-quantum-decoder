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
