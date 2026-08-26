// Small target-clock cache that decouples the PI2 OKI address multiplexer
// from the tagged sound-ROM bridge. ROM contents are immutable, so this cache
// is not architectural save-state data.
module CavePwrInst2OkiRomCache (
  input         clock,
  input         reset,
  input         io_client_rd,
  input  [24:0] io_client_addr,
  output [7:0]  io_client_dout,
  output        io_client_valid,
  output        io_mem_rd,
  output [24:0] io_mem_addr,
  input  [7:0]  io_mem_dout,
  input         io_mem_valid,
  output        io_idle
);
  localparam integer ENTRY_COUNT = 8;

  reg [ENTRY_COUNT-1:0] valid;
  reg [24:0] tags [0:ENTRY_COUNT-1];
  reg [7:0] data [0:ENTRY_COUNT-1];
  reg [2:0] replace_index;
  reg       pending;
  reg [24:0] pending_addr;
  integer lookup_index;
  integer reset_index;

  reg       client_hit;
  reg [7:0] client_data;
  always @(*) begin
    client_hit = 1'b0;
    client_data = 8'd0;
    for (lookup_index = 0; lookup_index < ENTRY_COUNT;
         lookup_index = lookup_index + 1) begin
      if (valid[lookup_index] && tags[lookup_index] == io_client_addr) begin
        client_hit = 1'b1;
        client_data = data[lookup_index];
      end
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      valid <= {ENTRY_COUNT{1'b0}};
      replace_index <= 3'd0;
      pending <= 1'b0;
      pending_addr <= 25'd0;
      for (reset_index = 0; reset_index < ENTRY_COUNT;
           reset_index = reset_index + 1) begin
        tags[reset_index] <= 25'd0;
        data[reset_index] <= 8'd0;
      end
    end
    else begin
      if (pending && io_mem_valid) begin
        valid[replace_index] <= 1'b1;
        tags[replace_index] <= pending_addr;
        data[replace_index] <= io_mem_dout;
        replace_index <= replace_index + 3'd1;
        pending <= 1'b0;
      end
      else if (!pending && io_client_rd && !client_hit) begin
        pending <= 1'b1;
        pending_addr <= io_client_addr;
      end
    end
  end

  assign io_client_dout = client_data;
  assign io_client_valid = io_client_rd & client_hit;
  assign io_mem_rd = pending;
  assign io_mem_addr = pending_addr;
  assign io_idle = ~pending;
endmodule
