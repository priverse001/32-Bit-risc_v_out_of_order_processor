`timescale 1ns / 1ps

module tb_top;

    reg clk;
    reg rst_n;
    
    wire [31:0] debug_reg_val;
    reg [4:0] debug_reg_idx;
    
    // AXI Instruction fetch interface
    wire [31:0] m_axi_i_araddr; wire m_axi_i_arvalid; wire m_axi_i_arready;
    wire [31:0] m_axi_i_rdata_w; reg [1:0] m_axi_i_rresp; reg m_axi_i_rvalid; wire m_axi_i_rready;
    
    // AXI Data interface
    wire [31:0] m_axi_d_awaddr; wire m_axi_d_awvalid; reg m_axi_d_awready;
    wire [31:0] m_axi_d_wdata; wire [3:0] m_axi_d_wstrb; wire m_axi_d_wvalid; reg m_axi_d_wready;
    reg [1:0] m_axi_d_bresp; reg m_axi_d_bvalid; wire m_axi_d_bready;
    wire [31:0] m_axi_d_araddr; wire m_axi_d_arvalid; reg m_axi_d_arready;
    reg [31:0] m_axi_d_rdata; reg [1:0] m_axi_d_rresp; reg m_axi_d_rvalid; wire m_axi_d_rready;
    
    // Use SAME clock for both core and AXI to eliminate CDC timing issues
    top u_top (
        .core_clk(clk), .core_rst_n(rst_n),
        .axi_clk(clk), .axi_rst_n(rst_n),
        .debug_reg_idx(debug_reg_idx), .debug_reg_val(debug_reg_val),
        
        // Instruction AXI
        .m_axi_i_araddr(m_axi_i_araddr), .m_axi_i_arvalid(m_axi_i_arvalid), .m_axi_i_arready(m_axi_i_arready),
        .m_axi_i_rdata(m_axi_i_rdata_w), .m_axi_i_rresp(m_axi_i_rresp), .m_axi_i_rvalid(m_axi_i_rvalid), .m_axi_i_rready(m_axi_i_rready),
        .m_axi_i_awready(1'b0), .m_axi_i_wready(1'b0), .m_axi_i_bvalid(1'b0), .m_axi_i_bresp(2'b0),
        
        // Data AXI
        .m_axi_d_awaddr(m_axi_d_awaddr), .m_axi_d_awvalid(m_axi_d_awvalid), .m_axi_d_awready(m_axi_d_awready),
        .m_axi_d_wdata(m_axi_d_wdata), .m_axi_d_wstrb(m_axi_d_wstrb), .m_axi_d_wvalid(m_axi_d_wvalid), .m_axi_d_wready(m_axi_d_wready),
        .m_axi_d_bresp(m_axi_d_bresp), .m_axi_d_bvalid(m_axi_d_bvalid), .m_axi_d_bready(m_axi_d_bready),
        .m_axi_d_araddr(m_axi_d_araddr), .m_axi_d_arvalid(m_axi_d_arvalid), .m_axi_d_arready(m_axi_d_arready),
        .m_axi_d_rdata(m_axi_d_rdata), .m_axi_d_rresp(m_axi_d_rresp), .m_axi_d_rvalid(m_axi_d_rvalid), .m_axi_d_rready(m_axi_d_rready)
    );

    // Single Clock: 100 MHz
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Mock Unified Memory
    reg [31:0] memory [0:1023];
    
    // Instruction AXI Slave (combinational arready, 1-cycle rdata)
    assign m_axi_i_arready = m_axi_i_arvalid; // Instant address accept
    
    reg [31:0] i_rdata_reg;
    assign m_axi_i_rdata_w = i_rdata_reg;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_i_rvalid <= 0;
            i_rdata_reg <= 0;
            m_axi_i_rresp <= 0;
        end else begin
            if (m_axi_i_arvalid && m_axi_i_arready) begin
                m_axi_i_rvalid <= 1;
                i_rdata_reg <= memory[m_axi_i_araddr[11:2]];
                m_axi_i_rresp <= 2'b00;
            end else if (m_axi_i_rvalid && m_axi_i_rready) begin
                m_axi_i_rvalid <= 0;
            end
        end
    end
    
    // Data AXI Slave (Read + Write)
    reg [31:0] d_awaddr_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_d_awready <= 0;
            m_axi_d_wready <= 0;
            m_axi_d_bvalid <= 0;
            m_axi_d_bresp <= 0;
            m_axi_d_arready <= 0;
            m_axi_d_rvalid <= 0;
            m_axi_d_rdata <= 0;
            m_axi_d_rresp <= 0;
        end else begin
            // --- Write ---
            if (m_axi_d_awvalid && !m_axi_d_awready) begin
                m_axi_d_awready <= 1;
                d_awaddr_reg <= m_axi_d_awaddr;
            end else begin
                m_axi_d_awready <= 0;
            end
            
            if (m_axi_d_wvalid && !m_axi_d_wready) begin
                m_axi_d_wready <= 1;
            end else begin
                m_axi_d_wready <= 0;
            end
            
            if (m_axi_d_wvalid && m_axi_d_wready) begin
                memory[d_awaddr_reg[11:2]] <= m_axi_d_wdata;
                m_axi_d_bvalid <= 1;
                m_axi_d_bresp <= 2'b00;
            end else if (m_axi_d_bvalid && m_axi_d_bready) begin
                m_axi_d_bvalid <= 0;
            end
            
            // --- Read ---
            if (m_axi_d_arvalid && !m_axi_d_arready) begin
                m_axi_d_arready <= 1;
            end else begin
                m_axi_d_arready <= 0;
            end
            
            if (m_axi_d_arvalid && m_axi_d_arready) begin
                m_axi_d_rvalid <= 1;
                m_axi_d_rdata <= memory[m_axi_d_araddr[11:2]];
                m_axi_d_rresp <= 2'b00;
            end else if (m_axi_d_rvalid && m_axi_d_rready) begin
                m_axi_d_rvalid <= 0;
            end
        end
    end
    
    // Test Stimulus
    integer i;
    integer pass_count;
    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);
        
        rst_n = 0;
        debug_reg_idx = 0;
        pass_count = 0;
        
        for (i = 0; i < 1024; i = i + 1) memory[i] = 32'h00000013; // NOP (addi x0, x0, 0)
        
        // Test Program: exercises ALU, MDU, and LSQ (9 tests)
        // x1 = 50, x2 = 15
        memory[0]  = 32'h03200093; // addi x1, x0, 50
        memory[1]  = 32'h00F00113; // addi x2, x0, 15
        // ALU R-type
        memory[2]  = 32'h002081B3; // add  x3, x1, x2     → 65
        memory[3]  = 32'h40208233; // sub  x4, x1, x2     → 35
        memory[4]  = 32'h0020F3B3; // and  x7, x1, x2     → 2
        memory[5]  = 32'h0020E433; // or   x8, x1, x2     → 63
        // MDU (multi-cycle)
        memory[6]  = 32'h022082B3; // mul  x5, x1, x2     → 750
        memory[7]  = 32'h0220C333; // div  x6, x1, x2     → 3
        // Store / Load
        memory[8]  = 32'h00502023; // sw   x5, 0(x0)      → mem[0] = 750
        memory[9]  = 32'h00002483; // lw   x9, 0(x0)      → x9 = 750
        
        #40;
        rst_n = 1;
        
        // Wait for pipeline to process all instructions (long timeout for MDU + LSQ)
        #40000;
        
        $display("Register State after execution:");
        
        debug_reg_idx = 1; #20;
        if (debug_reg_val == 50) begin $display("x1 = %0d  (PASS)  [ADDI]", debug_reg_val); pass_count = pass_count + 1; end
        else $display("x1 = %0d (FAIL, expected 50)", debug_reg_val);
        
        debug_reg_idx = 2; #20;
        if (debug_reg_val == 15) begin $display("x2 = %0d  (PASS)  [ADDI]", debug_reg_val); pass_count = pass_count + 1; end
        else $display("x2 = %0d (FAIL, expected 15)", debug_reg_val);
        
        debug_reg_idx = 3; #20;
        if (debug_reg_val == 65) begin $display("x3 = %0d  (PASS)  [ADD]", debug_reg_val); pass_count = pass_count + 1; end
        else $display("x3 = %0d (FAIL, expected 65)", debug_reg_val);
        
        debug_reg_idx = 4; #20;
        if (debug_reg_val == 35) begin $display("x4 = %0d  (PASS)  [SUB]", debug_reg_val); pass_count = pass_count + 1; end
        else $display("x4 = %0d (FAIL, expected 35)", debug_reg_val);
        
        debug_reg_idx = 5; #20;
        if (debug_reg_val == 750) begin $display("x5 = %0d (PASS)  [MUL]", debug_reg_val); pass_count = pass_count + 1; end
        else $display("x5 = %0d (FAIL, expected 750)", debug_reg_val);
        
        debug_reg_idx = 6; #20;
        if (debug_reg_val == 3) begin $display("x6 = %0d   (PASS)  [DIV]", debug_reg_val); pass_count = pass_count + 1; end
        else $display("x6 = %0d (FAIL, expected 3)", debug_reg_val);
        
        debug_reg_idx = 7; #20;
        if (debug_reg_val == 2) begin $display("x7 = %0d   (PASS)  [AND]", debug_reg_val); pass_count = pass_count + 1; end
        else $display("x7 = %0d (FAIL, expected 2)", debug_reg_val);
        
        debug_reg_idx = 8; #20;
        if (debug_reg_val == 63) begin $display("x8 = %0d  (PASS)  [OR]", debug_reg_val); pass_count = pass_count + 1; end
        else $display("x8 = %0d (FAIL, expected 63)", debug_reg_val);
        
        debug_reg_idx = 9; #20;
        if (debug_reg_val == 750) begin $display("x9 = %0d (PASS)  [SW/LW]", debug_reg_val); pass_count = pass_count + 1; end
        else $display("x9 = %0d (FAIL, expected 750)", debug_reg_val);
        
        $display("Result: %0d / 9 tests passed", pass_count);
        if (pass_count == 9) $display("[ ALL TESTS PASSED ]");
        else                 $display("[ SOME TESTS FAILED ]");
        $finish;
    end
    
    // Pipeline Debug Tracing
    
    // Track fetch activity
    always @(posedge clk) begin
        if (rst_n && $time < 5000) begin
            if (u_top.imem_req)
                $display("[%0t] FETCH: req addr=%h", $time, u_top.imem_addr);
            if (u_top.imem_ack)
                $display("[%0t] FETCH: ack data=%h", $time, u_top.imem_rdata);
            if (u_top.instr_valid && u_top.ready_for_instr)
                $display("[%0t] DISPATCH: instr=%h pc=%h rob_tag=%0d", $time, u_top.instr, u_top.instr_pc, u_top.rob_alloc_idx);
        end
    end
    
    // Track CDB broadcasts
    always @(posedge clk) begin
        if (rst_n && $time < 10000) begin
            if (u_top.cdb_valid)
                $display("[%0t] CDB: tag=%0d data=%0d (alu_req=%b br_req=%b lsq_req=%b mdu_req=%b)", 
                    $time, u_top.cdb_tag, u_top.cdb_data,
                    u_top.alu_req_out, u_top.br_req_out, u_top.lsq_req_out, u_top.mdu_req_out);
        end
    end
    
    // Track ROB commits
    always @(posedge clk) begin
        if (rst_n && $time < 10000) begin
            if (u_top.commit_valid)
                $display("[%0t] COMMIT: rd=x%0d data=%0d pc=%h", $time, u_top.commit_rd, u_top.commit_data, u_top.commit_pc);
            if (u_top.commit_flush)
                $display("[%0t] FLUSH: target=%h", $time, u_top.commit_flush_target);
        end
    end
    
    // Track ALU RS issue and dispatch (early instructions only)
    always @(posedge clk) begin
        if (rst_n && $time < 2000) begin
            if (u_top.rs_alu_req)
                $display("[%0t] RS_ALU_ISSUE: dest=%0d vj_valid=%b vj=%0d vk_valid=%b vk=%0d imm=%0d op=%0d",
                    $time, u_top.rs_alu_dest, u_top.rs_alu_vj_valid, u_top.rs_alu_vj, 
                    u_top.rs_alu_vk_valid, u_top.rs_alu_vk, u_top.rs_alu_imm, u_top.rs_alu_op);
            if (u_top.alu_fu_valid)
                $display("[%0t] ALU_EXEC: dest=%0d vj=%0d vk=%0d imm=%0d op=%0d", 
                    $time, u_top.alu_fu_dest, u_top.alu_fu_vj, u_top.alu_fu_vk, u_top.alu_fu_imm, u_top.alu_fu_op);
            if (u_top.alu_req_out)
                $display("[%0t] ALU_RESULT: tag=%0d data=%0d ack=%b", 
                    $time, u_top.alu_tag_out, u_top.alu_data_out, u_top.alu_ack_in);
            if (u_top.actual_flush)
                $display("[%0t] PIPELINE_FLUSH: target=%h (commit_flush=%b spec_flush=%b)", 
                    $time, u_top.actual_flush_target, u_top.commit_flush, u_top.spec_flush);
        end
    end

endmodule
