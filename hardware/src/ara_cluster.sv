// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Navaneeth Kunhi Purayil <nkunhi@student.ethz.ch>
// Description:
// Ara's System, containing Ara instances and Global Units connecting them.

module ara_cluster import ara_pkg::*; #(
    // RVV Parameters
    parameter  int           unsigned NrLanes      = 0,   // Number of parallel vector lanes per Ara instance
    parameter  int           unsigned NrClusters   = 0,   // Number of Ara instances

    // Support for floating-point data types
    parameter  fpu_support_e          FPUSupport   = FPUSupportHalfSingleDouble,
    // External support for vfrec7, vfrsqrt7
    parameter  fpext_support_e        FPExtSupport = FPExtSupportEnable,
    // Support for fixed-point data types
    parameter  fixpt_support_e        FixPtSupport = FixedPointEnable,
    // AXI Interface
    parameter  int           unsigned AxiDataWidth        = 0,
    parameter  int           unsigned AxiAddrWidth        = 0,
    parameter  int           unsigned ClusterAxiDataWidth = 0,
    parameter  int           unsigned NrAxiCuts           = 2,

    parameter  type                   axi_ar_t     = logic,
    parameter  type                   axi_r_t      = logic,
    parameter  type                   axi_aw_t     = logic,
    parameter  type                   axi_w_t      = logic,
    parameter  type                   axi_b_t      = logic,
    parameter  type                   axi_req_t    = logic,
    parameter  type                   axi_resp_t   = logic,

    parameter  type                   cluster_axi_ar_t     = logic,
    parameter  type                   cluster_axi_r_t      = logic,
    parameter  type                   cluster_axi_aw_t     = logic,
    parameter  type                   cluster_axi_w_t      = logic,
    parameter  type                   cluster_axi_b_t      = logic,
    parameter  type                   cluster_axi_req_t    = logic,
    parameter  type                   cluster_axi_resp_t   = logic,
  
    localparam int  unsigned DataWidth = $bits(elen_t),
    localparam type remote_data_t = logic [DataWidth-1:0],

    // Dependant parameters. DO NOT CHANGE!
    // Ara has NrLanes + 3 processing elements: each one of the lanes, the vector load unit, the
    // vector store unit, the slide unit, and the mask unit.
    localparam int           unsigned NrPEs        = NrLanes + 4
  ) (
    // Clock and Reset
    input  logic              clk_i,
    input  logic              rst_ni,
    // Scan chain
    input  logic              scan_enable_i,
    input  logic              scan_data_i,
    output logic              scan_data_o,
    // Interface with Ariane
    input  accelerator_req_t  acc_req_i,
    output accelerator_resp_t acc_resp_o,
    // AXI interface
    output axi_req_t          axi_req_o,
    input  axi_resp_t         axi_resp_i
  );
  accelerator_resp_t [NrClusters-1:0] acc_resp; 

  cluster_axi_req_t      [NrClusters-1:0] ara_axi_req, ara_axi_req_cut;
  cluster_axi_resp_t     [NrClusters-1:0] ara_axi_resp, ara_axi_resp_cut;

  axi_req_t  axi_req_cut, axi_req_align;
  axi_resp_t axi_resp_cut, axi_resp_align;

  // Ring connections
  remote_data_t [NrClusters-1:0] ring_data_l, ring_data_r; 
  logic [NrClusters-1:0] ring_data_l_ready, ring_data_l_valid, ring_data_r_ready, ring_data_r_valid; 

  for (genvar cluster=0; cluster < NrClusters; cluster++) begin : p_cluster 
      ara_macro #(
        .NrLanes           (NrLanes             ), 
        .NrClusters        (NrClusters          ),
        .ClusterId         (cluster             ),
        .FPUSupport        (FPUSupport          ),
        .FPExtSupport      (FPExtSupport        ),
        .FixPtSupport      (FixPtSupport        ),
        .AxiDataWidth      (AxiDataWidth        ),
        .AxiAddrWidth      (AxiAddrWidth        ),
        .ClusterAxiDataWidth (ClusterAxiDataWidth),
        .cluster_axi_ar_t  (cluster_axi_ar_t    ),
        .cluster_axi_r_t   (cluster_axi_r_t     ),
        .cluster_axi_aw_t  (cluster_axi_aw_t    ),
        .cluster_axi_w_t   (cluster_axi_w_t     ),
        .cluster_axi_b_t   (cluster_axi_b_t     ),
        .cluster_axi_req_t (cluster_axi_req_t   ),
        .cluster_axi_resp_t(cluster_axi_resp_t  )
      ) i_ara_macro (
        .clk_i             (clk_i               ),
        .rst_ni            (rst_ni              ),
        .scan_enable_i     (scan_enable_i       ),
        .scan_data_i       (scan_data_i         ),
        .scan_data_o       (/* Unused */        ),

        // Interface with Ariane
        .acc_req_i         (acc_req_i           ),
        .acc_resp_o        (acc_resp[cluster]   ),

        // AXI interface
        .axi_req_o         (ara_axi_req_cut[cluster]   ),
        .axi_resp_i        (ara_axi_resp_cut[cluster]  ),

        // Ring
        .ring_data_r_i       (ring_data_l        [cluster == NrClusters-1 ? 0 : cluster + 1]     ),
        .ring_data_r_valid_i (ring_data_l_valid  [cluster == NrClusters-1 ? 0 : cluster + 1]     ),
        .ring_data_r_ready_o (ring_data_l_ready  [cluster]                                       ), 

        .ring_data_l_i       (ring_data_r        [cluster == 0 ? NrClusters-1 : cluster - 1]     ),
        .ring_data_l_valid_i (ring_data_r_valid  [cluster == 0 ? NrClusters-1 : cluster - 1]     ),
        .ring_data_l_ready_o (ring_data_r_ready  [cluster]                                       ), 

        .ring_data_r_o       (ring_data_r        [cluster]                                       ),
        .ring_data_r_valid_o (ring_data_r_valid  [cluster]                                       ),
        .ring_data_r_ready_i (ring_data_r_ready  [cluster == NrClusters-1 ? 0 : cluster + 1]     ), 

        .ring_data_l_o       (ring_data_l        [cluster]                                       ),
        .ring_data_l_valid_o (ring_data_l_valid  [cluster]                                       ),
        .ring_data_l_ready_i (ring_data_l_ready  [cluster == 0 ? NrClusters-1 : cluster - 1]     ) 
      );
  end

  // Global Ld/St Unit
  global_ldst #(
    .NrLanes            (NrLanes            ),
    .NrClusters         (NrClusters         ),
    .AxiDataWidth       (AxiDataWidth       ),
    .ClusterAxiDataWidth(ClusterAxiDataWidth),
    .AxiAddrWidth       (AxiAddrWidth       ),
    .cluster_axi_req_t  (cluster_axi_req_t  ),
    .cluster_axi_resp_t (cluster_axi_resp_t ),
    .axi_req_t          (axi_req_t          ),
    .axi_resp_t         (axi_resp_t         )
  ) i_global_ldst (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    // To Ara
    .axi_req_i (ara_axi_req_cut  ),
    .axi_resp_o(ara_axi_resp_cut ),
    // To System
    .axi_resp_i(axi_resp_cut),
    .axi_req_o (axi_req_cut)
  );

  // Align stage
  align_stage #(
      .AxiDataWidth(AxiDataWidth),
      .AxiAddrWidth(AxiAddrWidth),
      .axi_ar_t   (axi_ar_t     ),
      .axi_aw_t   (axi_aw_t     ),
      .axi_b_t    (axi_b_t      ),
      .axi_r_t    (axi_r_t      ),
      .axi_w_t    (axi_w_t      ),
      .axi_req_t(axi_req_t), 
      .axi_resp_t(axi_resp_t)
    ) i_align_stage (
      .clk_i (clk_i), 
      .rst_ni(rst_ni), 
      .axi_req_i(axi_req_cut),
      .axi_resp_o(axi_resp_cut),
      .axi_req_o(axi_req_align),
      .axi_resp_i(axi_resp_align)
  );

  axi_cut #(
    .ar_chan_t   (axi_ar_t     ),
    .aw_chan_t   (axi_aw_t     ),
    .b_chan_t    (axi_b_t      ),
    .r_chan_t    (axi_r_t      ),
    .w_chan_t    (axi_w_t      ),
    .axi_req_t   (axi_req_t    ),
    .axi_resp_t  (axi_resp_t   )
  ) i_align_axi_cut (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .slv_req_i   (axi_req_align),
    .slv_resp_o  (axi_resp_align),
    .mst_req_o   (axi_req_o),
    .mst_resp_i  (axi_resp_i)
  );

  assign acc_resp_o = acc_resp[0];

endmodule : ara_cluster
