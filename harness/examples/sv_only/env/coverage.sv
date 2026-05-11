// =============================================================================
// coverage.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// Minimal functional-coverage collector built on covergroups. Students must
// extend this to hit the 85% functional-coverage gate in the grading rubric.
// =============================================================================

`ifndef SPI_COVERAGE_COL_SV
`define SPI_COVERAGE_COL_SV

class spi_coverage_col;

    bit [1:0] cv_mode;
    bit       cv_lsb_first;
    bit [1:0] cv_width;
 bit        cv_loopback; 
bit [15:0] cv_div;
    
    int cv_tx_occ;
    int cv_rx_occ;

    bit [7:0] cv_delay;
  bit [4:0]  cv_int_stat;              // for cg_interrupt
    bit [4:0]  cv_int_en;                // for cg_interrupt
    bit [3:0]  cv_ss_n;            // for cg_ss
    bit [7:0]  cv_reg_addr;              // for cg_register
    bit        cv_reg_is_write;          // for cg_register


    covergroup cg_config;
        option.per_instance = 1;
        cp_mode : coverpoint cv_mode  {
            bins modes[] = {[0:3]};
        }
        cp_first : coverpoint cv_lsb_first {
            bins msb_first = {0};
            bins lsb_first = {1};
        }
        cp_width : coverpoint cv_width {
            bins w8  = {2'b00};
            bins w16 = {2'b01};
            bins w32 = {2'b10};
 	    illegal_bins reserved = {2'b11};  // R23: illegal encoding
        }
        cx_mode_width : cross cp_mode, cp_width;

        cp_loopback : coverpoint cv_loopback {
        bins loopback_off = {0};
        bins loopback_on  = {1};
    }
    // The 24 mandatory cross bins
    cx_mode_width_order : cross cp_mode, cp_width, cp_first;
    // Bonus: loopback on/off per mode (satisfies cg_loopback in the plan)
    cx_loopback_mode    : cross cp_loopback, cp_mode;
    endgroup


    covergroup cg_clkdiv;
        // TODO: Create explicit bins for DIV values: 0, 1, 2, 3, 255, 1024, 65535.
        // Also add a random covering bin over the full range [0:65535].
        option.per_instance = 1;

        cp_div : coverpoint cv_div {
            bins div_0 = {0};
            bins div_1 = {1};
            bins div_2 = {2};
            bins div_3 = {3};
            bins div_255 = {255};
            bins div_1024 = {1024};
            bins div_65535 = {65535};

            bins div_other = default;
        }
    endgroup


    covergroup cg_fifo;
        // TODO: Create occupancy bins for both TX and RX.
        // Each FIFO should have bins for: empty (0), 1, mid (4), 7, and full (8).
        // Total of 10 bins across the two FIFOs.
        option.per_instance = 1;

        cp_tx_occ : coverpoint cv_tx_occ {
            bins tx_empty = {0};
            bins tx_one = {1};
            bins tx_mid = {4};
            bins tx_near_full = {7};
            bins tx_full = {8};
        }

        cp_rx_occ : coverpoint cv_rx_occ {
            bins rx_empty = {0};
            bins rx_one = {1};
            bins rx_mid = {4};
            bins rx_near_full = {7};
            bins rx_full = {8};
        }
    endgroup


    covergroup cg_delay;
        // TODO: Create bins for inter-transfer delay values: 0, 1, and one large value (>= 128).
        option.per_instance = 1;

        cp_delay : coverpoint cv_delay {
            bins delay_0 = {0}; 
            bins delay_1 = {1};
            bins delay_large = {[128:$]};
        }
    endgroup


    covergroup cg_interrupt;
        // TODO: Create 32 combination bins for the 5 interrupt sources.
    
        option.per_instance = 1;

        // All 32 combinations of the 5 INT_STAT bits
        cp_int_stat : coverpoint cv_int_stat {
            bins all_clear    = {5'b00000};
            bins tx_empty     = {5'b00001};
            bins rx_full      = {5'b00010};
            bins tx_ovf       = {5'b00100};
            bins rx_ovf       = {5'b01000};
            bins xfer_done    = {5'b10000};
            bins multiple     = {[5'b00011 : 5'b11111]};  // any combo of 2+
            bins all_set      = {5'b11111};
        }

        // Masked vs unmasked — covers the "asserted while masked" scenario (R17)

        cp_int_en : coverpoint cv_int_en {
            bins all_masked   = {5'b00000};
            bins all_enabled  = {5'b11111};
            bins partial      = {[5'b00001 : 5'b11110]};
        }

        // Cross: which sources are firing AND what is masked
        cx_stat_en : cross cp_int_stat, cp_int_en;

            // For each interrupt source, cover: asserted, cleared (W1C), and asserted-while-masked (INT_EN=0).
    endgroup



    covergroup cg_ss;
        // TODO: Create bins to cover all slave select patterns.
        // Include: each individual SS_n lane asserted alone, and multi-slave scenarios.

        option.per_instance = 1;
        cp_ss : coverpoint cv_ss_n {
            bins ss0_only  = {4'b0001};   // lane 0 alone
            bins ss1_only  = {4'b0010};   // lane 1 alone
            bins ss2_only  = {4'b0100};   // lane 2 alone
            bins ss3_only  = {4'b1000};   // lane 3 alone
            bins multi_ss  = {[4'b0011 : 4'b1111]};  // any 2+ lanes
            bins none      = {4'b0000};   // all deasserted LOOPBACK test 
        }
    endgroup
   




    covergroup cg_register;
        // TODO: Create bins for all 9 registers (0x00, 0x04, 0x08, 0x0C, 0x10, 0x14, 0x18, 0x1C, 0x20).
        //Also cover reserved offsets (0x24+).
            
        option.per_instance = 1;
        cp_addr : coverpoint cv_reg_addr {
            bins ctrl     = {8'h00};
            bins status   = {8'h04};
            bins tx_data  = {8'h08};
            bins rx_data  = {8'h0C};
            bins clk_div  = {8'h10};
            bins ss_ctrl  = {8'h14};
            bins int_en   = {8'h18};
            bins int_stat = {8'h1C};
            bins delay    = {8'h20};
            bins reserved = {[8'h24 : 8'hFF]};  // R22/R23
        }

        //  For each register, track read vs. write operations.

        cp_rw : coverpoint cv_reg_is_write {
            bins read  = {0};
            bins write = {1};
        }

        // Every register exercised in both read and write direction

        cx_addr_rw : cross cp_addr, cp_rw;
     
    endgroup



    function new();
        cg_config    = new();
        cg_clkdiv    = new();
        cg_fifo      = new();
        cg_delay     = new();
        cg_interrupt = new();
        cg_ss        = new();
        cg_register  = new();
    endfunction


   function void sample_clkdiv(bit [15:0] div);
        // TODO: Sample cg_clkdiv with the DIV value
        cv_div = div;
        cg_clkdiv.sample();
    endfunction

    function void sample_fifo(int tx_occ, int rx_occ);
        // TODO: Sample cg_fifo with TX and RX occupancy values
        cv_tx_occ = tx_occ;
        cv_rx_occ = rx_occ;
        cg_fifo.sample();
    endfunction

    function void sample_delay(bit [7:0] delay);
        // TODO: Sample cg_delay with the delay value
        cv_delay = delay;
        cg_delay.sample();
    endfunction


    function void sample_interrupt(bit [4:0] int_stat, bit [4:0] int_en);
        cv_int_stat = int_stat;
        cv_int_en   = int_en;
        cg_interrupt.sample();
    endfunction


    function void sample_ss(bit [3:0] ss_pattern);
        cv_ss_n = ss_pattern;
        cg_ss.sample();
    endfunction


    function void sample_register(bit [7:0] addr, bit is_write);
        cv_reg_addr     = addr;
        cv_reg_is_write = is_write;
        cg_register.sample();
    endfunction


	function void sample_config(bit [1:0] mode, bit [1:0] width,
    	                        bit lsb_first, bit loopback);
  	  cv_mode      = mode;
  	  cv_lsb_first = lsb_first;
   	 cv_width     = width;
  	  cv_loopback  = loopback;
  	  cg_config.sample();
	endfunction












endclass

`endif // SPI_COVERAGE_COL_SV


