`timescale 1ns / 1ps

module ddr3drv(
	axi4.SLAVE ddr3if,
	FPGADeviceClocks.DEFAULT clocks,
	FPGADeviceWires.DEFAULT wires,
	output wire calib_done,
	output wire ui_clk );

wire ui_clk_sync_rst;

mig_7series_0 DDR3Instance (
    // Memory interface ports
    .ddr3_addr                      (wires.ddr3_addr),
    .ddr3_ba                        (wires.ddr3_ba),
    .ddr3_cas_n                     (wires.ddr3_cas_n),
    .ddr3_ck_n                      (wires.ddr3_ck_n),
    .ddr3_ck_p                      (wires.ddr3_ck_p),
    .ddr3_cke                       (wires.ddr3_cke),
    .ddr3_ras_n                     (wires.ddr3_ras_n),
    .ddr3_reset_n                   (wires.ddr3_reset_n),
    .ddr3_we_n                      (wires.ddr3_we_n),
    .ddr3_dq                        (wires.ddr3_dq),
    .ddr3_dqs_n                     (wires.ddr3_dqs_n),
    .ddr3_dqs_p                     (wires.ddr3_dqs_p),
    .ddr3_dm                        (wires.ddr3_dm),
    .ddr3_odt                       (wires.ddr3_odt),

    // Application interface ports
    .ui_clk                         (ui_clk),          // Feeds back into axi4if.ACLK to drive the entire bus
    .ui_clk_sync_rst                (ui_clk_sync_rst),
    .init_calib_complete            (calib_done),
    .device_temp					(), // Unused

    .mmcm_locked                    (), // Unused
    .aresetn                        (ddr3if.ARESETn),

    .app_sr_req                     (1'b0), // Unused
    .app_ref_req                    (1'b0), // Unused
    .app_zq_req                     (1'b0), // Unused
    .app_sr_active                  (), // Unused
    .app_ref_ack                    (), // Unused
    .app_zq_ack                     (), // Unused

    // Slave Interface Write Address Ports
    .s_axi_awid                     (4'h0),
    .s_axi_awaddr                   (ddr3if.AWADDR[28:0]),
    .s_axi_awlen                    (8'h07),  // 8 transfers
    .s_axi_awsize                   (3'b010), // 4 bytes each
    .s_axi_awburst                  (2'b01),  // 00:FIXED 01:INCR 10:WRAP 11:RESERVED
    .s_axi_awlock                   (1'b0),
    .s_axi_awcache                  (4'h0),
    .s_axi_awprot                   (3'b000),
    .s_axi_awqos                    (4'h0),
    .s_axi_awvalid                  (ddr3if.AWVALID),
    .s_axi_awready                  (ddr3if.AWREADY),

    // Slave Interface Write Data Ports
    .s_axi_wdata                    (ddr3if.WDATA),
    .s_axi_wstrb                    (ddr3if.WSTRB),
    .s_axi_wlast                    (ddr3if.WLAST),
    .s_axi_wvalid                   (ddr3if.WVALID),
    .s_axi_wready                   (ddr3if.WREADY),

    // Slave Interface Write Response Ports
    .s_axi_bid                      (), // Unused
    .s_axi_bresp                    (ddr3if.BRESP),
    .s_axi_bvalid                   (ddr3if.BVALID),
    .s_axi_bready                   (ddr3if.BREADY),

    // Slave Interface Read Address Ports
    .s_axi_arid                     (4'h0),
    .s_axi_araddr                   (ddr3if.ARADDR[28:0]),
    .s_axi_arlen                    (8'h07),  // 8 transfers
    .s_axi_arsize                   (3'b010), // 4 bytes each
    .s_axi_arburst                  (2'b01),  // 00:FIXED 01:INCR 10:WRAP 11:RESERVED
    .s_axi_arlock                   (1'b0),
    .s_axi_arcache                  (4'h0),
    .s_axi_arprot                   (3'b000),
    .s_axi_arqos                    (4'h0),
    .s_axi_arvalid                  (ddr3if.ARVALID),
    .s_axi_arready                  (ddr3if.ARREADY),

    // Slave Interface Read Data Ports
    .s_axi_rid                      (), // Unused
    .s_axi_rdata                    (ddr3if.RDATA),
    .s_axi_rresp                    (ddr3if.RRESP),
    .s_axi_rlast                    (ddr3if.RLAST),
    .s_axi_rvalid                   (ddr3if.RVALID),
    .s_axi_rready                   (ddr3if.RREADY),
    // System Clock Ports
    .sys_clk_i                      (clocks.clk_sys_i), // 100MHz
    // Reference Clock Ports
    .clk_ref_i                      (clocks.clk_ref_i), // 200MHz
    .sys_rst                        (ddr3if.ARESETn) );

endmodule
