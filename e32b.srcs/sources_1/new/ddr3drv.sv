`timescale 1ns / 1ps

module ddr3drv(
	axi4wide.slave ddr3if,
	fpgadeviceclocks.def clocks,
	fpgadevicewires.def wires,
	output wire calib_done,
	output wire ui_clk );

wire ui_clk_sync_rst;

mig_7series_0 ddr3instance (
    // memory interface ports
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

    // application interface ports
    .ui_clk                         (ui_clk),          // feeds back into axi4if.aclk to drive the entire bus
    .ui_clk_sync_rst                (ui_clk_sync_rst),
    .init_calib_complete            (calib_done),
    .device_temp					(), // unused

    .mmcm_locked                    (), // unused
    .aresetn                        (ddr3if.aresetn),

    .app_sr_req                     (1'b0), // unused
    .app_ref_req                    (1'b0), // unused
    .app_zq_req                     (1'b0), // unused
    .app_sr_active                  (), // unused
    .app_ref_ack                    (), // unused
    .app_zq_ack                     (), // unused

    // slave interface write address ports
    .s_axi_awid                     (4'h0),
    .s_axi_awaddr                   (ddr3if.awaddr[28:0]),
    .s_axi_awlen                    (8'h03),  // 4 transfers
    .s_axi_awsize                   (3'b011), // 8 bytes each
    .s_axi_awburst                  (2'b01),  // 00:fixed 01:incr 10:wrap 11:reserved
    .s_axi_awlock                   (1'b0),
    .s_axi_awcache                  (4'b0011),
    .s_axi_awprot                   (3'b000),
    .s_axi_awqos                    (4'h0),
    .s_axi_awvalid                  (ddr3if.awvalid),
    .s_axi_awready                  (ddr3if.awready),

    // slave interface write data ports
    .s_axi_wdata                    (ddr3if.wdata),
    .s_axi_wstrb                    (ddr3if.wstrb),
    .s_axi_wlast                    (ddr3if.wlast),
    .s_axi_wvalid                   (ddr3if.wvalid),
    .s_axi_wready                   (ddr3if.wready),

    // slave interface write response ports
    .s_axi_bid                      (), // unused
    .s_axi_bresp                    (ddr3if.bresp),
    .s_axi_bvalid                   (ddr3if.bvalid),
    .s_axi_bready                   (ddr3if.bready),

    // slave interface read address ports
    .s_axi_arid                     (4'h0),
    .s_axi_araddr                   (ddr3if.araddr[28:0]),
    .s_axi_arlen                    (8'h03),  // 4 transfers
    .s_axi_arsize                   (3'b011), // 8 bytes each
    .s_axi_arburst                  (2'b01),  // 00:fixed 01:incr 10:wrap 11:reserved
    .s_axi_arlock                   (1'b0),
    .s_axi_arcache                  (4'b0011),
    .s_axi_arprot                   (3'b000),
    .s_axi_arqos                    (4'h0),
    .s_axi_arvalid                  (ddr3if.arvalid),
    .s_axi_arready                  (ddr3if.arready),

    // slave interface read data ports
    .s_axi_rid                      (), // unused
    .s_axi_rdata                    (ddr3if.rdata),
    .s_axi_rresp                    (ddr3if.rresp),
    .s_axi_rlast                    (ddr3if.rlast),
    .s_axi_rvalid                   (ddr3if.rvalid),
    .s_axi_rready                   (ddr3if.rready),
    // system clock ports
    .sys_clk_i                      (clocks.clk_sys_i), // 100mhz
    // reference clock ports
    .clk_ref_i                      (clocks.clk_ref_i), // 200mhz
    .sys_rst                        (ddr3if.aresetn) );

endmodule
