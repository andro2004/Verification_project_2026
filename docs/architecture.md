# SPI Master Architectural Context

## The RTL Split (`apb_regfile` vs `spi_core`)
The DUT is structured as a thin top-level module (`spi_master`) that instantiates two clearly bounded sub-blocks (per Section 2 of the spec). This separation of concerns is a crucial digital design pattern:

- **`apb_regfile` (The Bus Domain):** The "brain" of the system. It isolates the standard AMBA bus protocol from the custom SPI logic. It contains the APB slave logic, all 9 registers, IRQ aggregation, and the TX/RX FIFOs. If this IP were moved to an AXI4-Lite bus, only this file would change.
- **`spi_core` (The Protocol Domain):** The "muscle" of the system. It knows nothing about APB; it only takes stable commands from the register block. It contains the Shift FSM (IDLE/SHIFT/DELAY), SCLK divider, bit-ordering logic, and loopback mux. This keeps the timing-critical state machine clean and focused solely on the SPI protocol.

Keep this separation in mind when performing verification or writing assertions. Properties must be logically bound to the specific domain they verify.

## SVA Wrapper Implementation & Signal Tapping
To cleanly map to the RTL structure, the assertion environment works via a top-level wrapper:

1. **Top-Level Wrapper (`spi_sva.sv`)**: This is the top-level wrapper module. It is bound exactly once in the main testbench (`tb_top.sv`).
2. **Sub-Modules**: `spi_sva.sv` dynamically instantiates both **`spi_regfile_sva.sv`** and **`spi_core_sva.sv`** internally. This mirrors the RTL structure.
3. **Signal Tapping (Crucial Task)**: The ports currently defined in the skeleton files are intentionally incomplete. When writing mandatory assertions, engineers must identify which internal signals from the DUT are needed (e.g., FIFO pointers, FSM state machines). They must then:
   - Add these signals as ports to the respective sub-modules.
   - Route them up through the `spi_sva` wrapper ports.
   - Update the `bind` statement in `tb_top.sv` to correctly tap and route these signals from the deep design layers into the SVA wrapper.