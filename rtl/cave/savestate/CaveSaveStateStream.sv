// Cave-local chunk serializer, adapted from the MiSTer Taito F2/IGS PGM
// save-state stream and the corrected Batsugun implementation.
module CaveSaveStateData #(
    parameter [31:0] DDR_BASE = 32'h3e00_0000,
    parameter [31:0] SLOT_LENGTH = 32'h0040_0000,
    parameter integer CHUNK_COUNT = 48,
    parameter integer QUERY_TIMEOUT_BITS = 5
) (
    input wire       clk,
    input wire       reset,
    cave_ss_ddr_if.to_host ddr,
    input wire       load_start,
    input wire       save_start,
    input wire       abort,
    input wire [1:0] slot,
    output wire      busy,
    output wire      done,
    output wire      format_error,
    cave_ssbus_if.master ssbus
);

wire [31:0] slot_base = DDR_BASE + ({30'd0, slot} * SLOT_LENGTH);

CaveSaveStateStream #(
    .CHUNK_COUNT(CHUNK_COUNT),
    .QUERY_TIMEOUT_BITS(QUERY_TIMEOUT_BITS)
) stream (
    .clk(clk),
    .reset(reset),
    .ddr(ddr),
    .owner_write(ssbus.write),
    .owner_write_data(ssbus.data),
    .owner_ack(ssbus.ack),
    .owner_read(ssbus.read),
    .owner_read_data(ssbus.data_out),
    .owner_query(ssbus.query),
    .owner_addr(ssbus.addr),
    .owner_select(ssbus.select),
    .start_addr(slot_base),
    .length(SLOT_LENGTH),
    .load_start(load_start),
    .save_start(save_start),
    .abort(abort),
    .busy(busy),
    .done(done),
    .format_error(format_error)
);

endmodule

module CaveSaveStateStream #(
    parameter integer CHUNK_COUNT = 48,
    parameter integer QUERY_TIMEOUT_BITS = 5
) (
    input wire         clk,
    input wire         reset,
    cave_ss_ddr_if.to_host ddr,

    output reg         owner_write,
    output reg [63:0]  owner_write_data,
    input wire         owner_ack,
    output reg         owner_read,
    input wire [63:0]  owner_read_data,
    output reg         owner_query,
    output reg [31:0]  owner_addr,
    output reg [7:0]   owner_select,

    input wire [31:0]  start_addr,
    input wire [31:0]  length,
    input wire         load_start,
    input wire         save_start,
    input wire         abort,
    output wire        busy,
    output reg         done,
    output reg         format_error
);

typedef enum logic [4:0] {
    ST_IDLE,
    ST_READ_HEADER_REQ,
    ST_READ_HEADER_WAIT,
    ST_LOAD_MEM_REQ,
    ST_LOAD_MEM_WAIT,
    ST_LOAD_QUERY_WAIT,
    ST_LOAD_STREAM,
    ST_SAVE_INVALIDATE_REQ,
    ST_SAVE_INVALIDATE_WAIT,
    ST_SAVE_QUERY_FIRST,
    ST_SAVE_QUERY_NEXT,
    ST_SAVE_QUERY_WAIT,
    ST_SAVE_GATHER,
    ST_SAVE_MEM_REQ,
    ST_SAVE_MEM_WAIT,
    ST_SAVE_FINAL_REQ,
    ST_SAVE_FINAL_WAIT,
    ST_HEADER_SIZE_REQ,
    ST_HEADER_SIZE_WAIT,
    ST_HEADER_CHANGE_REQ,
    ST_HEADER_CHANGE_WAIT
} state_t;

state_t state = ST_IDLE;

assign busy = state != ST_IDLE;

