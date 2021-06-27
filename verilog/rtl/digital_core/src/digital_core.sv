//////////////////////////////////////////////////////////////////////
////                                                              ////
////  Digital core                                                ////
////                                                              ////
////  This file is part of the YIFive cores project               ////
////  http://www.opencores.org/cores/yifive/                      ////
////                                                              ////
////  Description                                                 ////
////      This is digital core and integrate all the main block   ////
////      here.  Following block are integrated here              ////
////      1. Risc V Core                                          ////
////      2. SPI Master                                           ////
////      3. Wishbone Cross Bar                                   ////
////                                                              ////
////  To Do:                                                      ////
////    nothing                                                   ////
////                                                              ////
////  Author(s):                                                  ////
////      - Dinesh Annayya, dinesha@opencores.org                 ////
////                                                              ////
////  Revision :                                                  ////
////    0.1 - 16th Feb 2021, Dinesh A                             ////
////          Initial integration with Risc-V core +              ////
////          Wishbone Cross Bar + SPI  Master                    ////
////    0.2 - 17th June 2021, Dinesh A                            ////
////        1. In risc core, wishbone and core domain is          ////
////           created                                            ////
////        2. cpu and rtc clock are generated in glbl reg block  ////
////        3. in wishbone interconnect:- Stagging flop are added ////
////           at interface to break wishbone timing path         ////
////        4. buswidth warning are fixed inside spi_master       ////
////        modified rtl files are                                ////
////           verilog/rtl/digital_core/src/digital_core.sv       ////
////           verilog/rtl/digital_core/src/glbl_cfg.sv           ////
////           verilog/rtl/lib/wb_stagging.sv                     ////
////           verilog/rtl/syntacore/scr1/src/top/scr1_dmem_wb.sv ////
////           verilog/rtl/syntacore/scr1/src/top/scr1_imem_wb.sv ////
////           verilog/rtl/syntacore/scr1/src/top/scr1_top_wb.sv  ////
////           verilog/rtl/user_project_wrapper.v                 ////
////           verilog/rtl/wb_interconnect/src/wb_interconnect.sv ////
////           verilog/rtl/spi_master/src/spim_clkgen.sv          ////
////           verilog/rtl/spi_master/src/spim_ctrl.sv            ////
////    0.3 - 20th June 2021, Dinesh A                            ////
////           1. uart core is integrated                         ////
////           2. 3rd Slave ported added to wishbone interconnect ////
////    0.4 - 25th June 2021, Dinesh A                            ////
////          Moved the pad logic inside sdram,spi,uart block to  ////
////          avoid logic at digital core level                   ////
////    0.5 - 25th June 2021, Dinesh A                            ////
////          Since carvel gives only 16MB address space for user ////
////          space, we have implemented indirect address select  ////
////          with 8 bit bank select given inside wb_host         ////
////          core Address = {Bank_Sel[7:0], Wb_Address[23:0]     ////
////          caravel user address space is                       ////
////          0x3000_0000 to 0x30FF_FFFF                          ////
////    0.6 - 27th June 2021, Dinesh A                            ////
////          Digital core level tie are moved inside IP to avoid ////
////          power hook up at core level                         ////
////          u_risc_top - test_mode & test_rst_n                 ////
////          u_intercon - s*_wbd_err_i                           ////
////          unused wb_cti_i is removed from u_sdram_ctrl        ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
////                                                              ////
//// Copyright (C) 2000 Authors and OPENCORES.ORG                 ////
////                                                              ////
//// This source file may be used and distributed without         ////
//// restriction provided that this copyright statement is not    ////
//// removed from the file and that any derivative work contains  ////
//// the original copyright notice and the associated disclaimer. ////
////                                                              ////
//// This source file is free software; you can redistribute it   ////
//// and/or modify it under the terms of the GNU Lesser General   ////
//// Public License as published by the Free Software Foundation; ////
//// either version 2.1 of the License, or (at your option) any   ////
//// later version.                                               ////
////                                                              ////
//// This source is distributed in the hope that it will be       ////
//// useful, but WITHOUT ANY WARRANTY; without even the implied   ////
//// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      ////
//// PURPOSE.  See the GNU Lesser General Public License for more ////
//// details.                                                     ////
////                                                              ////
//// You should have received a copy of the GNU Lesser General    ////
//// Public License along with this source; if not, download it   ////
//// from http://www.opencores.org/lgpl.shtml                     ////
////                                                              ////
//////////////////////////////////////////////////////////////////////


