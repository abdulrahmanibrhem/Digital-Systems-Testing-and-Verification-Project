# tb/

This folder contains the top-level testbench and Bus Functional Models (BFMs).
These modules drive stimulus into the DUT through the provided interfaces.

Files:
apb_master_bfm.sv
spi_slave_bfm.sv
//later

description: 

APB Master BFM

A configurable AMBA APB master Bus Functional Model (BFM) for verification environments.
Implements complete APB read/write transaction handling with wait-state support, burst access, register-level helper tasks, transaction verification, timeout monitoring, and DUT control utilities.
Designed for scalable SoC/IP verification with reusable high-level APIs for register configuration, FIFO access, interrupt handling, and protocol-driven stimulus generation.

SPI Slave BFM

A mode-aware SPI slave Bus Functional Model (BFM) supporting all four SPI modes (CPOL/CPHA combinations).
Implements accurate edge-based MOSI sampling and MISO driving behavior, transfer tracking, configurable response loading, and bidirectional shift-register operation.
Suitable for validating SPI master controllers under different timing modes, synchronization conditions, and protocol corner cases in advanced verification environments.
