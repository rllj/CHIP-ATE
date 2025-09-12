# CHIP-ATE

A small CHIP-8 interpreter I've been working on after being inspired by [isakbjugn](https://github.com/isakbjugn)'s [talk](https://vimeo.com/1115577320]).

Tested using [Timendus' tremendous test suite](https://github.com/Timendus/chip8-test-suite)

Currently passes all relevant tests for the original CHIP-8 except sound and clipping.

## Build

To build CHIP-ATE, simply run 
```bash
zig build -Doptimize=Release[Fast|Safe] # Use either "Fast" or "Safe"
``` 
The resulting binary can be found in `zig-out/bin/chip-ate`.

## Usage
To load and run a ROM, simply pass the path to the ROM to the executable.
```bash
chip-ate ./path/to/ROM.ch8
```
A nice collection of ROMs can be found here: https://github.com/kripod/chip8-roms