module digital_core 
#(
	parameter      SDR_DW   = 8,  // SDR Data Width 
        parameter      SDR_BW   = 1,  // SDR Byte Width
	parameter      WB_WIDTH = 32  // WB ADDRESS/DARA WIDTH
 ) (
`ifdef USE_POWER_PINS
    inout vccd1,	// User area 1 1.8V supply
    inout vssd1,	// User area 1 digital ground
`endif
    input   wire                       wb_clk_i        ,  // System clock
    input   wire                       user_clock2     ,  // user Clock
    input   wire                       wb_rst_i        ,  // Regular Reset signal

    input   wire                       wbd_ext_cyc_i   ,  // strobe/request
    input   wire                       wbd_ext_stb_i   ,  // strobe/request
    input   wire [WB_WIDTH-1:0]        wbd_ext_adr_i   ,  // address
    input   wire                       wbd_ext_we_i    ,  // write
    input   wire [WB_WIDTH-1:0]        wbd_ext_dat_i   ,  // data output
    input   wire [3:0]                 wbd_ext_sel_i   ,  // byte enable
    output  wire [WB_WIDTH-1:0]        wbd_ext_dat_o   ,  // data input
    output  wire                       wbd_ext_ack_o   ,  // acknowlegement

 
    // Logic Analyzer Signals
    input  wire [127:0]                la_data_in      ,
    output wire [127:0]                la_data_out     ,
    input  wire [127:0]                la_oenb         ,
 

    // IOs
    input  wire  [37:0]                io_in           ,
    output wire  [37:0]                io_out          ,
    output wire  [37:0]                io_oeb          ,

    output wire  [2:0]                 user_irq             

);

//---------------------------------------------------
// Local Parameter Declaration
// --------------------------------------------------


//---------------------------------------------------------------------
// Wishbone Risc V Instruction Memory Interface
//---------------------------------------------------------------------
wire                           wbd_riscv_imem_stb_i; // strobe/request
wire   [WB_WIDTH-1:0]          wbd_riscv_imem_adr_i; // address
wire                           wbd_riscv_imem_we_i;  // write
wire   [WB_WIDTH-1:0]          wbd_riscv_imem_dat_i; // data output
wire   [3:0]                   wbd_riscv_imem_sel_i; // byte enable
wire   [WB_WIDTH-1:0]          wbd_riscv_imem_dat_o; // data input
wire                           wbd_riscv_imem_ack_o; // acknowlegement
wire                           wbd_riscv_imem_err_o;  // error

//---------------------------------------------------------------------
// RISC V Wishbone Data Memory Interface
//---------------------------------------------------------------------
wire                           wbd_riscv_dmem_stb_i; // strobe/request
wire   [WB_WIDTH-1:0]          wbd_riscv_dmem_adr_i; // address
wire                           wbd_riscv_dmem_we_i;  // write
wire   [WB_WIDTH-1:0]          wbd_riscv_dmem_dat_i; // data output
wire   [3:0]                   wbd_riscv_dmem_sel_i; // byte enable
wire   [WB_WIDTH-1:0]          wbd_riscv_dmem_dat_o; // data input
wire                           wbd_riscv_dmem_ack_o; // acknowlegement
wire                           wbd_riscv_dmem_err_o; // error

//---------------------------------------------------------------------
// WB HOST Interface
//---------------------------------------------------------------------
wire                           wbd_int_cyc_i; // strobe/request
wire                           wbd_int_stb_i; // strobe/request
wire   [WB_WIDTH-1:0]          wbd_int_adr_i; // address
wire                           wbd_int_we_i;  // write
wire   [WB_WIDTH-1:0]          wbd_int_dat_i; // data output
wire   [3:0]                   wbd_int_sel_i; // byte enable
wire   [WB_WIDTH-1:0]          wbd_int_dat_o; // data input
wire                           wbd_int_ack_o; // acknowlegement
wire                           wbd_int_err_o; // error
//---------------------------------------------------------------------
//    SPI Master Wishbone Interface
//---------------------------------------------------------------------
wire                           wbd_spim_stb_o; // strobe/request
wire   [WB_WIDTH-1:0]          wbd_spim_adr_o; // address
wire                           wbd_spim_we_o;  // write
wire   [WB_WIDTH-1:0]          wbd_spim_dat_o; // data output
wire   [3:0]                   wbd_spim_sel_o; // byte enable
wire                           wbd_spim_cyc_o ;
wire   [WB_WIDTH-1:0]          wbd_spim_dat_i; // data input
wire                           wbd_spim_ack_i; // acknowlegement
wire                           wbd_spim_err_i;  // error

