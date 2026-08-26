// Reuses the existing logical NVRAM client after the CPU and EEPROM controller
// are quiesced. Reads and writes acknowledge only after the cache is idle.
module CaveSaveStateNvram #(
    parameter [7:0] SS_IDX = 8'd24
) (
    input wire        clk,
    input wire        reset,
    input wire        state_enable,
    input wire        restore_enable,

    output wire       mem_rd,
    output wire       mem_wr,
    output wire [6:0] mem_addr,
    output wire [15:0] mem_din,
    input wire [15:0] mem_dout,
    input wire        mem_wait_n,
    input wire        mem_valid,

    output wire       busy,
    output reg        blocked_access,
    cave_ssbus_if.slave ssbus
);

localparam [2:0] ST_IDLE           = 3'd0;
localparam [2:0] ST_READ_REQUEST   = 3'd1;
localparam [2:0] ST_READ_RESPONSE  = 3'd2;
localparam [2:0] ST_READ_DRAIN     = 3'd3;
localparam [2:0] ST_WRITE_REQUEST  = 3'd4;
localparam [2:0] ST_WRITE_DRAIN    = 3'd5;

reg [2:0] state = ST_IDLE;
reg [5:0] word_addr = 6'd0;
reg [15:0] write_data = 16'd0;
reg [15:0] read_data = 16'd0;

wire selected = ssbus.select == SS_IDX;
wire requested = selected && !ssbus.query && (ssbus.read || ssbus.write);
wire address_valid = ssbus.addr < 32'd64;

assign mem_rd = state == ST_READ_REQUEST;
assign mem_wr = state == ST_WRITE_REQUEST;
assign mem_addr = {word_addr, 1'b0};
assign mem_din = write_data;
assign busy = state != ST_IDLE;

always @(posedge clk) begin
    if (reset) begin
        state <= ST_IDLE;
        word_addr <= 6'd0;
        write_data <= 16'd0;
        read_data <= 16'd0;
        ssbus.data_out <= 64'd0;
        ssbus.ack <= 1'b0;
        blocked_access <= 1'b0;
    end else begin
        ssbus.ack <= 1'b0;
        blocked_access <= 1'b0;

        case (state)
            ST_IDLE: begin
                if (selected && ssbus.query) begin
                    ssbus.data_out <=
                        {SS_IDX, 22'd0, 2'd1, 32'd64};
                    ssbus.ack <= 1'b1;
                end else if (requested && !state_enable) begin
                    ssbus.data_out <= 64'd0;
                    ssbus.ack <= 1'b1;
                    blocked_access <= 1'b1;
                end else if (requested && !address_valid) begin
                    ssbus.data_out <= 64'd0;
                    ssbus.ack <= 1'b1;
                end else if (requested && ssbus.read) begin
                    word_addr <= ssbus.addr[5:0];
                    state <= ST_READ_REQUEST;
                end else if (requested && ssbus.write) begin
                    if (!restore_enable) begin
                        ssbus.ack <= 1'b1;
                    end else begin
                        word_addr <= ssbus.addr[5:0];
                        write_data <= ssbus.data[15:0];
                        state <= ST_WRITE_REQUEST;
                    end
                end
            end

            ST_READ_REQUEST: begin
                if (mem_valid) begin
                    read_data <= mem_dout;
                    state <= ST_READ_DRAIN;
                end else if (mem_wait_n) begin
                    state <= ST_READ_RESPONSE;
                end
            end

            ST_READ_RESPONSE: begin
                if (mem_valid) begin
                    read_data <= mem_dout;
                    state <= ST_READ_DRAIN;
                end
            end

            ST_READ_DRAIN: begin
                if (mem_wait_n) begin
                    ssbus.data_out <= {48'd0, read_data};
                    ssbus.ack <= 1'b1;
                    state <= ST_IDLE;
                end
            end

            ST_WRITE_REQUEST: begin
                if (mem_wait_n)
                    state <= ST_WRITE_DRAIN;
            end

            ST_WRITE_DRAIN: begin
                if (mem_wait_n) begin
                    ssbus.ack <= 1'b1;
                    state <= ST_IDLE;
                end
            end

            default: state <= ST_IDLE;
        endcase
    end
end

endmodule
