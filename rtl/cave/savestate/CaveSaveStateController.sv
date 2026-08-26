// Cave-local save/restore coordinator. Device-specific idle and CPU checkpoint
// signals are kept outside this block so each integration boundary can be
// simulated independently.
module CaveSaveStateController #(
    parameter integer WATCHDOG_BITS = 24,
    parameter integer RECOVERY_CYCLES = 16
) (
    input  wire       clk,
    input  wire       reset,
    input  wire       allow,
    input  wire       save_request,
    input  wire       load_request,
    input  wire       vblank,

    input  wire       cpu_capture_done,
    input  wire       clients_idle,

    input  wire       stream_busy,
    input  wire       stream_done,
    input  wire       stream_format_error,
    input  wire       restore_valid,
    input  wire       restore_commit_done,
    input  wire       reconstruction_ready,

    output wire       active,
    output wire       freeze,
    output wire       block_clients,
    output wire       cpu_hold,
    output wire       cpu_capture_request,
    output wire       stream_save_start,
    output wire       stream_load_start,
    output wire       metadata_restore_start,
    output wire       stream_abort,
    output wire       restore_write_enable,
    output wire       restore_commit_request,
    output reg        release_pulse,
    output wire       recovery_reset,
    output wire [3:0] state_debug,
    output reg  [3:0] last_error
);

localparam [3:0] ST_IDLE                = 4'd0;
localparam [3:0] ST_WAIT_VBLANK         = 4'd1;
localparam [3:0] ST_SAVE_CAPTURE        = 4'd2;
localparam [3:0] ST_DRAIN               = 4'd3;
localparam [3:0] ST_SAVE_START          = 4'd4;
localparam [3:0] ST_SAVE_STREAM         = 4'd5;
localparam [3:0] ST_LOAD_START          = 4'd6;
localparam [3:0] ST_LOAD_STREAM         = 4'd7;
localparam [3:0] ST_RESTORE_COMMIT      = 4'd8;
localparam [3:0] ST_RESTORE_COMMIT_WAIT = 4'd9;
localparam [3:0] ST_ABORT_STREAM        = 4'd10;
localparam [3:0] ST_WAIT_RELEASE        = 4'd11;
localparam [3:0] ST_RECONSTRUCT         = 4'd12;
localparam [3:0] ST_RECOVERY_RESET      = 4'd13;

localparam [3:0] ERR_NONE          = 4'd0;
localparam [3:0] ERR_VBLANK        = 4'd1;
localparam [3:0] ERR_CPU_CAPTURE   = 4'd2;
localparam [3:0] ERR_DRAIN         = 4'd3;
localparam [3:0] ERR_STREAM        = 4'd4;
localparam [3:0] ERR_FORMAT        = 4'd5;
localparam [3:0] ERR_METADATA      = 4'd6;
localparam [3:0] ERR_COMMIT        = 4'd7;
localparam [3:0] ERR_RELEASE       = 4'd8;

