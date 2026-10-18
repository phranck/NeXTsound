#!/usr/bin/env python3
"""Reject ELF load segments or entry points outside RP2350 SRAM."""

import re
import subprocess
import sys

SRAM_START = 0x20000000
SRAM_END = 0x20082000

if len(sys.argv) != 3:
    raise SystemExit("Usage: check-ram-elf.py READELF ELF")

headers = subprocess.check_output([sys.argv[1], "-lW", sys.argv[2]], text=True)
entry_match = re.search(r"Entry point (0x[0-9a-fA-F]+)", headers)
if entry_match is None:
    raise SystemExit("ELF has no entry point")
entry = int(entry_match[1], 16) & ~1
loaded_ranges = []
for line in headers.splitlines():
    fields = line.split()
    if not fields or fields[0] != "LOAD":
        continue
    virtual, physical, file_bytes, memory_bytes = (int(fields[index], 16) for index in (2, 3, 4, 5))
    if virtual != physical or not SRAM_START <= physical <= physical + max(file_bytes, memory_bytes) <= SRAM_END:
        raise SystemExit(f"ELF load segment is not SRAM-only: {line.strip()}")
    loaded_ranges.append((physical, physical + file_bytes))
if not any(start <= entry < end for start, end in loaded_ranges):
    raise SystemExit("ELF entry point is outside its SRAM load data")
print(f"SRAM-only ELF: {len(loaded_ranges)} load segments; entry {entry:#010x}")