//---------------------------------------------------------------------
//    SPI Master Wishbone Interface
//---------------------------------------------------------------------
wire                           wbd_sdram_stb_o ;
wire [WB_WIDTH-1:0]            wbd_sdram_adr_o ;
wire                           wbd_sdram_we_o  ; // 1 - Write, 0 - Read
wire [WB_WIDTH-1:0]            wbd_sdram_dat_o ;
wire [WB_WIDTH/8-1:0]          wbd_sdram_sel_o ; // Byte enable
wire                           wbd_sdram_cyc_o ;
wire  [2:0]                    wbd_sdram_cti_o ;
wire  [WB_WIDTH-1:0]           wbd_sdram_dat_i ;
wire                           wbd_sdram_ack_i ;

//---------------------------------------------------------------------
//    Global Register Wishbone Interface
//---------------------------------------------------------------------
wire                           wbd_glbl_stb_o; // strobe/request
wire   [7:0]                   wbd_glbl_adr_o; // address
wire                           wbd_glbl_we_o;  // write
wire   [WB_WIDTH-1:0]          wbd_glbl_dat_o; // data output
wire   [3:0]                   wbd_glbl_sel_o; // byte enable
wire                           wbd_glbl_cyc_o ;
wire   [WB_WIDTH-1:0]          wbd_glbl_dat_i; // data input
wire                           wbd_glbl_ack_i; // acknowlegement
wire                           wbd_glbl_err_i;  // error

//---------------------------------------------------------------------
//    Global Register Wishbone Interface
//---------------------------------------------------------------------
wire                           wbd_uart_stb_o; // strobe/request
wire   [7:0]                   wbd_uart_adr_o; // address
wire                           wbd_uart_we_o;  // write
wire   [7:0]                   wbd_uart_dat_o; // data output
wire                           wbd_uart_sel_o; // byte enable
wire                           wbd_uart_cyc_o ;
wire   [7:0]                   wbd_uart_dat_i; // data input
wire                           wbd_uart_ack_i; // acknowlegement
wire                           wbd_uart_err_i;  // error

//----------------------------------------------------
//  CPU Configuration
//----------------------------------------------------
wire                              cpu_rst_n     ;
wire                              spi_rst_n     ;
wire                              sdram_rst_n   ;
wire                              sdram_clk           ;
wire                              cpu_clk       ;
wire                              rtc_clk       ;
wire                              wbd_clk_int   ;
wire                              wbd_int_rst_n ;

wire [31:0]                       fuse_mhartid  ;
wire [15:0]                       irq_lines     ;
wire                              soft_irq      ;

wire [7:0]                        cfg_glb_ctrl  ;
wire [31:0]                       cfg_clk_ctrl1 ;
wire [31:0]                       cfg_clk_ctrl2 ;

//------------------------------------------------
// Configuration Parameter
//------------------------------------------------
wire [1:0]                        cfg_sdr_width       ; // 2'b00 - 32 Bit SDR, 2'b01 - 16 Bit SDR, 2'b1x - 8 Bit
wire [1:0]                        cfg_colbits         ; // 2'b00 - 8 Bit column address, 
wire                              sdr_init_done       ; // Indicate SDRAM Initialisation Done
wire [3:0] 		          cfg_sdr_tras_d      ; // Active to precharge delay
wire [3:0]                        cfg_sdr_trp_d       ; // Precharge to active delay
wire [3:0]                        cfg_sdr_trcd_d      ; // Active to R/W delay
wire 			          cfg_sdr_en          ; // Enable SDRAM controller
wire [1:0] 		          cfg_req_depth       ; // Maximum Request accepted by SDRAM controller
wire [12:0] 		          cfg_sdr_mode_reg    ;
wire [2:0] 		          cfg_sdr_cas         ; // SDRAM CAS Latency
wire [3:0] 		          cfg_sdr_trcar_d     ; // Auto-refresh period
wire [3:0]                        cfg_sdr_twr_d       ; // Write recovery delay
wire [11: 0]                      cfg_sdr_rfsh        ;
wire [2 : 0]                      cfg_sdr_rfmax       ;





