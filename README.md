# FPGA-quantum-decoder
# Neutral Atom Array Image Processing (Red Pitaya STEMlab 125-14)
 
FPGA-based image processing pipeline for real-time detection, counting, and rearrangement of neutral atoms in an optical tweezer array, implemented on a Red Pitaya STEMlab 125-14 (Xilinx Zynq-7010). The system processes camera image data to locate atoms, uses closed-loop feedback to determine a rearrangement sequence to fill a target grid pattern, and outputs control signals via the onboard DAC to drive the rearrangement hardware (e.g. AOD). Uses ssh terminal to communicate with the board.
 
## Table of Contents
- [Overview](#overview)
- [Repository Structure](#repository-structure)
- [ Block Design](#block-design)
- [ Architecture](#architecture)
- [Getting Started](#getting-started)
- [Constraints](#constraints)
- [Simulation & Testbenches](#simulation--testbenches)
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
  ('FCLK_CLK0') and active-low reset ('FCLK_RESET0_N') to the 
  programmable logic. The '_N' suffix means reset is active when the 
  signal is driven low - keep this consistent throughout or the design 
  will be permanently held in reset.
  
- **AXI GPIO** - dual-channel GPIO used to stream simulated pixel data 
  from a Python script into the FPGA over SSH:
  - Channel 1: 'img_bit_stream' - 14-bit pixel brightness value
  - Channel 2: 'valid' - 1-bit handshake between camera and board, pulses high once per pixel
    
- **my_FPGA** - the custom RTL module containing the full processing pipeline
  
- **AXI SmartConnect** - routes AXI read/write from the PS7's master port to the correct slave (AXI GPIO) based on the configured address map; required whenever a Zynq PS interfaces with AXI peripherals in the PL.
  
- **PROC_SYS_RESET** - synchronises the PS7's asynchronous FCLK_RESET0_N to the 125 MHz fabric clock domain and generates the correctly-polarised reset variants (active-high/active-low) needed by the AXI SmartConnect and AXI GPIO, preventing metastability at the reset input.

 In the ZYNQ7 processing module, double click and Disable DDR, then make Fixed IO external (Vivado deals with this pin itself). Make Trigger, and all the output ports in my_FPGA external.
 
 Once block design is complete, validate design to check no wiring or hardware errors. Then go to the sources tab and right click on the block design and select create HDL wrapper to convert the block diagram into actual verilog code that can be understood by Vivado when implementing the design.
To note: After any further edits to VHDL design, go to block design and refresh module to update. 


 ## Architecture

- **Generics** 
Parameterises the design so the same RTL can be re-targeted to a different experiment without re-writing logic, only re-running synthesis. Key generics include `grid_size` which is the dimension of the atom arrays in number of atoms, image dimensions in pixels, and the brightness threshold used for occupancy detection. Internal signals such as the BRAM/FIFO storage depth are derived from these generics, so changing a parameter and re-generating the bitstream automatically resizes the relevant storage without manual edits.

- **Ports**
Inputs: 'img_bit_stream' (pixel brightness), 'valid' (pixel handshake), 'Trigger' (starts a rearrangement cycle), 'clk', 'reset'.
Outputs: DAC data bus plus the interleaved-mode control signals required by the AD9767 (see datasheet), and status flags 'Q1'–'Q4' marking completion of each FSM stage, used for readout/debug.

- **Slowed clock**
The onboard system clock, 'clk', runs at the 125 MHz, which is too fast for the main body of the rearrangement logic and running these processes on the fast internal clock could break timing requirements. A clock divider generates a 12.5 kHz derived clock which relaxes timing closure on the slower logic.

- **Region of Interest (ROI) processing**
Rather than processing every incoming pixel, this stage restricts detection to the pixel coordinates surrounding the expected lattice sites, discarding background pixels outside those regions. The size and positioning of ROIs are variable generics. Eg 'roi_size =2' creates a 2x2 region of interest surrounding each site. For real images you may want to increase this. 'start_offset_x' & 'start_offset_y' are important for determining the coordinates of the first pixel of the first ROI. The rest of the regions are calculated off of this starting point. This reduces the data volume carried forward into detection/counting and avoids false triggers from stray light outside the trap array.

- **Valid-phase processing**
The valid handshake pulses once per pixel, but the camera's valid signal is asynchronous to the FPGA's internal clock and can stay high for several clock cycles per pixel, latching the same pixel two or three times before valid dropped again. To avoid this, valid is passed through two flip-flops ('valid_1', 'valid_2') and then combined as valid_1 AND NOT valid_2. This produces a new signal, 'valid_phase', that only pulses high for exactly one clock cycle, right on the rising edge of valid. That single pulse is what triggers the BRAM write, guaranteeing each pixel is captured exactly once. ADD DIAGRAM TO SHOW THIS CLEARLY.

- **BRAM read/write**
Incoming pixel data is written onto the chips BRAM at the pixel-stream rate. It's read back out on the slowed 12.5 kHz clock, with a 1-cycle delayed signal, 'img_data_latched_1', used so each pixel lines up correctly with its ROI classification rather than the next pixel's.

- **Main body FSM**
Sequences the pipeline through its stages - image capture, detection/counting, target generation, rearrangement calculation, and DAC output — with the 'Q1'–'Q4' flags exposing which stage is currently active or complete.

- **Detection & counting**
Within the first state, FINDING_1, each pixel inside an ROI is compared against hist_data_h and hist_data_l: above the high threshold registers an atom hit; between the two thresholds flags an ambiguous case without counting it as an atom; below the low threshold is background. Hits are OR-accumulated across all pixels in a site's ROI window (from roi_first_pixel to roi_last_pixel), so a single bright pixel anywhere in the ROI is enough to classify that site as occupied. This makes detection tolerant to the atom not falling exactly on the ROI's centre pixel. The result is stored as roi_results, a grid_size × grid_size array of bits (one per lattice site), and the total atom count (atom_counter) is incremented once per site as the frame scan completes.

- **Creating targets**
'target_grid' is built as a priority-ordered lookup on the total atom count. The highest-count case is checked first, falling through to smaller patterns as count drops, so the achievable target scales automatically with how many atoms were actually loaded that shot. It's the same size as the atom array, initially all zeros, with 1's written in at the site locations that make up the target pattern. The example implemented here is deliberately simple and there's room to build more sophisticated target-selection algorithm.

- **Rearrangement strategy**
The algorithm is a closest-atom fill:
REARRANGE scans the grid from top-left to bottom-right, looking for the first target site that is empty (target_grid = '1', roi_results = '0'). Raster order sets the fill priority: top-left sites are filled first.
Once an empty target site is found, SEARCH_DONOR scans the whole grid for the closest atom to that site, among atoms sitting outside the target pattern. This minimises the distance each atom has to travel, reducing move time and heating/loss risk during transport.
That atom is marked as vacated, and a move command is written into var_fifo: its coordinates, plus the (Δrow, Δcol) needed to bring it to the target site.
The FSM loops back to REARRANGE to find the next empty target site, repeating until every target site is filled or no atoms remain to move. The finished move list is latched into 'fifo_storage' for the execution stage.
This approach isn't globally optimal, but it's cheap in logic/timing and works well for small, sparse grids like this 3×3 prototype.

- **Move output / instruction formatting**
Each move is transmitted as four sequential 8-bit values over two Trigger pulses: donor x-coordinate, donor y-coordinate, then x-displacement, y-displacement (signed). Between values, the FSM enters a DELAY state that holds the output steady for 'output_del' cycles and pulses readout once. This creates a clean, separated step on the output line so each instruction is individually resolvable on a scope. Currently DELAY is quite long.


- **DAC output**
A separate process from the main body that runs on the fast clock. Feeds the computed move sequence into the AOD drive waveform to output the signal needed to steer the optical tweezers. The 8-bit instruction value ('instr_s') is left-shifted into a 14-bit DAC word by padding with six '0's (instr_s & "000000"), scaling the value by 64. This spreads the DAC's usable output range across the full 8-bit instruction space, producing larger voltage steps between adjacent instruction values on the scope/DAC output. The dac_driver process then implements the AD9767's interleaved-mode write timing: it alternates between the 2 output channels (dac_sel) using a fixed sequence (SEL_SETUP → DATA_SETUP → CLK_HI → WRT_HI → BOTH_LO → SWAP_CHAN) to meet the DAC's setup/hold requirements for IQSEL, IQCLK, and IQWRT as specified in the datasheet.[DAC methods - Go to interleaved mode, not dual port](https://www.analog.com/media/en/technical-documentation/data-sheets/AD9763_9765_9767.pdf) or access data sheet via [ANALOG DEVICES AD9767](https://www.analog.com/en/products/AD9767.html)


## Getting Started
 
1. Open Vivado and create a new project targeting xc7z010clg400-1.
2. Add src/my_FPGA.vhd as a design source
3. Add constraints/constraints.xdc as a constraint source
4. Recreate the block design (see above) and generate the HDL wrapper
5. Run Synthesis → Implementation → Generate Bitstream
6. Connect power to the board and switch on. Use ethernet to connect to pc.
7. Wait roughly 20 s then type rp-xxxxxx.local in web address to verify communication between board and pc. Replace xxxxxx with the boards specific ID printed on it.
8. Once web browser loads, transfer .bit file to FPGA. This can be done via SSH over ethernet. Alternative methods can be found [here]().
9. SSH is available natively on Windows (PowerShell / Command Prompt), Mac, and Linux — no additional software required.
10. ```bash
    # From PC terminal, copy bitstream to the board. 
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
- **LED pins** - Connects signals Q_1 to Q_4 within my_FPGA to the onboard LEDs to indicate when certain stages in the FSM are complete. Useful for debugging.
Pin assignments are taken from `Schematics_STEM_125-14_v1.1.pdf` available from Red Pitaya's official documentation (https://redpitaya.readthedocs.io/en/latest/developerGuide/hardware/ORIG_GEN/125-14/top.html#top-125-14) All GPIO pins are LVCMOS33. 






## Simulation & Testbenches
 
Simulation often has max timing it can simulate. Scale down the slowed clock and output_del to ~ 4 and 10 to see logic clearly in waveforms. screenshots  of how waveforms should look during simulation are given in file `docs/`.
 
Can simulate in Vivado by adding testbench in add sources tab or on platforms such as EDA playground which I found easier and faster to work with. 

1. Add the testbench `tb.vhd` and set it as the simulation top.
2. Run Behavioral Simulation.
3. Inspect waveforms in the Wave window and check detection thresholds trigger correctly, and DAC output matches the expected rearrangement sequence for the specific image being used.  
tb.vhd produces a clock signal of period 10 ns and feeds simulated image data into the design from a text file synchronously with the 'valid' pulse at regular intervals (40 ns). After it has completed sreaming the data from the text file, it produces a trigger signal that enables the readout of the DAC output.
Explicit generic and port mapping of the testbench signals to the design entity is done in the standard way within the uut (Unit under test) instantiation.

 
## Future Work

-Test with real images from a camera using ADC.

-Could look into faster or more sophisticated rearrangement algorithm. [ATLAS algorithm](https://arxiv.org/html/2511.16303v1)

-Make generics editable on face level rather than within the design vhdl code, via a text file for example. Means we don't have to open vivado every time we make a change. Few ways of doing this, some more complicated than others. [Generics/parameter examples](https://www.doulos.com/knowhow/fpga/settings-genericsparameters-for-synthesis/)
