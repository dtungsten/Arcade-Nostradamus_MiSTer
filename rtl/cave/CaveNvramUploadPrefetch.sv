// Presents each EEPROM word before MiSTer's upload read strobe samples it.
module CaveNvramUploadPrefetch (
  input         clock,
  input         reset,
  input         upload,
  input  [26:0] upload_addr,
  output [15:0] upload_dout,
  output        upload_wait_n,
  output        mem_rd,
  output [6:0]  mem_addr,
  input  [15:0] mem_dout,
  input         mem_wait_n,
  input         mem_valid
);
  localparam [1:0] STATE_IDLE    = 2'd0;
  localparam [1:0] STATE_REQUEST = 2'd1;
  localparam [1:0] STATE_WAIT    = 2'd2;
  localparam [1:0] STATE_READY   = 2'd3;

  reg [1:0]  state;
  reg [6:0]  address;
  reg [15:0] data;

  wire selected = upload && (upload_addr < 27'd128);
  wire address_changed = upload_addr[6:0] != address;

  always @(posedge clock) begin
    if (reset || !selected) begin
      state <= STATE_IDLE;
      address <= 7'd0;
      data <= 16'd0;
    end else begin
      case (state)
        STATE_IDLE: begin
          address <= upload_addr[6:0];
          state <= STATE_REQUEST;
        end

        STATE_REQUEST: begin
          if (mem_wait_n) begin
            if (mem_valid) begin
              data <= mem_dout;
              state <= STATE_READY;
            end else begin
              state <= STATE_WAIT;
            end
          end
        end

        STATE_WAIT: begin
          if (mem_valid) begin
            data <= mem_dout;
            state <= STATE_READY;
          end
        end

        STATE_READY: begin
          if (address_changed) begin
            address <= upload_addr[6:0];
            state <= STATE_REQUEST;
          end
        end

        default:
          state <= STATE_IDLE;
      endcase
    end
  end

  assign upload_dout = data;
  assign upload_wait_n =
    !selected || ((state == STATE_READY) && !address_changed);
  assign mem_rd = selected && (state == STATE_REQUEST);
  assign mem_addr = address;
endmodule
