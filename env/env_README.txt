# env/

This folder contains the verification environment components:
the reference model (scoreboard) and the functional coverage model.

Files:

//later  the reference model  register Shadowing: It maintains a local copy of all configuration registers (CTRL, CLK_DIV, etc.) to verify that the APB interface correctly writes and reads back settings.
FIFO Emulation: It models the behavior of the dual 8-deep FIFOs, including specific hardware rules like discarding data on overflow and ignoring writes when the controller is disabled.
Data Transformation: It mathematically replicates the SPI engine's logic, specifically:
Width Masking,Bit Reversal,Loopback Logic,Status & Interrupt Prediction
How It Works (The Verification Flow)
Stimulus: When the testbench writes data to the DUT, it simultaneously "pushes" that data into the Reference Model.
Transformation: While the hardware is shifting bits on the SPI bus, the Reference Model performs the same transformation in zero-time.
Judgment: The Scoreboard compares the actual output from the hardware (observed by the Monitor) against the "Golden Prediction" from this model. If they don't match, a [SCOREBOARD_ERROR] is flagged.