/////////////////////////////////////////////////////////
// Generating acive low wishbone reset                 
// //////////////////////////////////////////////////////
assign wbd_int_rst_n = cfg_glb_ctrl[0];
assign cpu_rst_n     = cfg_glb_ctrl[1];
assign spi_rst_n     = cfg_glb_ctrl[2];
assign sdram_rst_n   = cfg_glb_ctrl[3];



wb_host u_wb_host(

    // Master Port
       .wbm_rst_i        (wb_rst_i             ),  
       .wbm_clk_i        (wb_clk_i             ),  
       .wbm_cyc_i        (wbd_ext_cyc_i        ),  
       .wbm_stb_i        (wbd_ext_stb_i        ),  
       .wbm_adr_i        (wbd_ext_adr_i        ),  
       .wbm_we_i         (wbd_ext_we_i         ),  
       .wbm_dat_i        (wbd_ext_dat_i        ),  
       .wbm_sel_i        (wbd_ext_sel_i        ),  
       .wbm_dat_o        (wbd_ext_dat_o        ),  
       .wbm_ack_o        (wbd_ext_ack_o        ),  
       .wbm_err_o        (                     ),  

    // Slave Port
       .wbs_clk_i        (wbd_clk_int          ),  
       .wbs_cyc_o        (wbd_int_cyc_i        ),  
       .wbs_stb_o        (wbd_int_stb_i        ),  
       .wbs_adr_o        (wbd_int_adr_i        ),  
       .wbs_we_o         (wbd_int_we_i         ),  
       .wbs_dat_o        (wbd_int_dat_i        ),  
       .wbs_sel_o        (wbd_int_sel_i        ),  
       .wbs_dat_i        (wbd_int_dat_o        ),  
       .wbs_ack_i        (wbd_int_ack_o        ),  
       .wbs_err_i        (wbd_int_err_o        ),  

       .cfg_glb_ctrl     (cfg_glb_ctrl         ),
       .cfg_clk_ctrl1    (cfg_clk_ctrl1        ),
       .cfg_clk_ctrl2    (cfg_clk_ctrl2        ),

    // Logic Analyzer Signals
       .la_data_in       (la_data_in           ),
       .la_data_out      (la_data_out          ),
       .la_oenb          (la_oenb              )
    );




//------------------------------------------------------------------------------
// RISC V Core instance
//------------------------------------------------------------------------------
scr1_top_wb u_riscv_top (
    // Reset
    .pwrup_rst_n            (wbd_int_rst_n             ),
    .rst_n                  (wbd_int_rst_n             ),
    .cpu_rst_n              (cpu_rst_n                 ),

    // Clock
    .core_clk               (cpu_clk                   ),
    .rtc_clk                (rtc_clk                   ),

    // Fuses
    .fuse_mhartid           (fuse_mhartid              ),

    // IRQ
    .irq_lines              (irq_lines                 ), 
    .soft_irq               (soft_irq                  ), // TODO - Interrupts

    // DFT
    // .test_mode           (1'b0                      ), // Moved inside IP
    // .test_rst_n          (1'b1                      ), // Moved inside IP

    
    .wb_rst_n               (wbd_int_rst_n              ),
    .wb_clk                 (wbd_clk_int               ),
    // Instruction memory interface
    .wbd_imem_stb_o         (wbd_riscv_imem_stb_i      ),
    .wbd_imem_adr_o         (wbd_riscv_imem_adr_i      ),
    .wbd_imem_we_o          (wbd_riscv_imem_we_i       ), 
    .wbd_imem_dat_o         (wbd_riscv_imem_dat_i      ),
    .wbd_imem_sel_o         (wbd_riscv_imem_sel_i      ),
    .wbd_imem_dat_i         (wbd_riscv_imem_dat_o      ),
    .wbd_imem_ack_i         (wbd_riscv_imem_ack_o      ),
    .wbd_imem_err_i         (wbd_riscv_imem_err_o      ),

    // Data memory interface
    .wbd_dmem_stb_o         (wbd_riscv_dmem_stb_i      ),
    .wbd_dmem_adr_o         (wbd_riscv_dmem_adr_i      ),
    .wbd_dmem_we_o          (wbd_riscv_dmem_we_i       ), 
    .wbd_dmem_dat_o         (wbd_riscv_dmem_dat_i      ),
    .wbd_dmem_sel_o         (wbd_riscv_dmem_sel_i      ),
    .wbd_dmem_dat_i         (wbd_riscv_dmem_dat_o      ),
    .wbd_dmem_ack_i         (wbd_riscv_dmem_ack_o      ),
    .wbd_dmem_err_i         (wbd_riscv_dmem_err_o      ) 
);

