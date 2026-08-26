// Handshaked Cave-local clock crossings for save-state data and CPU control.
module CaveSaveStateBusCdc #(
    parameter [63:0] SELECT_MASK = 64'hffff_ffff_ffff_ffff
) (
    input wire src_clk,
    input wire src_reset,
    input wire src_restore_enable,
    input wire [63:0] src_select_mask,
    cave_ssbus_if.slave src_bus,

    input wire dst_clk,
    input wire dst_reset,
    output reg dst_restore_enable,
    cave_ssbus_if.master dst_bus
);

reg [63:0] src_data_hold = 64'd0;
reg [31:0] src_addr_hold = 32'd0;
reg [7:0]  src_select_hold = 8'd0;
reg        src_write_hold = 1'b0;
reg        src_read_hold = 1'b0;
reg        src_query_hold = 1'b0;
reg        src_restore_hold = 1'b0;
reg        src_request_toggle = 1'b0;
reg        src_pending = 1'b0;
reg        src_ack_seen = 1'b0;
reg        src_command_seen = 1'b0;

reg [63:0] dst_response_hold = 64'd0;
reg        dst_ack_toggle = 1'b0;
reg        dst_request_seen = 1'b0;
reg        dst_waiting_ack = 1'b0;

(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg dst_request_sync0 = 1'b0;
(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg dst_request_sync1 = 1'b0;
(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg src_ack_sync0 = 1'b0;
(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg src_ack_sync1 = 1'b0;

wire src_selected = (src_bus.select < 8'd64) &&
                    SELECT_MASK[src_bus.select[5:0]] &&
                    src_select_mask[src_bus.select[5:0]];
wire src_command = src_selected &&
                   (src_bus.query || src_bus.read || src_bus.write);

always @(posedge src_clk) begin
    if (src_reset) begin
        src_data_hold <= 64'd0;
        src_addr_hold <= 32'd0;
        src_select_hold <= 8'd0;
        src_write_hold <= 1'b0;
        src_read_hold <= 1'b0;
        src_query_hold <= 1'b0;
        src_restore_hold <= 1'b0;
        src_request_toggle <= 1'b0;
        src_pending <= 1'b0;
        src_ack_seen <= 1'b0;
        src_command_seen <= 1'b0;
        src_ack_sync0 <= 1'b0;
        src_ack_sync1 <= 1'b0;
        src_bus.data_out <= 64'd0;
        src_bus.ack <= 1'b0;
    end else begin
        src_ack_sync0 <= dst_ack_toggle;
        src_ack_sync1 <= src_ack_sync0;
        src_bus.ack <= 1'b0;

        if (!src_command)
            src_command_seen <= 1'b0;

        if (src_command && !src_pending && !src_command_seen) begin
            src_data_hold <= src_bus.data;
            src_addr_hold <= src_bus.addr;
            src_select_hold <= src_bus.select;
            src_write_hold <= src_bus.write;
            src_read_hold <= src_bus.read;
            src_query_hold <= src_bus.query;
            src_restore_hold <= src_restore_enable;
            src_request_toggle <= ~src_request_toggle;
            src_pending <= 1'b1;
            src_command_seen <= 1'b1;
        end

        if (src_pending && (src_ack_sync1 != src_ack_seen)) begin
            src_ack_seen <= src_ack_sync1;
            src_bus.data_out <= dst_response_hold;
            src_bus.ack <= 1'b1;
            src_pending <= 1'b0;
        end
    end
end

always @(posedge dst_clk) begin
    if (dst_reset) begin
        dst_request_sync0 <= 1'b0;
        dst_request_sync1 <= 1'b0;
        dst_request_seen <= 1'b0;
        dst_waiting_ack <= 1'b0;
        dst_response_hold <= 64'd0;
        dst_ack_toggle <= 1'b0;
        dst_restore_enable <= 1'b0;
        dst_bus.data <= 64'd0;
        dst_bus.addr <= 32'd0;
        dst_bus.select <= 8'd0;
        dst_bus.write <= 1'b0;
        dst_bus.read <= 1'b0;
        dst_bus.query <= 1'b0;
    end else begin
        dst_request_sync0 <= src_request_toggle;
        dst_request_sync1 <= dst_request_sync0;
        dst_bus.write <= 1'b0;
        dst_bus.read <= 1'b0;
        dst_bus.query <= 1'b0;

        if (!dst_waiting_ack && (dst_request_sync1 != dst_request_seen)) begin
            dst_request_seen <= dst_request_sync1;
            dst_bus.data <= src_data_hold;
            dst_bus.addr <= src_addr_hold;
            dst_bus.select <= src_select_hold;
            dst_bus.write <= src_write_hold;
            dst_bus.read <= src_read_hold;
            dst_bus.query <= src_query_hold;
            dst_restore_enable <= src_restore_hold;
            dst_waiting_ack <= 1'b1;
        end

        if (dst_waiting_ack && dst_bus.ack) begin
            dst_response_hold <= dst_bus.data_out;
            dst_ack_toggle <= ~dst_ack_toggle;
            dst_waiting_ack <= 1'b0;
        end
    end
end

endmodule

module CaveSaveStateCpuControlCdc (
    input wire src_clk,
    input wire src_reset,
    input wire src_capture_request,
    input wire src_hold,
    input wire src_restore_start,
    input wire src_restore_commit,
    input wire src_release,
    input wire src_recovery_reset,
    output wire src_capture_done,
    output wire src_cpu_idle,
    output wire src_clients_idle,
    output reg  src_restore_commit_done,
    output wire src_reconstruction_ready,

    input wire dst_clk,
    input wire dst_reset,
    output wire dst_capture_request,
    output wire dst_hold,
    output reg  dst_restore_start,
    output reg  dst_restore_commit,
    output reg  dst_release,
    output wire dst_recovery_reset,
    input wire dst_capture_done,
    input wire dst_cpu_idle,
    input wire dst_clients_idle,
    input wire dst_restore_commit_done,
    input wire dst_reconstruction_ready
);

reg src_restore_start_toggle = 1'b0;
reg src_restore_commit_toggle = 1'b0;
reg src_release_toggle = 1'b0;
reg dst_restore_start_seen = 1'b0;
reg dst_restore_commit_seen = 1'b0;
reg dst_release_seen = 1'b0;
reg dst_commit_done_toggle = 1'b0;
reg src_commit_done_seen = 1'b0;

(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg dst_capture_request_sync0 = 1'b0;
(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg dst_capture_request_sync1 = 1'b0;
(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg dst_hold_sync0 = 1'b0;
(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg dst_hold_sync1 = 1'b0;
(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg dst_recovery_reset_sync0 = 1'b0;
(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg dst_recovery_reset_sync1 = 1'b0;
(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg dst_restore_start_sync0 = 1'b0;
(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg dst_restore_start_sync1 = 1'b0;
(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg dst_restore_commit_sync0 = 1'b0;
(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg dst_restore_commit_sync1 = 1'b0;
(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg dst_release_sync0 = 1'b0;
(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg dst_release_sync1 = 1'b0;

(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg src_capture_done_sync0 = 1'b0;
(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg src_capture_done_sync1 = 1'b0;
(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg src_cpu_idle_sync0 = 1'b0;
(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg src_cpu_idle_sync1 = 1'b0;
(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg src_clients_idle_sync0 = 1'b0;
(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg src_clients_idle_sync1 = 1'b0;
(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg src_reconstruction_ready_sync0 = 1'b0;
(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg src_reconstruction_ready_sync1 = 1'b0;
(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg src_commit_done_sync0 = 1'b0;
(* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
reg src_commit_done_sync1 = 1'b0;

assign dst_capture_request = dst_capture_request_sync1;
assign dst_hold = dst_hold_sync1;
assign dst_recovery_reset = dst_recovery_reset_sync1;
assign src_capture_done = src_capture_done_sync1;
assign src_cpu_idle = src_cpu_idle_sync1;
assign src_clients_idle = src_clients_idle_sync1;
assign src_reconstruction_ready = src_reconstruction_ready_sync1;

always @(posedge src_clk) begin
    if (src_reset) begin
        src_restore_start_toggle <= 1'b0;
        src_restore_commit_toggle <= 1'b0;
        src_release_toggle <= 1'b0;
        src_capture_done_sync0 <= 1'b0;
        src_capture_done_sync1 <= 1'b0;
        src_cpu_idle_sync0 <= 1'b0;
        src_cpu_idle_sync1 <= 1'b0;
        src_clients_idle_sync0 <= 1'b0;
        src_clients_idle_sync1 <= 1'b0;
        src_reconstruction_ready_sync0 <= 1'b0;
        src_reconstruction_ready_sync1 <= 1'b0;
        src_commit_done_sync0 <= 1'b0;
        src_commit_done_sync1 <= 1'b0;
        src_commit_done_seen <= 1'b0;
        src_restore_commit_done <= 1'b0;
    end else begin
        if (src_restore_start)
            src_restore_start_toggle <= ~src_restore_start_toggle;
        if (src_restore_commit)
            src_restore_commit_toggle <= ~src_restore_commit_toggle;
        if (src_release)
            src_release_toggle <= ~src_release_toggle;

        src_capture_done_sync0 <= dst_capture_done;
        src_capture_done_sync1 <= src_capture_done_sync0;
        src_cpu_idle_sync0 <= dst_cpu_idle;
        src_cpu_idle_sync1 <= src_cpu_idle_sync0;
        src_clients_idle_sync0 <= dst_clients_idle;
        src_clients_idle_sync1 <= src_clients_idle_sync0;
        src_reconstruction_ready_sync0 <= dst_reconstruction_ready;
        src_reconstruction_ready_sync1 <= src_reconstruction_ready_sync0;
        src_commit_done_sync0 <= dst_commit_done_toggle;
        src_commit_done_sync1 <= src_commit_done_sync0;

        src_restore_commit_done <= 1'b0;
        if (src_commit_done_sync1 != src_commit_done_seen) begin
            src_commit_done_seen <= src_commit_done_sync1;
            src_restore_commit_done <= 1'b1;
        end
    end
end

always @(posedge dst_clk) begin
    if (dst_reset) begin
        dst_capture_request_sync0 <= 1'b0;
        dst_capture_request_sync1 <= 1'b0;
        dst_hold_sync0 <= 1'b0;
        dst_hold_sync1 <= 1'b0;
        dst_recovery_reset_sync0 <= 1'b0;
        dst_recovery_reset_sync1 <= 1'b0;
        dst_restore_start_sync0 <= 1'b0;
        dst_restore_start_sync1 <= 1'b0;
        dst_restore_commit_sync0 <= 1'b0;
        dst_restore_commit_sync1 <= 1'b0;
        dst_release_sync0 <= 1'b0;
        dst_release_sync1 <= 1'b0;
        dst_restore_start_seen <= 1'b0;
        dst_restore_commit_seen <= 1'b0;
        dst_release_seen <= 1'b0;
        dst_commit_done_toggle <= 1'b0;
        dst_restore_start <= 1'b0;
        dst_restore_commit <= 1'b0;
        dst_release <= 1'b0;
    end else begin
        dst_capture_request_sync0 <= src_capture_request;
        dst_capture_request_sync1 <= dst_capture_request_sync0;
        dst_hold_sync0 <= src_hold;
        dst_hold_sync1 <= dst_hold_sync0;
        dst_recovery_reset_sync0 <= src_recovery_reset;
        dst_recovery_reset_sync1 <= dst_recovery_reset_sync0;
        dst_restore_start_sync0 <= src_restore_start_toggle;
        dst_restore_start_sync1 <= dst_restore_start_sync0;
        dst_restore_commit_sync0 <= src_restore_commit_toggle;
        dst_restore_commit_sync1 <= dst_restore_commit_sync0;
        dst_release_sync0 <= src_release_toggle;
        dst_release_sync1 <= dst_release_sync0;

        dst_restore_start <= 1'b0;
        dst_restore_commit <= 1'b0;
        dst_release <= 1'b0;

        if (dst_restore_start_sync1 != dst_restore_start_seen) begin
            dst_restore_start_seen <= dst_restore_start_sync1;
            dst_restore_start <= 1'b1;
        end
        if (dst_restore_commit_sync1 != dst_restore_commit_seen) begin
            dst_restore_commit_seen <= dst_restore_commit_sync1;
            dst_restore_commit <= 1'b1;
        end
        if (dst_release_sync1 != dst_release_seen) begin
            dst_release_seen <= dst_release_sync1;
            dst_release <= 1'b1;
        end
        if (dst_restore_commit_done)
            dst_commit_done_toggle <= ~dst_commit_done_toggle;
    end
end

endmodule
