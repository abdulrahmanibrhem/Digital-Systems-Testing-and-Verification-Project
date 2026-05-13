# Digital-Systems-Testing-and-Verification-Project
Final project starter kit for Digital Design Verification (Ain Shams University, Spring 2026) — verify an SPI Master Controller using SystemVerilog constrained-random testbenches, functional coverage, and SVA. UVM optional.

# SPI Master Controller — Verification Final Project

**Ain Shams University · Digital Design Verification · Spring 2026**

## Overview

This project is a complete verification environment for a production-style **SPI Master Controller** IP, built as a final project for the Digital Design Verification course. The goal is to develop a SystemVerilog testbench that can reliably detect functional bugs in the DUT (Device Under Test) across its full configuration space.

The DUT implements a full-featured SPI master with an APB register interface, TX/RX FIFOs, interrupt logic, and support for all four SPI modes — closely modeled after register layouts found in ARM-based microcontrollers.

## What This Repo Contains

| Directory | Description |
|-----------|-------------|
| `docs/` | SPI Master specification PDF + grading interface reference |
| `golden_rtl/` | Reference RTL: `spi_master.sv`, `spi_core.sv`, `apb_regfile.sv` |
| `harness/` | Fixed verification harness (interfaces, DUT wrapper, Makefile template) |
| `harness/examples/sv_only/` | Ready-to-use SV-only scaffold with BFMs, scoreboard, coverage, and assertions |

## Verification Goals

- Drive APB register writes/reads to configure and control the DUT
- Model SPI slave behavior on the MISO/MOSI/SCLK/SS_n lines
- Implement a **scoreboard** that predicts correct behavior and flags `[SCOREBOARD_ERROR]` on mismatches
- Achieve ≥ 85% **functional coverage** across:
  - 4 SPI modes × {MSB/LSB-first} × {8, 16, 32}-bit transfers
  - Range of `CLK_DIV` and `DELAY` values
  - All interrupt sources
- Write at least **5 SystemVerilog Assertions (SVA)** bound to the DUT

## Methodology

- **Constrained-random stimulus** (mandatory)
- **Functional coverage** (mandatory)
- **SVA** (mandatory)
- **UVM** (optional, +10 bonus points)
- **UVM RAL** (optional, +5 bonus points)

## Scoring

| Category | Points |
|----------|-------:|
| Mandatory tests pass | 10 |
| Functional coverage ≥ 85% | 15 |
| SVA assertions | 5 |
| Bugs caught (target: 20 of 28) | 60 |
| Report & test plan | 10 |
| UVM bonus | +10 |
| UVM RAL bonus | +5 |

## Tools

- **Simulator:** QuestaSim (or compatible; update `Makefile` for other simulators)
- **Language:** SystemVerilog (UVM optional)

## Getting Started

```bash
# 1. Copy the SV-only scaffold into your submission directory
cp -r harness/examples/sv_only/ my_submission/

# 2. Compile and run a single test against golden RTL
make run TEST=sanity_test SEED=1

# 3. Run full regression (default: 10 tests × 20 seeds)
make regress

# 4. Generate coverage report
make cov
```

Read `docs/SPI_Master_Spec.pdf` and `harness/grading_interface.md` before writing any testbench code.