/*********************************************************
* SPI Master
* This is an implementation of an SPI master that is controlled via an AXI bus. 
* It has FIFOs for transmitting and receiving data. 
* It supports both the normal SPI mode and QPI mode with 4 data lines.
* *******************************************************/

spim_top
#(
`ifndef SYNTHESIS
    .WB_WIDTH  (WB_WIDTH)
`endif
) u_spi_master
(
    .mclk                   (wbd_clk_int               ),
    .rst_n                  (spi_rst_n                 ),

    .wbd_stb_i              (wbd_spim_stb_o            ),
    .wbd_adr_i              (wbd_spim_adr_o            ),
    .wbd_we_i               (wbd_spim_we_o             ), 
    .wbd_dat_i              (wbd_spim_dat_o            ),
    .wbd_sel_i              (wbd_spim_sel_o            ),
    .wbd_dat_o              (wbd_spim_dat_i            ),
    .wbd_ack_o              (wbd_spim_ack_i            ),
    .wbd_err_o              (wbd_spim_err_i            ),

    .events_o               (                          ), // TODO - Need to connect to intr ?

    // Pad Interface
    .io_in                  (io_in[35:30]              ),
    .io_out                 (io_out[35:30]             ),
    .io_oeb                 (io_oeb[35:30]             )

);


sdrc_top  
    `ifndef SYNTHESIS
    #(.APP_AW(WB_WIDTH), 
	    .APP_DW(WB_WIDTH), 
	    .APP_BW(4),
	    .SDR_DW(8), 
	    .SDR_BW(1))
      `endif
     u_sdram_ctrl (
    .cfg_sdr_width          (cfg_sdr_width              ),
    .cfg_colbits            (cfg_colbits                ),
                    
    // WB bus
    .wb_rst_n               (wbd_int_rst_n              ),
    .wb_clk_i               (wbd_clk_int                ),
    
    .wb_stb_i               (wbd_sdram_stb_o            ),
    .wb_addr_i              (wbd_sdram_adr_o            ),
    .wb_we_i                (wbd_sdram_we_o             ),
    .wb_dat_i               (wbd_sdram_dat_o            ),
    .wb_sel_i               (wbd_sdram_sel_o            ),
    .wb_cyc_i               (wbd_sdram_cyc_o            ),
    .wb_ack_o               (wbd_sdram_ack_i            ),
    .wb_dat_o               (wbd_sdram_dat_i            ),

		
    /* Interface to SDRAMs */
    .sdram_clk              (sdram_clk                 ),
    .sdram_resetn           (sdram_rst_n               ),

    /** Pad Interface       **/
    .io_in                  (io_in[29:0]               ),
    .io_oeb                 (io_oeb[29:0]              ),
    .io_out                 (io_out[29:0]              ),
                    
    /* Parameters */
    .sdr_init_done          (sdr_init_done             ),
    .cfg_req_depth          (cfg_req_depth             ), //how many req. buffer should hold
    .cfg_sdr_en             (cfg_sdr_en                ),
    .cfg_sdr_mode_reg       (cfg_sdr_mode_reg          ),
    .cfg_sdr_tras_d         (cfg_sdr_tras_d            ),
    .cfg_sdr_trp_d          (cfg_sdr_trp_d             ),
    .cfg_sdr_trcd_d         (cfg_sdr_trcd_d            ),
    .cfg_sdr_cas            (cfg_sdr_cas               ),
    .cfg_sdr_trcar_d        (cfg_sdr_trcar_d           ),
    .cfg_sdr_twr_d          (cfg_sdr_twr_d             ),
    .cfg_sdr_rfsh           (cfg_sdr_rfsh              ),
    .cfg_sdr_rfmax          (cfg_sdr_rfmax             )
   );


