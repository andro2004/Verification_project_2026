// =============================================================================
// spi_core_sva.sv
// -----------------------------------------------------------------------------
// SystemVerilog Assertions bound to u_core module in the SPI Master DUT.
// =============================================================================

`ifndef SPI_CORE_SVA_SV
`define SPI_CORE_SVA_SV

module spi_core_sva (
    input logic clk, rst_n,
    input logic sclk, mosi, cpol, cpha,
    input logic [3:0] ss_n,
    // Internal taps from the DUT clock generator
    input logic [16:0] sclk_cnt,
    input logic        sclk_phase,
    input logic [15:0] cfg_clk_div,
    
    input wire  BUSY, 
    input logic [5:0] width // width in bits (8, 16, 32)
);

    // =========================================================================
    // Internal strobe derivation (mirrors RTL counter logic)
    // =========================================================================
    wire leading_strobe  = (sclk_cnt == cfg_clk_div) && (sclk_phase == 1'b0);
    wire trailing_strobe = (sclk_cnt == cfg_clk_div) && (sclk_phase == 1'b1);

    // CPHA=0: sample on leading edge; CPHA=1: sample on trailing edge
    wire sample_edge = (cpha == 1'b0) ? leading_strobe : trailing_strobe;

    // =========================================================================
    // Actual SCLK edge detection (for xfer_length counting)
    // =========================================================================
    // The strobe derivation above (sample_edge) is based on sclk_cnt/sclk_phase
    // which may continue running during the DELAY phase even though SCLK is
    // held at its idle level. This causes "phantom" sample edges that corrupt
    // the transfer length counter. To avoid this, we detect actual SCLK
    // transitions on the output pin for counting purposes.
    //
    // Sample edge polarity per SPI mode:
    //   Mode 0 (CPOL=0,CPHA=0): sample on rising  → cpol==cpha → rising
    //   Mode 1 (CPOL=0,CPHA=1): sample on falling  → cpol!=cpha → falling
    //   Mode 2 (CPOL=1,CPHA=0): sample on falling  → cpol!=cpha → falling
    //   Mode 3 (CPOL=1,CPHA=1): sample on rising   → cpol==cpha → rising

    logic sclk_d;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) sclk_d <= 1'b0;
        else        sclk_d <= sclk;
    end

    wire sclk_rose = (sclk == 1'b1) && (sclk_d == 1'b0);
    wire sclk_fell = (sclk == 1'b0) && (sclk_d == 1'b1);

    // Real sample edge: based on actual SCLK transitions. During DELAY, SCLK
    // is held at idle (per spec §4.2), so no transitions occur and this signal
    // stays 0 — naturally filtering out phantom strobes.
    wire real_sample_edge = BUSY && ((cpol == cpha) ? sclk_rose : sclk_fell);

    // =========================================================================
    // a_sclk_idle (Req R4)
    // =========================================================================
    // OBSERVED ISSUE: Per spec R4, "SCLK idle polarity matches CPOL before,
    //   between, and after transfers." When BUSY=0, SCLK should equal CPOL.
    //
    //   This assertion fires in the following scenarios:
    //
    //   - After transfers in Modes 1/2/3, SCLK does not return to the expected
    //     CPOL idle level (e.g. SCLK=1 when CPOL=0 after a Mode 1 transfer).
    //     This may indicate a DUT bug in the SCLK generation/idle logic.
    //
    //   - After reset, SCLK is HIGH while CPOL=0 (spec §7.1 says SCLK should
    //     be driven to CPOL=0 idle level on reset). This may indicate a DUT
    //     reset sequencing issue.
    //
    //   - When tests switch CPOL between sub-tests by writing CTRL, there is
    //     a brief window where idle_cnt is already large from the previous idle
    //     but SCLK hasn't adapted to the new CPOL yet. This could be a DUT
    //     settling delay or an assertion timing artifact.
    //
    //   The assertion includes a grace period (idle_cnt > cfg_clk_div+1) which
    //   is WEAKER than what the spec literally requires, yet it still fires.
    //   Whether this is a DUT bug or an expected settling behavior depends on
    //   the RTL implementation. The assertion is LEFT AS-IS to flag the issue.

    logic [16:0] idle_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || BUSY)
            idle_cnt <= 17'd0;
        else if (idle_cnt <= cfg_clk_div + 17'd2)
            idle_cnt <= idle_cnt + 17'd1;
    end

    property spi_idle_clock;
        @(posedge clk) disable iff (!rst_n)
        (!BUSY && (idle_cnt > cfg_clk_div + 17'd1)) |-> (sclk == cpol);
    endproperty
    a_sclk_idle: assert property(spi_idle_clock)
        else $error("[ASSERTION_ERROR] a_sclk_idle SCLK idle level mismatch! SCLK=%b, CPOL=%b", sclk, cpol);

    // =========================================================================
    // a_mosi_stable (Req R5)
    // =========================================================================
    // KNOWN ISSUE: At DIV=0 (SCLK = PCLK/2, a valid configuration per R24),
    //   launch and sample edges fall on adjacent PCLK cycles. The $stable(mosi)
    //   check compares MOSI on the sample edge to its value one PCLK earlier —
    //   which is the launch edge where MOSI legitimately changes. The guard
    //   `!$past(launch_edge)` is intended to suppress this, but the strobe
    //   derivation from sclk_cnt/sclk_phase may not perfectly align with the
    //   RTL's actual internal strobe at DIV=0, causing false fires.
    //
    //   The spec (R5) says "MOSI is stable across the sample edge" and §10.2
    //   says "stable for at least 1 PCLK around each sample edge." At DIV=0,
    //   MOSI is stable for exactly 1 PCLK (the sample cycle itself) — the
    //   minimum the spec allows. Whether the DUT meets this at DIV=0 requires
    //   waveform-level investigation.
    //
    //   This assertion is LEFT AS-IS; fires at DIV=0 may be false positives
    //   from strobe derivation skew, or genuine DUT issues. Both are documented.

    wire launch_edge = (cpha == 1'b0) ? trailing_strobe : leading_strobe;

    property spi_mosi_stable;
        @(posedge clk) disable iff (!rst_n)
        (BUSY && sample_edge && !$past(launch_edge)) |-> $stable(mosi);
    endproperty
    a_mosi_stable: assert property(spi_mosi_stable)
        else $error("[ASSERTION_ERROR] a_mosi_stable MOSI unstable on sample edge!");

    // =========================================================================
    // a_ss_stable (Req R20, §4.2)
    // =========================================================================
    // Spec §4.2: "SS_n MUST remain asserted for the full transfer (first launch
    //   edge through BUSY deassertion). The IP never toggles SS_n autonomously."
    //
    // This assertion correctly encodes the spec requirement. It fires during:
    //   - error_injection_test: intentional mid-transfer SS_n manipulation
    //     (the test exercises error handling — assertion proves the violation
    //     is detected and the DUT or test is responsible)
    //   - clk_div_corner_test: test timeout forces SS_n deassert while BUSY=1
    //     (test's wait_idle is too short for large DIV values)
    //
    // The assertion is NOT disabled during these tests. The fires prove the
    // assertion works — it catches real spec violations regardless of whether
    // they are caused by the DUT or the testbench stimulus.
    property spi_ss_held_low;
        @(posedge clk) disable iff (!rst_n)
        (BUSY && $past(BUSY)) |-> $stable(ss_n);
    endproperty
    a_ss_stable: assert property(spi_ss_held_low)
        else $error("[ASSERTION_ERROR] a_ss_stable SS_n glitch/deassert during active transfer! SS_n=%b", ss_n);

    // =========================================================================
    // a_xfer_length (Req R7)
    // =========================================================================
    // Spec R7: "A transfer lasts exactly WIDTH SCLK cycles; BUSY=1 throughout
    //   and deasserts one PCLK after the last sample edge."
    //
    // Design: Count REAL SCLK sample-edge transitions (real_sample_edge) per
    //   individual word transfer. Using actual SCLK pin transitions instead of
    //   the internal strobe derivation (sample_edge) avoids phantom counts
    //   during the DELAY phase — when DELAY > 0, BUSY stays 1 between words
    //   (spec R21) but SCLK is held at idle (no transitions).
    //
    // The counter resets at word boundaries (when count reaches WIDTH) so it
    //   works correctly for multi-word bursts.
    //
    // NOTE: This assertion will still fire when transfers are forcefully
    //   aborted (e.g., test timeout deasserts SS_n mid-transfer, or mid-
    //   transfer CLK_DIV writes cause undefined behavior per spec §8.3).
    //   Those fires are expected and indicate test/stimulus issues.

    logic [5:0] pulse_cnt;
    logic [5:0] pulse_cnt_save;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || !BUSY)
            pulse_cnt <= 6'd0;
        else if (real_sample_edge) begin
            if (pulse_cnt + 6'd1 == width)
                pulse_cnt <= 6'd0;      // reset at word boundary for burst
            else
                pulse_cnt <= pulse_cnt + 6'd1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pulse_cnt_save <= 6'd0;
        else if ($rose(BUSY))
            pulse_cnt_save <= 6'd0;
        else if (BUSY && real_sample_edge && (pulse_cnt + 6'd1 == width))
            pulse_cnt_save <= width;    // full word completed
        else if (BUSY && real_sample_edge)
            pulse_cnt_save <= pulse_cnt + 6'd1;
    end

    property a_xfer_length_dynamic;
        @(posedge clk) disable iff (!rst_n)
        $fell(BUSY) |-> (pulse_cnt_save == width);
    endproperty
    a_xfer_length: assert property(a_xfer_length_dynamic)
        else $error("[ASSERTION_ERROR] a_xfer_length Transfer length mismatch! Expected %0d, got %0d", width, pulse_cnt_save);

endmodule

`endif // SPI_CORE_SVA_SV