reg [3:0] state = ST_IDLE;
reg [3:0] previous_state = ST_IDLE;
reg       operation_load = 1'b0;
reg       restore_mutated = 1'b0;
reg       vblank_d = 1'b0;
reg [WATCHDOG_BITS-1:0] watchdog = {WATCHDOG_BITS{1'b0}};
reg [15:0] recovery_count = 16'd0;

wire vblank_rising = vblank && !vblank_d;
wire watchdog_expired = &watchdog;

assign active = state != ST_IDLE;
assign freeze = active;
assign state_debug = state;

assign stream_save_start = state == ST_SAVE_START;
assign stream_load_start = state == ST_LOAD_START;
assign metadata_restore_start = state == ST_LOAD_START;
assign stream_abort = state == ST_ABORT_STREAM;
assign restore_commit_request = state == ST_RESTORE_COMMIT;
assign recovery_reset = state == ST_RECOVERY_RESET;

assign restore_write_enable =
    (state == ST_LOAD_STREAM) && restore_valid && !stream_format_error;

assign block_clients =
    (state == ST_SAVE_CAPTURE) ||
    (state == ST_DRAIN) ||
    (state == ST_SAVE_START) ||
    (state == ST_SAVE_STREAM) ||
    (state == ST_LOAD_START) ||
    (state == ST_LOAD_STREAM) ||
    (state == ST_RESTORE_COMMIT) ||
    (state == ST_RESTORE_COMMIT_WAIT) ||
    (state == ST_ABORT_STREAM) ||
    (state == ST_WAIT_RELEASE) ||
    (state == ST_RECOVERY_RESET);

assign cpu_hold =
    (state == ST_DRAIN) ||
    (state == ST_SAVE_START) ||
    (state == ST_SAVE_STREAM) ||
    (state == ST_LOAD_START) ||
    (state == ST_LOAD_STREAM) ||
    (state == ST_RESTORE_COMMIT) ||
    (state == ST_RESTORE_COMMIT_WAIT) ||
    (state == ST_ABORT_STREAM) ||
    (state == ST_WAIT_RELEASE) ||
    (state == ST_RECOVERY_RESET);

assign cpu_capture_request = !operation_load &&
    ((state == ST_SAVE_CAPTURE) ||
     (state == ST_DRAIN) ||
     (state == ST_SAVE_START) ||
     (state == ST_SAVE_STREAM) ||
     (state == ST_ABORT_STREAM) ||
     (state == ST_WAIT_RELEASE));

always @(posedge clk) begin
    if (reset) begin
        state <= ST_IDLE;
        previous_state <= ST_IDLE;
        operation_load <= 1'b0;
        restore_mutated <= 1'b0;
        vblank_d <= 1'b0;
        watchdog <= {WATCHDOG_BITS{1'b0}};
        recovery_count <= 16'd0;
        release_pulse <= 1'b0;
        last_error <= ERR_NONE;
    end else begin
        vblank_d <= vblank;
        release_pulse <= 1'b0;

        if (state != previous_state) begin
            previous_state <= state;
            watchdog <= {WATCHDOG_BITS{1'b0}};
        end else if (state != ST_IDLE) begin
            watchdog <= watchdog + {{(WATCHDOG_BITS-1){1'b0}}, 1'b1};
        end

        case (state)
            ST_IDLE: begin
                restore_mutated <= 1'b0;
                recovery_count <= 16'd0;
                if (allow && (save_request || load_request)) begin
                    operation_load <= load_request;
                    last_error <= ERR_NONE;
                    state <= ST_WAIT_VBLANK;
                end
            end

            ST_WAIT_VBLANK: begin
                if (!allow) begin
                    state <= ST_IDLE;
                end else if (vblank_rising) begin
                    if (operation_load)
                        state <= ST_DRAIN;
                    else
                        state <= ST_SAVE_CAPTURE;
                end else if (watchdog_expired) begin
                    last_error <= ERR_VBLANK;
                    state <= ST_IDLE;
                end
            end

            ST_SAVE_CAPTURE: begin
                if (cpu_capture_done) begin
                    state <= ST_DRAIN;
                end else if (watchdog_expired) begin
                    last_error <= ERR_CPU_CAPTURE;
                    state <= ST_WAIT_RELEASE;
                end
            end

            ST_DRAIN: begin
                if (clients_idle) begin
                    state <= operation_load ? ST_LOAD_START : ST_SAVE_START;
                end else if (watchdog_expired) begin
                    last_error <= ERR_DRAIN;
                    state <= ST_WAIT_RELEASE;
                end
            end

            ST_SAVE_START: begin
                if (stream_busy) begin
                    last_error <= ERR_STREAM;
                    state <= ST_ABORT_STREAM;
                end else begin
                    state <= ST_SAVE_STREAM;
                end
            end

            ST_SAVE_STREAM: begin
                if (stream_done) begin
                    if (stream_format_error)
                        last_error <= ERR_FORMAT;
                    state <= ST_WAIT_RELEASE;
                end else if (watchdog_expired) begin
                    last_error <= ERR_STREAM;
                    state <= ST_ABORT_STREAM;
                end
            end

            ST_LOAD_START: begin
                if (stream_busy) begin
                    last_error <= ERR_STREAM;
                    state <= ST_ABORT_STREAM;
                end else begin
                    state <= ST_LOAD_STREAM;
                end
            end

            ST_LOAD_STREAM: begin
                if (restore_valid)
                    restore_mutated <= 1'b1;

                if (stream_done) begin
                    if (stream_format_error) begin
                        last_error <= ERR_FORMAT;
                        state <= restore_mutated || restore_valid
                            ? ST_RECOVERY_RESET : ST_WAIT_RELEASE;
                    end else if (!restore_valid) begin
                        last_error <= ERR_METADATA;
                        state <= ST_WAIT_RELEASE;
                    end else begin
                        state <= ST_RESTORE_COMMIT;
                    end
                end else if (watchdog_expired) begin
                    last_error <= ERR_STREAM;
                    state <= ST_ABORT_STREAM;
                end
            end

            ST_RESTORE_COMMIT: begin
                state <= ST_RESTORE_COMMIT_WAIT;
            end

            ST_RESTORE_COMMIT_WAIT: begin
                if (restore_commit_done) begin
                    state <= ST_WAIT_RELEASE;
                end else if (watchdog_expired) begin
                    last_error <= ERR_COMMIT;
                    state <= ST_RECOVERY_RESET;
                end
            end

            ST_ABORT_STREAM: begin
                if (!stream_busy) begin
                    state <= operation_load && restore_mutated
                        ? ST_RECOVERY_RESET : ST_WAIT_RELEASE;
                end
            end

            ST_WAIT_RELEASE: begin
                if (vblank_rising) begin
                    release_pulse <= 1'b1;
                    state <= ST_RECONSTRUCT;
                end else if (watchdog_expired) begin
                    last_error <= ERR_RELEASE;
                    state <= ST_RECOVERY_RESET;
                end
            end

            ST_RECONSTRUCT: begin
                if (vblank_rising && reconstruction_ready) begin
                    state <= ST_IDLE;
                end else if (watchdog_expired) begin
                    last_error <= ERR_RELEASE;
                    state <= ST_RECOVERY_RESET;
                end
            end

            ST_RECOVERY_RESET: begin
                if (recovery_count + 16'd1 >= RECOVERY_CYCLES) begin
                    recovery_count <= 16'd0;
                    state <= ST_IDLE;
                end else begin
                    recovery_count <= recovery_count + 16'd1;
                end
            end

            default: begin
                last_error <= ERR_STREAM;
                state <= ST_RECOVERY_RESET;
            end
        endcase
    end
end

endmodule