reg [31:0] end_addr = 32'd0;
reg [31:0] current_addr = 32'd0;
reg [2:0]  lane = 3'd0;
reg [63:0] buffer = 64'd0;
reg [31:0] chunk_remaining = 32'd0;
reg [31:0] next_owner_addr = 32'd0;
reg [QUERY_TIMEOUT_BITS-1:0] query_delay = {QUERY_TIMEOUT_BITS{1'b0}};
reg [1:0]  chunk_width = 2'd0;
reg [7:0]  chunk_index = 8'd0;
reg        is_loading = 1'b0;
reg        owner_pending = 1'b0;
reg [63:0] header_data = 64'd0;

wire [31:0] chunk_byte_count = chunk_remaining << chunk_width;
wire [31:0] rounded_chunk_bytes =
    (chunk_byte_count + 32'd7) & 32'hffff_fff8;
wire [31:0] header_payload_bytes = {ddr.rdata[61:32], 2'b00};
wire [31:0] payload_length = current_addr - (start_addr + 32'd8);
wire [31:0] next_change_detector = (&header_data[31:0])
    ? 32'd1 : header_data[31:0] + 32'd1;

function automatic [2:0] last_lane(input [1:0] width);
    case (width)
        2'd0: last_lane = 3'd7;
        2'd1: last_lane = 3'd3;
        2'd2: last_lane = 3'd1;
        default: last_lane = 3'd0;
    endcase
endfunction

task automatic finish_operation;
begin
    ddr.acquire <= 1'b0;
    ddr.read <= 1'b0;
    ddr.write <= 1'b0;
    owner_read <= 1'b0;
    owner_write <= 1'b0;
    owner_query <= 1'b0;
    done <= 1'b1;
    state <= ST_IDLE;
end
endtask

always_ff @(posedge clk) begin
    if (reset) begin
        state <= ST_IDLE;
        ddr.acquire <= 1'b0;
        ddr.addr <= 32'd0;
        ddr.wdata <= 64'd0;
        ddr.read <= 1'b0;
        ddr.write <= 1'b0;
        ddr.burstcnt <= 8'd1;
        ddr.byteenable <= 8'hff;
        owner_write <= 1'b0;
        owner_write_data <= 64'd0;
        owner_read <= 1'b0;
        owner_query <= 1'b0;
        owner_addr <= 32'd0;
        owner_select <= 8'd0;
        done <= 1'b0;
        format_error <= 1'b0;
        lane <= 3'd0;
        chunk_remaining <= 32'd0;
        chunk_index <= 8'd0;
        is_loading <= 1'b0;
        owner_pending <= 1'b0;
    end else begin
        done <= 1'b0;

        if (abort && (state != ST_IDLE)) begin
            format_error <= 1'b1;
            finish_operation();
        end else case (state)
            ST_IDLE: begin
                ddr.acquire <= 1'b0;
                ddr.read <= 1'b0;
                ddr.write <= 1'b0;
                ddr.burstcnt <= 8'd1;
                ddr.byteenable <= 8'hff;
                owner_write <= 1'b0;
                owner_read <= 1'b0;
                owner_query <= 1'b0;
                owner_select <= 8'd0;
                owner_addr <= 32'd0;
                current_addr <= start_addr + 32'd8;
                end_addr <= start_addr + length;
                lane <= 3'd0;
                buffer <= 64'd0;
                chunk_remaining <= 32'd0;
                next_owner_addr <= 32'd0;
                chunk_index <= 8'd0;
                owner_pending <= 1'b0;

                if (load_start || save_start) begin
                    format_error <= 1'b0;
                    is_loading <= load_start;
                    ddr.acquire <= 1'b1;
                    state <= ST_READ_HEADER_REQ;
                end
            end

            ST_READ_HEADER_REQ: begin
                if (!ddr.busy) begin
                    ddr.addr <= start_addr;
                    ddr.read <= 1'b1;
                    state <= ST_READ_HEADER_WAIT;
                end
            end

            ST_READ_HEADER_WAIT: begin
                // BUSY is the request-acceptance handshake; read data may
                // return later on rdata_ready.
                if (!ddr.busy)
                    ddr.read <= 1'b0;

                if (ddr.rdata_ready) begin
                    ddr.read <= 1'b0;
                    header_data <= ddr.rdata;

                    if (is_loading) begin
                        if ((ddr.rdata[31:0] == 0) ||
                            (header_payload_bytes == 0) ||
                            (header_payload_bytes > (length - 32'd8))) begin
                            format_error <= 1'b1;
                            finish_operation();
                        end else begin
                            end_addr <= start_addr + 32'd8 +
                                        header_payload_bytes;
                            state <= ST_LOAD_MEM_REQ;
                        end
                    end else begin
                        state <= ST_SAVE_INVALIDATE_REQ;
                    end
                end
            end

            ST_SAVE_INVALIDATE_REQ: begin
                if (!ddr.busy) begin
                    ddr.addr <= start_addr;
                    ddr.byteenable <= 8'h0f;
                    ddr.wdata[31:0] <= 32'd0;
                    ddr.write <= 1'b1;
                    state <= ST_SAVE_INVALIDATE_WAIT;
                end
            end

            ST_SAVE_INVALIDATE_WAIT: begin
                if (!ddr.busy) begin
                    ddr.write <= 1'b0;
                    ddr.byteenable <= 8'hff;
                    state <= ST_SAVE_QUERY_FIRST;
                end
            end

            ST_LOAD_MEM_REQ: begin
                owner_write <= 1'b0;
                owner_query <= 1'b0;
                if (current_addr >= end_addr) begin
                    finish_operation();
                end else if (!ddr.busy) begin
                    ddr.addr <= current_addr & 32'hffff_fff8;
                    current_addr <= current_addr + 32'd8;
                    ddr.read <= 1'b1;
                    state <= ST_LOAD_MEM_WAIT;
                end
            end

            ST_LOAD_MEM_WAIT: begin
                if (!ddr.busy)
                    ddr.read <= 1'b0;

                if (ddr.rdata_ready) begin
                    ddr.read <= 1'b0;
                    buffer <= ddr.rdata;

                    if (chunk_remaining == 0) begin
                        if (&ddr.rdata) begin
                            finish_operation();
                        end else begin
                            chunk_remaining <= ddr.rdata[31:0];
                            chunk_width <= ddr.rdata[33:32];
                            owner_select <= ddr.rdata[63:56];
                            owner_addr <= 32'd0;
                            next_owner_addr <= 32'd0;
                            lane <= 3'd0;
                            owner_write <= 1'b1;
                            owner_query <= 1'b1;
                            query_delay <= {QUERY_TIMEOUT_BITS{1'b0}};
                            state <= ST_LOAD_QUERY_WAIT;
                        end
                    end else begin
                        state <= ST_LOAD_STREAM;
                    end
                end
            end

            ST_LOAD_QUERY_WAIT: begin
                if (owner_ack) begin
                    owner_query <= 1'b0;
                    owner_write <= 1'b0;
                    owner_addr <= 32'd0;
                    next_owner_addr <= 32'd0;
                    lane <= 3'd0;
                    owner_pending <= 1'b0;
                    state <= ST_LOAD_MEM_REQ;
                end else if (&query_delay) begin
                    owner_query <= 1'b0;
                    owner_write <= 1'b0;
                    current_addr <= current_addr + rounded_chunk_bytes;
                    chunk_remaining <= 32'd0;
                    owner_addr <= 32'd0;
                    next_owner_addr <= 32'd0;
                    lane <= 3'd0;
                    owner_pending <= 1'b0;
                    state <= ST_LOAD_MEM_REQ;
                end else begin
                    query_delay <= query_delay +
                                   {{(QUERY_TIMEOUT_BITS-1){1'b0}}, 1'b1};
                end
            end

            ST_LOAD_STREAM: begin
                owner_write <= 1'b0;
                if (chunk_remaining == 0) begin
                    owner_addr <= 32'd0;
                    lane <= 3'd0;
                    owner_pending <= 1'b0;
                    state <= ST_LOAD_MEM_REQ;
                end else begin
                    case (chunk_width)
                        2'd0: owner_write_data[7:0] <=
                                  buffer[(lane * 8) +: 8];
                        2'd1: owner_write_data[15:0] <=
                                  buffer[(lane * 16) +: 16];
                        2'd2: owner_write_data[31:0] <=
                                  buffer[(lane * 32) +: 32];
                        default: owner_write_data <= buffer;
                    endcase

                    if (owner_pending && owner_ack) begin
                        if (lane == last_lane(chunk_width)) begin
                            lane <= 3'd0;
                            state <= ST_LOAD_MEM_REQ;
                        end else begin
                            lane <= lane + 3'd1;
                        end
                        chunk_remaining <= chunk_remaining - 32'd1;
                        next_owner_addr <= owner_addr + 32'd1;
                        owner_pending <= 1'b0;
                    end else if (!owner_pending && !owner_ack) begin
                        owner_addr <= next_owner_addr;
                        owner_write <= 1'b1;
                        owner_pending <= 1'b1;
                    end
                end
            end

            ST_SAVE_QUERY_FIRST: begin
                chunk_index <= 8'd0;
                owner_select <= 8'd0;
                owner_addr <= 32'd0;
                owner_read <= 1'b1;
                owner_query <= 1'b1;
                query_delay <= {QUERY_TIMEOUT_BITS{1'b0}};
                owner_pending <= 1'b0;
                state <= ST_SAVE_QUERY_WAIT;
            end

            ST_SAVE_QUERY_NEXT: begin
                if ((chunk_index + 8'd1) >= CHUNK_COUNT) begin
                    state <= ST_SAVE_FINAL_REQ;
                end else begin
                    chunk_index <= chunk_index + 8'd1;
                    owner_select <= chunk_index + 8'd1;
                    owner_addr <= 32'd0;
                    owner_read <= 1'b1;
                    owner_query <= 1'b1;
                    query_delay <= {QUERY_TIMEOUT_BITS{1'b0}};
                    owner_pending <= 1'b0;
                    state <= ST_SAVE_QUERY_WAIT;
                end
            end

            ST_SAVE_QUERY_WAIT: begin
                if (owner_ack) begin
                    buffer <= 64'd0;
                    buffer[33:0] <= owner_read_data[33:0];
                    buffer[63:56] <= chunk_index;
                    chunk_remaining <= owner_read_data[31:0];
                    chunk_width <= owner_read_data[33:32];
                    owner_addr <= 32'd0;
                    next_owner_addr <= 32'd0;
                    lane <= 3'd0;
                    owner_query <= 1'b0;
                    owner_read <= 1'b0;
                    owner_pending <= 1'b0;
                    state <= ST_SAVE_MEM_REQ;
                end else if (&query_delay) begin
                    owner_query <= 1'b0;
                    owner_read <= 1'b0;
                    owner_pending <= 1'b0;
                    state <= ST_SAVE_QUERY_NEXT;
                end else begin
                    query_delay <= query_delay +
                                   {{(QUERY_TIMEOUT_BITS-1){1'b0}}, 1'b1};
                end
            end

            ST_SAVE_GATHER: begin
                owner_read <= 1'b0;
                if (chunk_remaining == 0) begin
                    if (lane != 0)
                        state <= ST_SAVE_MEM_REQ;
                    else
                        state <= ST_SAVE_QUERY_NEXT;
                    owner_pending <= 1'b0;
                end else if (owner_pending && owner_ack) begin
                    case (chunk_width)
                        2'd0: buffer[(lane * 8) +: 8] <=
                                  owner_read_data[7:0];
                        2'd1: buffer[(lane * 16) +: 16] <=
                                  owner_read_data[15:0];
                        2'd2: buffer[(lane * 32) +: 32] <=
                                  owner_read_data[31:0];
                        default: buffer <= owner_read_data;
                    endcase

                    if (lane == last_lane(chunk_width)) begin
                        lane <= 3'd0;
                        state <= ST_SAVE_MEM_REQ;
                    end else begin
                        lane <= lane + 3'd1;
                    end
                    next_owner_addr <= owner_addr + 32'd1;
                    chunk_remaining <= chunk_remaining - 32'd1;
                    owner_pending <= 1'b0;
                end else if (!owner_pending && !owner_ack) begin
                    owner_addr <= next_owner_addr;
                    owner_read <= 1'b1;
                    owner_pending <= 1'b1;
                end
            end

            ST_SAVE_MEM_REQ: begin
                if (current_addr >= end_addr) begin
                    format_error <= 1'b1;
                    finish_operation();
                end else if (!ddr.busy) begin
                    ddr.addr <= current_addr & 32'hffff_fff8;
                    ddr.wdata <= buffer;
                    ddr.write <= 1'b1;
                    current_addr <= current_addr + 32'd8;
                    state <= ST_SAVE_MEM_WAIT;
                end
            end

            ST_SAVE_MEM_WAIT: begin
                if (!ddr.busy) begin
                    ddr.write <= 1'b0;
                    if (chunk_remaining == 0) begin
                        lane <= 3'd0;
                        buffer <= 64'd0;
                        state <= ST_SAVE_QUERY_NEXT;
                    end else begin
                        buffer <= 64'd0;
                        state <= ST_SAVE_GATHER;
                    end
                end
            end

            ST_SAVE_FINAL_REQ: begin
                if (current_addr >= end_addr) begin
                    format_error <= 1'b1;
                    finish_operation();
                end else if (!ddr.busy) begin
                    ddr.addr <= current_addr & 32'hffff_fff8;
                    ddr.wdata <= 64'hffff_ffff_ffff_ffff;
                    ddr.write <= 1'b1;
                    current_addr <= current_addr + 32'd8;
                    state <= ST_SAVE_FINAL_WAIT;
                end
            end

            ST_SAVE_FINAL_WAIT: begin
                if (!ddr.busy) begin
                    ddr.write <= 1'b0;
                    state <= ST_HEADER_SIZE_REQ;
                end
            end

            ST_HEADER_SIZE_REQ: begin
                if (!ddr.busy) begin
                    ddr.addr <= start_addr;
                    ddr.byteenable <= 8'hf0;
                    ddr.wdata[63:32] <= {2'b00, payload_length[31:2]};
                    ddr.write <= 1'b1;
                    state <= ST_HEADER_SIZE_WAIT;
                end
            end

            ST_HEADER_SIZE_WAIT: begin
                if (!ddr.busy) begin
                    ddr.write <= 1'b0;
                    ddr.byteenable <= 8'hff;
                    state <= ST_HEADER_CHANGE_REQ;
                end
            end

            ST_HEADER_CHANGE_REQ: begin
                if (!ddr.busy) begin
                    ddr.addr <= start_addr;
                    ddr.byteenable <= 8'h0f;
                    ddr.wdata[31:0] <= next_change_detector;
                    ddr.write <= 1'b1;
                    state <= ST_HEADER_CHANGE_WAIT;
                end
            end

            ST_HEADER_CHANGE_WAIT: begin
                if (!ddr.busy) begin
                    ddr.write <= 1'b0;
                    ddr.byteenable <= 8'hff;
                    finish_operation();
                end
            end

            default: begin
                format_error <= 1'b1;
                finish_operation();
            end
        endcase
    end
end

endmodule