wb_interconnect  u_intercon (
         .clk_i         (wbd_clk_int           ), 
         .rst_n         (wbd_int_rst_n         ),
         
         // Master 0 Interface
         .m0_wbd_dat_i  (wbd_riscv_imem_dat_i  ),
         .m0_wbd_adr_i  (wbd_riscv_imem_adr_i  ),
         .m0_wbd_sel_i  (wbd_riscv_imem_sel_i  ),
         .m0_wbd_we_i   (wbd_riscv_imem_we_i   ),
         .m0_wbd_cyc_i  (wbd_riscv_imem_stb_i  ),
         .m0_wbd_stb_i  (wbd_riscv_imem_stb_i  ),
         .m0_wbd_dat_o  (wbd_riscv_imem_dat_o  ),
         .m0_wbd_ack_o  (wbd_riscv_imem_ack_o  ),
         .m0_wbd_err_o  (wbd_riscv_imem_err_o  ),
         
         // Master 1 Interface
         .m1_wbd_dat_i  (wbd_riscv_dmem_dat_i  ),
         .m1_wbd_adr_i  (wbd_riscv_dmem_adr_i  ),
         .m1_wbd_sel_i  (wbd_riscv_dmem_sel_i  ),
         .m1_wbd_we_i   (wbd_riscv_dmem_we_i   ),
         .m1_wbd_cyc_i  (wbd_riscv_dmem_stb_i  ),
         .m1_wbd_stb_i  (wbd_riscv_dmem_stb_i  ),
         .m1_wbd_dat_o  (wbd_riscv_dmem_dat_o  ),
         .m1_wbd_ack_o  (wbd_riscv_dmem_ack_o  ),
         .m1_wbd_err_o  (wbd_riscv_dmem_err_o  ),
         
         // Master 2 Interface
         .m2_wbd_dat_i  (wbd_int_dat_i  ),
         .m2_wbd_adr_i  (wbd_int_adr_i  ),
         .m2_wbd_sel_i  (wbd_int_sel_i  ),
         .m2_wbd_we_i   (wbd_int_we_i   ),
         .m2_wbd_cyc_i  (wbd_int_cyc_i  ),
         .m2_wbd_stb_i  (wbd_int_stb_i  ),
         .m2_wbd_dat_o  (wbd_int_dat_o  ),
         .m2_wbd_ack_o  (wbd_int_ack_o  ),
         .m2_wbd_err_o  (wbd_int_err_o  ),
         
         
         // Slave 0 Interface
         // .s0_wbd_err_i  (1'b0           ), - Moved inside IP
         .s0_wbd_dat_i  (wbd_spim_dat_i ),
         .s0_wbd_ack_i  (wbd_spim_ack_i ),
         .s0_wbd_dat_o  (wbd_spim_dat_o ),
         .s0_wbd_adr_o  (wbd_spim_adr_o ),
         .s0_wbd_sel_o  (wbd_spim_sel_o ),
         .s0_wbd_we_o   (wbd_spim_we_o  ),  
         .s0_wbd_cyc_o  (wbd_spim_cyc_o ),
         .s0_wbd_stb_o  (wbd_spim_stb_o ),
         
         // Slave 1 Interface
         // .s1_wbd_err_i  (1'b0           ), - Moved inside IP
         .s1_wbd_dat_i  (wbd_sdram_dat_i ),
         .s1_wbd_ack_i  (wbd_sdram_ack_i ),
         .s1_wbd_dat_o  (wbd_sdram_dat_o ),
         .s1_wbd_adr_o  (wbd_sdram_adr_o ),
         .s1_wbd_sel_o  (wbd_sdram_sel_o ),
         .s1_wbd_we_o   (wbd_sdram_we_o  ),  
         .s1_wbd_cyc_o  (wbd_sdram_cyc_o ),
         .s1_wbd_stb_o  (wbd_sdram_stb_o ),
         
         // Slave 2 Interface
         // .s2_wbd_err_i  (1'b0           ), - Moved inside IP
         .s2_wbd_dat_i  (wbd_glbl_dat_i ),
         .s2_wbd_ack_i  (wbd_glbl_ack_i ),
         .s2_wbd_dat_o  (wbd_glbl_dat_o ),
         .s2_wbd_adr_o  (wbd_glbl_adr_o ),
         .s2_wbd_sel_o  (wbd_glbl_sel_o ),
         .s2_wbd_we_o   (wbd_glbl_we_o  ),  
         .s2_wbd_cyc_o  (wbd_glbl_cyc_o ),
         .s2_wbd_stb_o  (wbd_glbl_stb_o ),

         // Slave 3 Interface
         // .s3_wbd_err_i  (1'b0           ), - Moved inside IP
         .s3_wbd_dat_i  (wbd_uart_dat_i ),
         .s3_wbd_ack_i  (wbd_uart_ack_i ),
         .s3_wbd_dat_o  (wbd_uart_dat_o ),
         .s3_wbd_adr_o  (wbd_uart_adr_o ),
         .s3_wbd_sel_o  (wbd_uart_sel_o ),
         .s3_wbd_we_o   (wbd_uart_we_o  ),  
         .s3_wbd_cyc_o  (wbd_uart_cyc_o ),
         .s3_wbd_stb_o  (wbd_uart_stb_o )
	);

