`timescale 1ns / 1ps
`include "../include/params.vh"

//-----------------------------------------------------------------------------
// Perceptron Branch Predictor
// An AI-driven branch predictor using a single-layer neural network.
// It computes a dot product between the Global History Register (GHR) and
// a learned set of weights.
//-----------------------------------------------------------------------------
module perceptron_bpu #(
    parameter HISTORY_LEN = 4,   // N = 4 bits of global history
    parameter WEIGHT_WIDTH = 8,  // 8-bit signed weights
    parameter TABLE_ENTRIES = 32 // Number of perceptrons
)(
    input  wire                      clk,
    input  wire                      rst_n,
    
    // --- Prediction Interface (Fetch Stage) ---
    input  wire [`ADDR_WIDTH-1:0]     fetch_pc,
    input  wire                      fetch_valid,  // Pulsed when fetching a valid instruction
    output wire                      predict_taken,
    
    // --- Training Interface (Commit Stage) ---
    input  wire                      commit_valid,
    input  wire                      commit_is_branch,
    input  wire [`ADDR_WIDTH-1:0]     commit_pc,
    input  wire                      commit_taken,
    input  wire                      commit_pred_taken // What did we originally predict?
);

    localparam INDEX_WIDTH = $clog2(TABLE_ENTRIES);
    localparam THRESHOLD = (1.93 * HISTORY_LEN) + 14; // Standard perceptron threshold formula

    // Global History Register
    reg [HISTORY_LEN-1:0] ghr;

    // Weight tables: [w0 (bias), w1, w2, w3, w4]
    // Indexed by PC hash
    reg signed [WEIGHT_WIDTH-1:0] w0 [0:TABLE_ENTRIES-1];
    reg signed [WEIGHT_WIDTH-1:0] w  [0:HISTORY_LEN-1][0:TABLE_ENTRIES-1];

    // Read index
    wire [INDEX_WIDTH-1:0] fetch_idx = fetch_pc[INDEX_WIDTH+1:2];
    
    // Write index
    wire [INDEX_WIDTH-1:0] commit_idx = commit_pc[INDEX_WIDTH+1:2];

    // --- PREDICTION LOGIC (Combinational) ---
    // In a real high-speed design, this adder tree would be pipelined.
    // For this project, we implement it completely combinationally.
    reg signed [WEIGHT_WIDTH+3:0] y_out;
    integer i;
    always @(*) begin
        y_out = w0[fetch_idx];
        for (i = 0; i < HISTORY_LEN; i = i + 1) begin
            // If history bit is 1, add weight. If 0 (representing -1), subtract weight.
            if (ghr[i]) begin
                y_out = y_out + w[i][fetch_idx];
            end else begin
                y_out = y_out - w[i][fetch_idx];
            end
        end
    end

    // Predict taken if y_out >= 0
    assign predict_taken = (y_out >= 0);

    // --- TRAINING LOGIC (Sequential) ---
    wire sign_y = (y_out >= 0);
    // Was the prediction incorrect, or was the confidence too low?
    wire train_needed = (commit_pred_taken != commit_taken) || 
                        ((y_out >= 0 ? y_out : -y_out) <= THRESHOLD);

    integer j, k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ghr <= 0;
            for (j = 0; j < TABLE_ENTRIES; j = j + 1) begin
                w0[j] <= 0;
                for (k = 0; k < HISTORY_LEN; k = k + 1) begin
                    w[k][j] <= 0;
                end
            end
        end else begin
            // Update weights if a branch committed and needs training
            if (commit_valid && commit_is_branch && train_needed) begin
                // Update bias
                if (commit_taken) begin
                    if (w0[commit_idx] < (1<<(WEIGHT_WIDTH-1))-1)
                        w0[commit_idx] <= w0[commit_idx] + 1;
                end else begin
                    if (w0[commit_idx] > -(1<<(WEIGHT_WIDTH-1)))
                        w0[commit_idx] <= w0[commit_idx] - 1;
                end
                
                // Update correlation weights based on GHR at the time of commit
                // (In a true processor, we would snapshot the GHR at fetch time and pass it down the pipeline.
                // For simplicity in this demo, we use the current speculative GHR).
                for (k = 0; k < HISTORY_LEN; k = k + 1) begin
                    if (commit_taken == ghr[k]) begin
                        if (w[k][commit_idx] < (1<<(WEIGHT_WIDTH-1))-1)
                            w[k][commit_idx] <= w[k][commit_idx] + 1;
                    end else begin
                        if (w[k][commit_idx] > -(1<<(WEIGHT_WIDTH-1)))
                            w[k][commit_idx] <= w[k][commit_idx] - 1;
                    end
                end
            end
            
            // Speculative update of GHR at fetch
            if (fetch_valid) begin // Assuming we only shift GHR on actual branches in a real core, but shift on all fetch here is okay for a simple hash
                ghr <= {ghr[HISTORY_LEN-2:0], predict_taken};
            end
        end
    end

endmodule
