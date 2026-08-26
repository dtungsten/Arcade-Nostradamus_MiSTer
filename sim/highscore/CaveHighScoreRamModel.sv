// Byte-addressed simulation model for the mixed-width RAMs used by the
// high-score manager. Quartus builds use the Arcadia altsyncram wrapper.
module true_dual_port_ram #(
  parameter ADDR_WIDTH_A = 8,
  parameter ADDR_WIDTH_B = 8,
  parameter DATA_WIDTH_A = 8,
  parameter DATA_WIDTH_B = 8,
  parameter DEPTH_A = 0,
  parameter DEPTH_B = 0,
  parameter MASK_ENABLE = 0
) (
  input                           clk_a,
  input                           rd_a,
  input                           wr_a,
  input      [ADDR_WIDTH_A-1:0]   addr_a,
  input      [DATA_WIDTH_A/8-1:0] mask_a,
  input      [DATA_WIDTH_A-1:0]   din_a,
  output reg [DATA_WIDTH_A-1:0]   dout_a,
  input                           clk_b,
  input                           rd_b,
  input      [ADDR_WIDTH_B-1:0]   addr_b,
  output reg [DATA_WIDTH_B-1:0]   dout_b
);
  localparam integer BYTE_COUNT_A = DATA_WIDTH_A / 8;
  localparam integer BYTE_COUNT_B = DATA_WIDTH_B / 8;
  localparam integer BYTE_DEPTH_A = (1 << ADDR_WIDTH_A) * BYTE_COUNT_A;
  localparam integer BYTE_DEPTH_B = (1 << ADDR_WIDTH_B) * BYTE_COUNT_B;
  localparam integer BYTE_DEPTH = BYTE_DEPTH_A > BYTE_DEPTH_B
    ? BYTE_DEPTH_A : BYTE_DEPTH_B;

  reg [7:0] mem [0:BYTE_DEPTH-1];
  integer i;

  initial begin
    dout_a = {DATA_WIDTH_A{1'b0}};
    dout_b = {DATA_WIDTH_B{1'b0}};
    for (i = 0; i < BYTE_DEPTH; i = i + 1)
      mem[i] = 8'd0;
  end

  always @(posedge clk_a) begin
    if (rd_a) begin
      for (i = 0; i < BYTE_COUNT_A; i = i + 1)
        dout_a[i*8 +: 8] <= mem[(addr_a * BYTE_COUNT_A) + i];
    end
    if (wr_a) begin
      for (i = 0; i < BYTE_COUNT_A; i = i + 1)
        if (!MASK_ENABLE || mask_a[i])
          mem[(addr_a * BYTE_COUNT_A) + i] <= din_a[i*8 +: 8];
    end
  end

  always @(posedge clk_b) begin
    if (rd_b) begin
      for (i = 0; i < BYTE_COUNT_B; i = i + 1)
        dout_b[i*8 +: 8] <= mem[(addr_b * BYTE_COUNT_B) + i];
    end
  end
endmodule
