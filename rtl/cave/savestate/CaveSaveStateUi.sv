// Cave-local MiSTer save-state UI decoder.
module CaveSaveStateUi #(
    parameter integer INFO_TIMEOUT_BITS = 25
) (
    input wire        clk,
    input wire [10:0] ps2_key,
    input wire        allow_ss,
    input wire        joy_ss,
    input wire        joy_right,
    input wire        joy_left,
    input wire        joy_down,
    input wire        joy_up,
    input wire [1:0]  status_slot,
    input wire        autoinc_slot,
    input wire [1:0]  osd_saveload,
    output reg        save_request,
    output reg        load_request,
    output reg        info_request,
    output reg [7:0]  info,
    output reg        status_update,
    output wire [1:0] selected_slot
);

reg [1:0] slot = 2'd0;
reg last_right = 1'b0;
reg last_left = 1'b0;
reg last_down = 1'b0;
reg last_up = 1'b0;
reg [INFO_TIMEOUT_BITS-1:0] info_wait = {INFO_TIMEOUT_BITS{1'b0}};
reg [1:0] last_osd_setting = 2'd0;
reg old_key_state = 1'b0;
reg alt = 1'b0;
reg [1:0] old_osd_saveload = 2'd0;
reg save_event;
reg load_event;
reg slot_event;
reg [1:0] request_slot;
reg [1:0] slot_info_value;

assign selected_slot = slot;

wire pressed = ps2_key[9];

always_ff @(posedge clk) begin
    old_key_state <= ps2_key[10];
    last_right <= joy_right;
    last_left <= joy_left;
    last_down <= joy_down;
    last_up <= joy_up;

    save_event = 1'b0;
    load_event = 1'b0;
    slot_event = 1'b0;
    request_slot = slot;
    slot_info_value = slot;

    save_request <= 1'b0;
    load_request <= 1'b0;
    info_request <= 1'b0;
    status_update <= 1'b0;

    if (allow_ss) begin
        if (old_key_state != ps2_key[10]) begin
            case (ps2_key[7:0])
                8'h11: alt <= pressed;
                8'h05: begin
                    save_event = pressed && alt;
                    load_event = pressed && !alt;
                    request_slot = 2'd0;
                    slot <= 2'd0;
                    status_update <= 1'b1;
                end
                8'h06: begin
                    save_event = pressed && alt;
                    load_event = pressed && !alt;
                    request_slot = 2'd1;
                    slot <= 2'd1;
                    status_update <= 1'b1;
                end
                8'h04: begin
                    save_event = pressed && alt;
                    load_event = pressed && !alt;
                    request_slot = 2'd2;
                    slot <= 2'd2;
                    status_update <= 1'b1;
                end
                8'h0c: begin
                    save_event = pressed && alt;
                    load_event = pressed && !alt;
                    request_slot = 2'd3;
                    slot <= 2'd3;
                    status_update <= 1'b1;
                end
                default: begin end
            endcase
        end

        last_osd_setting <= status_slot;
        if (last_osd_setting != status_slot) begin
            slot <= status_slot;
            slot_info_value = status_slot;
            status_update <= 1'b1;
        end

        if (joy_ss) begin
            info_wait <= info_wait + {{(INFO_TIMEOUT_BITS-1){1'b0}}, 1'b1};
            if (info_wait[INFO_TIMEOUT_BITS-1]) begin
                info <= 8'd1;
                info_request <= 1'b1;
                info_wait <= {INFO_TIMEOUT_BITS{1'b0}};
            end
            if (joy_right && !last_right && slot < 2'd3) begin
                slot <= slot + 2'd1;
                slot_info_value = slot + 2'd1;
                status_update <= 1'b1;
                slot_event = 1'b1;
                info_wait <= {INFO_TIMEOUT_BITS{1'b0}};
            end
            if (joy_left && !last_left && slot > 2'd0) begin
                slot <= slot - 2'd1;
                slot_info_value = slot - 2'd1;
                status_update <= 1'b1;
                slot_event = 1'b1;
                info_wait <= {INFO_TIMEOUT_BITS{1'b0}};
            end
            if (joy_down && !last_down) begin
                save_event = 1'b1;
                request_slot = slot;
                info_wait <= {INFO_TIMEOUT_BITS{1'b0}};
                if (autoinc_slot) begin
                    slot <= slot + 2'd1;
                    status_update <= 1'b1;
                end
            end
            if (joy_up && !last_up) begin
                load_event = 1'b1;
                request_slot = slot;
                info_wait <= {INFO_TIMEOUT_BITS{1'b0}};
            end
        end else begin
            info_wait <= {INFO_TIMEOUT_BITS{1'b0}};
        end

        old_osd_saveload <= osd_saveload;
        if (!old_osd_saveload[0] && osd_saveload[0]) begin
            save_event = 1'b1;
            request_slot = slot;
            if (autoinc_slot) begin
                slot <= slot + 2'd1;
                status_update <= 1'b1;
            end
        end
        if (!old_osd_saveload[1] && osd_saveload[1])
            begin
                load_event = 1'b1;
                request_slot = slot;
            end

        if (slot_event) begin
            info <= 8'd2 + slot_info_value;
            info_request <= 1'b1;
        end
        if (load_event || save_event) begin
            info <= 8'd6 + {request_slot, load_event};
            info_request <= 1'b1;
        end

        save_request <= save_event;
        load_request <= load_event;
    end
end

endmodule
