# FPGA-quantum-decoder
# Neutral Atom Array Image Processing (Red Pitaya STEMlab 125-14)
 
FPGA-based image processing pipeline for real-time detection, counting, and rearrangement of neutral atoms in an optical tweezer array, implemented on a Red Pitaya STEMlab 125-14 (Xilinx Zynq-7010). The system processes camera image data to locate atoms, uses closed-loop feedback to determine a rearrangement sequence to fill a target grid pattern, and outputs control signals via the onboard DAC to drive the rearrangement hardware (e.g. AOD). Uses ssh terminal to communicate with the board.
 
## Table of Contents
- [Overview](#overview)
- [Repository Structure](#repository-structure)
- [Architecture / Block Design](#architecture--block-design)
- [Getting Started](#getting-started)
- [Constraints](#constraints)
- [Algorithm](#algorithm)
- [Simulation & Testbenches](#simulation--testbenches)
- [Results / Verification](#results--verification)
- [Future Work](#future-work)
## Overview

- **Application:** Real-time image processing for neutral atom arrays in quantum computing
- **Target device:** [Red Pitaya STEMlab 125-14 (Xilinx Zynq-7010, dual-core ARM Cortex-A9 + programmable logic)](https://redpitaya.readthedocs.io/en/latest/developerGuide/hardware/ORIG_GEN/125-14/top.html#top-125-14)
- **Toolchain:**  [AMD Vivado 2026.1](https://www.xilinx.com/support/download.html) — download the **Self Extracting Web Installer** (~286 MB for Windows, ~394 MB for Linux), not the full offline SFD image. The web installer lets you select only the components you need (Zynq-7000), no need for the full package.
- **Language:** VHDL
- **I/O:** 2x 14-bit ADC input channels (125 MSPS), 2x 14-bit DAC output channels (125 MSPS)
- **Pipeline:** Camera image in → atom detection/thresholding → counting → grid rearrangement decision → DAC output to rearrangement optics.

## Repository Structure
 
```
.
├── src/            # VHDL source files 
├── testbench/      # VHDL testbench for simulation
├── constraints/    # Pin constraints (.xdc)
├── docs/           # Block diagram, waveforms, screenshots
├── sim/            # Simulation scripts (python streaming data over AXI GPIO)
└── README.md
```
## Block Design
  
![Block Diagram](docs/Block_design.png)

The Vivado block design connects five components:

- **Zynq7 Processing System (PS7)** - provides the 125 MHz system clock 
  (`FCLK_CLK0`) and active-low reset (`FCLK_RESET0_N`) to the 
  programmable logic. The `_N` suffix means reset is active when the 
  signal is driven low - keep this consistent throughout or the design 
  will be permanently held in reset.
  
- **AXI GPIO** - dual-channel GPIO used to stream simulated pixel data 
  from a Python script into the FPGA over SSH:
  - Channel 1: `img_bit_stream` - 14-bit pixel brightness value
  - Channel 2: `valid` - 1-bit handshake between camera and board, pulses high once per pixel
    
- **my_FPGA** - the custom RTL module containing the full processing pipeline
  
- **AXI SmartConnect** - routes AXI read/write from the PS7's master port to the correct slave (AXI GPIO) based on the configured address map; required whenever a Zynq PS interfaces with AXI peripherals in the PL.
  
- **PROC_SYS_RESET** - synchronises the PS7's asynchronous FCLK_RESET0_N to the 125 MHz fabric clock domain and generates the correctly-polarised reset variants (active-high/active-low) needed by the AXI SmartConnect and AXI GPIO, preventing metastability at the reset input.

 In the ZYNQ7 processing module, double click and Disable DDR, then make Fixed IO external (Vivado deals with this pin itself). Make Trigger, and all the output ports in my_FPGA external.
 
 Once block design is complete, validate design to check no wiring or hardware errors. Then go to the sources tab and right click on the block design and select create HDL wrapper to convert the block diagram into actual verilog code that can be understood by Vivado when implementing the design.
To note: After any further edits to VHDL design, go to block design and refresh module to update. 


 ## Architecture
 
Describe the detection and rearrangement algorithm in more detail here, e.g.:
 
- **Detection:** how a site is classified as occupied/empty from the raw image (thresholding method, filtering, calibration approach)
- **Counting:** how the total atom count and occupancy grid are represented in hardware (e.g. bit vector, register array)
- **Rearrangement strategy:** the logic used to decide which atoms move where to fill the target pattern (e.g. row-by-row, column compaction, or a specific published rearrangement algorithm you implemented/adapted)
- **Timing:** how fast this runs end-to-end (important for atom trapping — rearrangement usually needs to happen within the atom lifetime/trap coherence window)
 
- **Image input interface** — how camera frame data enters the FPGA (via ADC channels directly, via PS-side capture and AXI stream into PL, GigE/CameraLink bridged through the ARM core, etc. — specify your actual interface)
- **Atom detection block** — thresholding / peak-finding logic that identifies atom presence at each expected lattice site from the image data
- **Counting block** — tallies detected atoms and produces the current occupancy grid
- **Rearrangement algorithm block** — compares current occupancy to the target pattern and computes the move sequence needed to fill it
- **DAC output stage** — converts the rearrangement move sequence into the analog control waveform(s) sent to the AOD/AOM driving the tweezer rearrangement [DAC methods - Go to interleaved mode, not dual port](https://www.analog.com/media/en/technical-documentation/data-sheets/AD9763_9765_9767.pdf) or access data sheet via [ANALOG DEVICES AD9767](https://www.analog.com/en/products/AD9767.html)
- **PS/PL interface** — what the ARM core (Zynq PS) handles vs. what runs in FPGA fabric (PL) — e.g. PS for configuration/monitoring, PL for the real-time detection and DAC pipeline
If there's a top-level state machine (e.g. IDLE → CAPTURE → DETECT → DECIDE → OUTPUT), a state diagram here is worth including.

Valid phase, ensures read each pixel only once.
image_data_latched_1. 1 cycle delay so that start read doesn't occur too early.



## Getting Started
 
1. Open Vivado and create a new project targeting `xc7z010clg400-1`.
2. Add `src/my_FPGA.vhd` as a design source
3. Add `constraints/constraints.xdc` as a constraint source
4. Recreate the block design (see above) and generate the HDL wrapper
5. Run Synthesis → Implementation → Generate Bitstream
6. Connect power to the board and switch on. Use ethernet to connect to pc.
7. Wait roughly 20 s then type rp-xxxxxx.local in web address to verify communication between board and pc. Replace xxxxxx with the boards specific ID printed on it.
8. Once web browser loads, transfer .bit file to FPGA. This can be done via SSH over ethernet. Alternative methods can be found [here]().
9. SSH is available natively on Windows (PowerShell / Command Prompt), Mac, and Linux — no additional software required.
10. ```bash
    # From your PC terminal, copy bitstream to the board. 
     scp C:\path\Design_name_wrapper.bit root@rp-xxxxxx.local:/tmp/
    
    # SSH into the board (default password: root)
    ssh root@rp-xxxxxx.local
    
    # Load the bitstream onto the FPGA
    cat /tmp/design_wrapper.bit > /dev/xdevcfg
    ```
13. In a separate window, load txt file containing simulated data (my text file named myfile).
    ```bash
    cd C:\textfilepath
    scp myfile.txt root@rp-f00ac3:~
    ```
15. back in ssh terminal open python via command ```nano test.py```
16. paste `test.py` in file `sim/`and save and exit
17. Run ``` python3 test.py ```. LEDs 0-2 should light up
18. Connect function generator to pin DIO5_P in E1 to implement the trigger signal for readout. Look for light at LED_3 and waveform on oscilloscope out of DAC.
Additional : If difficulty connecting pc to board, go to [Network Manager](https://redpitaya.readthedocs.io/en/latest/appsFeatures/systemtool/network_manager/networkManager.html).

   
## Constraints
 
The `constraints.xdc` file in `constraints/` defines the Red Pitaya's fixed pin mapping for:
 
- **DAC output pins** — connects to the onboard 14-bit DAC channels driving the rearrangement control signal
- **GPIO / expansion connector pins** — Uses the extension header for the Trigger GPIO (DIO5_P in E1 connector).
- **LED pins** - Connects signals q1 to q4 within my_FPGA to the onboard LEDs to indicate when certain stages in the FSM are complete. Useful for debugging.
Pin assignments are taken from `Schematics_STEM_125-14_v1.1.pdf` available from Red Pitaya's official documentation (https://redpitaya.readthedocs.io/en/latest/developerGuide/hardware/ORIG_GEN/125-14/top.html#top-125-14) All GPIO pins are LVCMOS33. 






## Simulation & Testbenches
 
Simulation often has max timing it can simulate. Scale down the slowed clock and output_del to ~ 4 and 10 to see logic clearly in waveforms. screenshots  of how waveforms should look during simulation are given in file `docs/`.
 
Can simulate in Vivado by adding testbench in add sources tab or on platforms such as EDA playground which I found easier and faster to work with. 

1. Add the testbench `tb.vhd` and set it as the simulation top.
2. Run Behavioral Simulation.
3. Inspect waveforms in the Wave window and check detection thresholds trigger correctly, and DAC output matches the expected rearrangement sequence for the specific image being used.  
tb.vhd produces a clock signal of period 10 ns and feeds simulated image data into the design from a text file synchronously with the 'valid' pulse at regular intervals (40 ns). After it has completed sreaming the data from the text file, it produces a trigger signal that enables the readout of the DAC output.
Explicit generic and port mapping of the testbench signals to the design entity is done in the standard way within the uut (Unit under test) instantiation.


## Results / Verification
 
Summarize what's been verified: simulation results against known image test vectors, on-hardware detection accuracy, end-to-end latency from image capture to DAC output, and resource utilization (LUTs, FFs, BRAM, DSP slices) on the Zynq-7010 fabric.
 
## Future Work

-Test with real images from a camera using ADC.

-Could look into faster or more sophisticated rearrangement algorithm. [ATLAS algorithm](https://arxiv.org/html/2511.16303v1)

-Make generics editable on face level rather than within the design vhdl code, via a text file for example. Means we don't have to open vivado every time we make a change. Few ways of doing this, some more complicated than others. [Generics/parameter examples](https://www.doulos.com/knowhow/fpga/settings-genericsparameters-for-synthesis/)
