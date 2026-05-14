# env/

This folder contains the verification environment components:
the reference model (scoreboard) and the functional coverage model.

Files:
coverage.sv 
ref_model.sv
spi_env_pkg.sv

description :
SPI Verification Environment (SystemVerilog)

This repository implements a self-checking verification environment for an SPI Master design using SystemVerilog.

The environment is built around a cycle-aware reference model that predicts FIFO behavior, SPI transfers, and interrupt generation, enabling automated comparison against DUT responses.

Key Features
Behavioral SPI reference model with:
Configurable CPOL/CPHA modes
Byte/halfword/word transfer support
TX/RX FIFO modeling (depth-aware)
Bit-order handling (MSB/LSB first)
Interrupt and status prediction
Self-checking scoreboard mechanisms:
RX data validation against predicted model
MOSI signal verification
Register read-back checking
Status and IRQ correctness validation
Functional coverage collection:
Mode and width coverage
FIFO utilization states
Interrupt activation tracking
Delay and loopback scenarios
Data pattern coverage for corner-case stimulation
Package-based modular architecture for reuse across testcases

The environment is designed to separate stimulus generation, golden reference prediction, and coverage closure to ensure scalable verification of SPI protocol behavior under constrained and stress conditions.

//later
//later  the reference model  register Shadowing: It maintains a local copy of all configuration registers (CTRL, CLK_DIV, etc.) to verify that the APB interface correctly writes and reads back settings.
FIFO Emulation: It models the behavior of the dual 8-deep FIFOs, including specific hardware rules like discarding data on overflow and ignoring writes when the controller is disabled.
Data Transformation: It mathematically replicates the SPI engine's logic, specifically:
Width Masking,Bit Reversal,Loopback Logic,Status & Interrupt Prediction
How It Works (The Verification Flow)
Stimulus: When the testbench writes data to the DUT, it simultaneously "pushes" that data into the Reference Model.
Transformation: While the hardware is shifting bits on the SPI bus, the Reference Model performs the same transformation in zero-time.
Judgment: The Scoreboard compares the actual output from the hardware (observed by the Monitor) against the "Golden Prediction" from this model. If they don't match, a [SCOREBOARD_ERROR] is flagged.