glbl_cfg   u_glbl_cfg (

       .mclk                   (wbd_clk_int               ),
       .reset_n                (wbd_int_rst_n             ),
       .user_clock2            (user_clock2               ),
       .device_idcode          (                          ),

        // Reg Bus Interface Signal
       .reg_cs                 (wbd_glbl_stb_o            ),
       .reg_wr                 (wbd_glbl_we_o             ),
       .reg_addr               (wbd_glbl_adr_o            ),
       .reg_wdata              (wbd_glbl_dat_o            ),
       .reg_be                 (wbd_glbl_sel_o            ),

       // Outputs
       .reg_rdata              (wbd_glbl_dat_i            ),
       .reg_ack                (wbd_glbl_ack_i            ),

       // SDRAM Clock

       .sdram_clk              (sdram_clk                 ),
       .cpu_clk                (cpu_clk                   ),
       .rtc_clk                (rtc_clk                   ),

       // Risc configuration
       .fuse_mhartid           (fuse_mhartid              ),
       .irq_lines              (irq_lines                 ), 
       .soft_irq               (soft_irq                  ),
       .user_irq               (user_irq                  ),

       // SDRAM Config
       .cfg_sdr_width          (cfg_sdr_width             ),
       .cfg_colbits            (cfg_colbits               ),

	/* Parameters */
       .sdr_init_done          (sdr_init_done             ),
       .cfg_req_depth          (cfg_req_depth             ), //how many req. buffer should hold
       .cfg_sdr_en             (cfg_sdr_en                ),
       .cfg_sdr_mode_reg       (cfg_sdr_mode_reg          ),
       .cfg_sdr_tras_d         (cfg_sdr_tras_d            ),
       .cfg_sdr_trp_d          (cfg_sdr_trp_d             ),
       .cfg_sdr_trcd_d         (cfg_sdr_trcd_d            ),
       .cfg_sdr_cas            (cfg_sdr_cas               ),
       .cfg_sdr_trcar_d        (cfg_sdr_trcar_d           ),
       .cfg_sdr_twr_d          (cfg_sdr_twr_d             ),
       .cfg_sdr_rfsh           (cfg_sdr_rfsh              ),
       .cfg_sdr_rfmax          (cfg_sdr_rfmax             )


        );

uart_core   u_uart_core (
        .arst_n                 (wbd_int_rst_n            ), // async reset
        .app_clk                (wbd_clk_int              ),

        // Reg Bus Interface Signal
       .reg_cs                 (wbd_uart_stb_o            ),
       .reg_wr                 (wbd_uart_we_o             ),
       .reg_addr               (wbd_uart_adr_o[5:2]       ),
       .reg_wdata              (wbd_uart_dat_o[7:0]       ),
       .reg_be                 (wbd_uart_sel_o            ),

       // Outputs
       .reg_rdata              (wbd_uart_dat_i[7:0]       ),
       .reg_ack                (wbd_uart_ack_i            ),

       // Pad interface
       .io_in                  (io_in [37:36]              ),
       .io_oeb                 (io_oeb[37:36]              ),
       .io_out                 (io_out[37:36]              )

     );


endmodule : digital_core
