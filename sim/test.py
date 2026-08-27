import time
from pynq import MMIO

-----------------------------------------------------------------------------------------------------------------------------------
#if pynq library not found, comment out line 2 and replace with the following:

import mmap
import struct
import os

class MMIO:
  def __init__(self,base_addr,length):
    self._mem_fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
    self._mem = mmap.mmap(self._mem_fd, length, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=base_addr)

  def write(self, offset, value):
    self._mem[offset:offset + 4] = struct.pack("<I", value & 0xFFFFFFFF)

  def close(self):
    self._mem.close()
    os.close(self._mem_fd)
-------------------------------------------------------------------------------------------------------------------------------------------

AXI_GPIO_BASE = 0x41200000

DATA_OFFSET = 0x0000
VALID_OFFSET = 0x0008

PIXEL_PERIOD_S = 8e-4

gpio =MMIO(AXI_GPIO_BASE, 0x10000)

pixels = []
with open("myfile.txt") as f:
  for line in f:
    line = line.strip()
    if line:
      pixels.append(int(line,2))

for px in pixels:
  gpio.write(DATA_OFFSET, px)
  gpio.write(VALID_OFFSET,1)
  time.sleep(PIXEL_PERIOD_S / 2)
  gpio.write(VALID_OFFSET,0)
  time.sleep(PIXEL_PERIOD_S / 2)

print("Done.")
    
