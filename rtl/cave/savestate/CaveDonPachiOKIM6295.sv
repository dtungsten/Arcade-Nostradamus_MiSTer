// DonPachi-only stateful OKIM6295 path. The normal Cave OKI path remains
// untouched for Power Instinct 2 and Gogetsuji Legends.
module CaveDonPachiOKIM6295 #(
    parameter [7:0] SS_IDX = 8'd36,
    parameter [16:0] CEN_STEP = 17'h0873,
    parameter FIR_COEFFS = "jt6295_up4_soft.hex"
) (
    input               clock,
    input               reset,
    input               io_ss,
    input               io_cpu_wr,
    input        [7:0]  io_cpu_din,
    output       [7:0]  io_cpu_dout,
    output              io_rom_rd,
    output       [17:0] io_rom_addr,
    input        [7:0]  io_rom_dout,
    input               io_rom_valid,
    output              io_audio_valid,
    output       [13:0] io_audio,
    input               io_ss_hold,
    input               io_ss_restore_enable,
    output              io_ss_idle,
    cave_ssbus_if.slave  io_ssbus
);

reg         adpcm_cen;
reg  [15:0] cen_accumulator;
reg  [15:0] fir_din;
reg  [2:0]  hold_stable_count;

wire [16:0] cen_next = {1'b0, cen_accumulator} + CEN_STEP;
wire        core_cen = io_ss_hold ? 1'b0 : adpcm_cen;
wire        core_cen1;
wire        core_cen4;
wire        core_sample;
wire signed [13:0] core_sound;

wire        auto_rd;
wire        auto_wr;
wire [31:0] auto_data_in;
wire [7:0]  auto_device_idx;
wire [15:0] auto_state_idx;
wire [31:0] auto_data_out;
wire        auto_ack;

wire        wrapper_restore_wr;
wire [31:0] wrapper_restore_data;
wire        fir_state_wr;
wire [31:0] fir_state_din;
wire [31:0] fir_state_dout;
wire [6:0]  fir_mem_addr;
wire        fir_mem_wr;
wire [15:0] fir_mem_din;
wire [15:0] fir_mem_dout;
wire        fir_idle;
wire signed [15:0] fir_dout;

wire [31:0] wrapper_state = {fir_din, cen_accumulator};

always @(posedge clock) begin
    if (reset) begin
        cen_accumulator <= 16'd0;
        adpcm_cen <= 1'b0;
    end else if (wrapper_restore_wr) begin
        cen_accumulator <= wrapper_restore_data[15:0];
        adpcm_cen <= 1'b0;
    end else if (io_ss_hold) begin
        adpcm_cen <= 1'b0;
    end else begin
        cen_accumulator <= cen_next[15:0];
        adpcm_cen <= cen_next[16];
    end
end

always @(posedge clock) begin
    if (reset)
        fir_din <= 16'd0;
    else if (wrapper_restore_wr)
        fir_din <= wrapper_restore_data[31:16];
    else if (!io_ss_hold && core_cen4)
        fir_din <= core_cen1 ? {{1{core_sound[13]}}, core_sound, 1'b0}
                             : 16'd0;
end

always @(posedge clock) begin
    if (reset || !io_ss_hold || !fir_idle)
        hold_stable_count <= 3'd0;
    else if (!(&hold_stable_count))
        hold_stable_count <= hold_stable_count + 3'd1;
end

assign io_ss_idle = io_ss_hold & (&hold_stable_count);
assign io_rom_rd = 1'b1;
assign io_audio_valid = core_cen4;
assign io_audio = fir_dout[13:0];

cave_donpachi_ss_jt6295 #(
    .INTERPOL (0),
    .SAMPLE   (1)
) decoder (
    .rst                     (reset),
    .clk                     (clock),
    .cen                     (core_cen),
    .ss                      (io_ss),
    .wrn                     (~(io_cpu_wr & ~io_ss_hold)),
    .din                     (io_cpu_din),
    .dout                    (io_cpu_dout),
    .rom_addr                (io_rom_addr),
    .rom_data                (io_rom_dout),
    .rom_ok                  (io_rom_valid),
    .sound                   (core_sound),
    .sample                  (core_sample),
    .cen_sr_out              (core_cen1),
    .cen_sr4_out             (core_cen4),
    .auto_ss_rd              (auto_rd),
    .auto_ss_wr              (auto_wr),
    .auto_ss_data_in         (auto_data_in),
    .auto_ss_device_idx      (auto_device_idx),
    .auto_ss_state_idx       (auto_state_idx),
    .auto_ss_base_device_idx (8'd0),
    .auto_ss_data_out        (auto_data_out),
    .auto_ss_ack             (auto_ack)
);

CaveDonPachiOkiFir #(
    .COEFFS (FIR_COEFFS)
) interpolator (
    .clock         (clock),
    .reset         (reset),
    .sample        (core_cen4),
    .din           (fir_din),
    .dout          (fir_dout),
    .ss_hold       (io_ss_hold),
    .ss_idle       (fir_idle),
    .ss_state_wr   (fir_state_wr),
    .ss_state_din  (fir_state_din),
    .ss_state_dout (fir_state_dout),
    .ss_mem_addr   (fir_mem_addr),
    .ss_mem_wr     (fir_mem_wr),
    .ss_mem_din    (fir_mem_din),
    .ss_mem_dout   (fir_mem_dout)
);

CaveDonPachiOkiStatePort #(
    .SS_IDX (SS_IDX)
) state_port (
    .clock                (clock),
    .reset                (reset),
    .state_enable         (io_ss_idle),
    .restore_enable       (io_ss_restore_enable),
    .wrapper_state        (wrapper_state),
    .wrapper_restore_wr   (wrapper_restore_wr),
    .wrapper_restore_data (wrapper_restore_data),
    .fir_state_dout       (fir_state_dout),
    .fir_state_wr         (fir_state_wr),
    .fir_state_din        (fir_state_din),
    .fir_mem_addr         (fir_mem_addr),
    .fir_mem_wr           (fir_mem_wr),
    .fir_mem_din          (fir_mem_din),
    .fir_mem_dout         (fir_mem_dout),
    .auto_rd              (auto_rd),
    .auto_wr              (auto_wr),
    .auto_data_in         (auto_data_in),
    .auto_device_idx      (auto_device_idx),
    .auto_state_idx       (auto_state_idx),
    .auto_data_out        (auto_data_out),
    .auto_ack             (auto_ack),
    .ssbus                (io_ssbus)
);

wire _unused_core_sample = core_sample;

endmodule

module CaveDonPachiOkiFir #(
    parameter COEFFS = "jt6295_up4_soft.hex",
    parameter [7:0] KMAX = 8'd69
) (
    input                    clock,
    input                    reset,
    input                    sample,
    input signed      [15:0] din,
    output reg signed [15:0] dout,
    input                    ss_hold,
    output                   ss_idle,
    input                    ss_state_wr,
    input             [31:0] ss_state_din,
    output            [31:0] ss_state_dout,
    input             [6:0]  ss_mem_addr,
    input                    ss_mem_wr,
    input             [15:0] ss_mem_din,
    output            [15:0] ss_mem_dout
);

reg         [7:0]  pt_wr;
reg         [7:0]  pt_rd;
reg         [7:0]  cnt;
reg         [8:0]  rd_addr;
reg                st;
reg                wt_ram;
reg                restore_wait_sample;
reg                hold_canonicalized;
reg signed  [35:0] acc;
reg signed  [15:0] coeff;
reg signed  [31:0] product;
wire signed [15:0] ram_dout;
wire        [15:0] port0_dout;

wire [8:0] port0_addr = ss_hold
    ? {1'b1, 1'b0, ss_mem_addr}
    : {1'b1, pt_wr};
wire [15:0] port0_data = ss_hold ? ss_mem_din : din;
wire        port0_we = ss_hold ? ss_mem_wr : sample;

function signed [35:0] extend_product;
    input signed [31:0] value;
    begin
        extend_product = {{4{value[31]}}, value};
    end
endfunction

function [7:0] loop_inc;
    input [7:0] value;
    begin
        loop_inc = value == (KMAX - 8'd1) ? 8'd0 : value + 8'd1;
    end
endfunction

function signed [15:0] saturate;
    input [35:0] value;
    begin
        saturate = value[35:30] == {6{value[29]}}
            ? value[29:14]
            : {value[35], {15{~value[35]}}};
    end
endfunction

always @* begin
    rd_addr = st == 1'b0 ? {1'b0, cnt} : {1'b1, pt_rd};
end

jtframe_dual_ram #(
    .dw      (16),
    .aw      (9),
    .synfile (COEFFS)
) state_ram (
    .clk0  (clock),
    .clk1  (clock),
    .data0 (port0_data),
    .addr0 (port0_addr),
    .we0   (port0_we),
    .q0    (port0_dout),
    .data1 (16'd0),
    .addr1 (rd_addr),
    .we1   (1'b0),
    .q1    (ram_dout)
);

always @(posedge clock or posedge reset) begin
    if (reset) begin
        dout <= 16'd0;
        pt_rd <= 8'd0;
        pt_wr <= 8'd0;
        cnt <= 8'd0;
        st <= 1'b0;
        wt_ram <= 1'b0;
        restore_wait_sample <= 1'b0;
        hold_canonicalized <= 1'b0;
        acc <= 36'd0;
        product <= 32'd0;
        coeff <= 16'd0;
    end else if (ss_state_wr) begin
        pt_wr <= ss_state_din[7:0];
        dout <= ss_state_din[23:8];
        pt_rd <= ss_state_din[7:0];
        cnt <= KMAX;
        st <= 1'b0;
        wt_ram <= 1'b0;
        restore_wait_sample <= 1'b1;
        hold_canonicalized <= 1'b1;
        acc <= 36'd0;
        product <= 32'd0;
        coeff <= 16'd0;
    end else if (ss_hold && ss_idle) begin
        if (!hold_canonicalized) begin
            pt_rd <= pt_wr;
            cnt <= KMAX;
            st <= 1'b0;
            wt_ram <= 1'b0;
            restore_wait_sample <= 1'b1;
            hold_canonicalized <= 1'b1;
            acc <= 36'd0;
            product <= 32'd0;
            coeff <= 16'd0;
        end
    end else begin
        hold_canonicalized <= 1'b0;
        if (sample) begin
            restore_wait_sample <= 1'b0;
            pt_rd <= pt_wr;
            cnt <= 8'd0;
            pt_wr <= loop_inc(pt_wr);
            acc <= 36'd0;
            product <= 32'd0;
            st <= 1'b0;
            wt_ram <= 1'b1;
        end else if (!restore_wait_sample) begin
            wt_ram <= ~wt_ram;
            if (!wt_ram) begin
                if (cnt < KMAX) begin
                    st <= ~st;
                    if (st == 1'b0) begin
                        coeff <= ram_dout;
                    end else begin
                        product <= ram_dout * coeff;
                        acc <= acc + extend_product(product);
                        cnt <= cnt + 8'd1;
                        pt_rd <= loop_inc(pt_rd);
                    end
                end else begin
                    dout <= saturate(acc);
                end
            end
        end
    end
end

assign ss_idle = cnt >= KMAX;
assign ss_state_dout = {8'd0, dout, pt_wr};
assign ss_mem_dout = port0_dout;

endmodule

module CaveDonPachiOkiStatePort #(
    parameter [7:0] SS_IDX = 8'd36
) (
    input               clock,
    input               reset,
    input               state_enable,
    input               restore_enable,
    input        [31:0] wrapper_state,
    output reg          wrapper_restore_wr,
    output reg   [31:0] wrapper_restore_data,
    input        [31:0] fir_state_dout,
    output reg          fir_state_wr,
    output reg   [31:0] fir_state_din,
    output reg   [6:0]  fir_mem_addr,
    output reg          fir_mem_wr,
    output reg   [15:0] fir_mem_din,
    input        [15:0] fir_mem_dout,
    output reg          auto_rd,
    output reg          auto_wr,
    output reg   [31:0] auto_data_in,
    output reg   [7:0]  auto_device_idx,
    output reg   [15:0] auto_state_idx,
    input        [31:0] auto_data_out,
    input               auto_ack,
    cave_ssbus_if.slave  ssbus
);

localparam [31:0] AUTO_WORDS = 32'd75;
localparam [31:0] WRAPPER_WORD = 32'd75;
localparam [31:0] FIR_STATE_WORD = 32'd76;
localparam [31:0] FIR_MEMORY_BASE = 32'd77;
localparam [31:0] FIR_MEMORY_WORDS = 32'd35;
localparam [31:0] WORD_COUNT = 32'd112;

localparam [3:0] ST_IDLE = 4'd0;
localparam [3:0] ST_AUTO_READ = 4'd1;
localparam [3:0] ST_AUTO_WRITE = 4'd2;
localparam [3:0] ST_DIRECT_WRITE = 4'd3;
localparam [3:0] ST_MEM_READ_0_WAIT = 4'd4;
localparam [3:0] ST_MEM_READ_0_CAPTURE = 4'd5;
localparam [3:0] ST_MEM_READ_1_WAIT = 4'd6;
localparam [3:0] ST_MEM_READ_1_CAPTURE = 4'd7;
localparam [3:0] ST_MEM_WRITE_0 = 4'd8;
localparam [3:0] ST_MEM_WRITE_1 = 4'd9;
localparam [3:0] ST_WAIT_REQUEST = 4'd10;

reg [3:0] state;
reg [31:0] request_addr;
reg [31:0] request_data;
reg [15:0] memory_word_0;
reg        memory_second_valid;

wire selected = ssbus.select == SS_IDX;
wire request_active = ssbus.query || ssbus.read || ssbus.write;

function [23:0] auto_location;
    input [6:0] flat_index;
    begin
        if (flat_index == 7'd0)
            auto_location = {8'd1, 16'd0};
        else if (flat_index <= 7'd2)
            auto_location = {8'd2, 9'd0, flat_index - 7'd1};
        else if (flat_index <= 7'd7)
            auto_location = {8'd3, 9'd0, flat_index - 7'd3};
        else if (flat_index == 7'd8)
            auto_location = {8'd4, 16'd0};
        else if (flat_index <= 7'd50)
            auto_location = {8'd5, 9'd0, flat_index - 7'd9};
        else if (flat_index <= 7'd56)
            auto_location = {8'd6, 9'd0, flat_index - 7'd51};
        else if (flat_index == 7'd57)
            auto_location = {8'd7, 16'd0};
        else if (flat_index <= 7'd61)
            auto_location = {8'd8, 9'd0, flat_index - 7'd58};
        else if (flat_index <= 7'd73)
            auto_location = {8'd9, 9'd0, flat_index - 7'd62};
        else
            auto_location = {8'd10, 16'd0};
    end
endfunction

reg [23:0] mapped_location;
reg [7:0] history_index;

always @(posedge clock) begin
    ssbus.ack <= 1'b0;
    wrapper_restore_wr <= 1'b0;
    fir_state_wr <= 1'b0;

    if (reset) begin
        state <= ST_IDLE;
        ssbus.data_out <= 64'd0;
        wrapper_restore_data <= 32'd0;
        fir_state_din <= 32'd0;
        fir_mem_addr <= 7'd0;
        fir_mem_wr <= 1'b0;
        fir_mem_din <= 16'd0;
        auto_rd <= 1'b0;
        auto_wr <= 1'b0;
        auto_data_in <= 32'd0;
        auto_device_idx <= 8'd0;
        auto_state_idx <= 16'd0;
        request_addr <= 32'd0;
        request_data <= 32'd0;
        memory_word_0 <= 16'd0;
        memory_second_valid <= 1'b0;
        mapped_location <= 24'd0;
        history_index <= 8'd0;
    end else begin
        case (state)
            ST_IDLE: begin
                auto_rd <= 1'b0;
                auto_wr <= 1'b0;
                fir_mem_wr <= 1'b0;

                if (selected && state_enable && ssbus.query) begin
                    ssbus.data_out <= {SS_IDX, 22'd0, 2'd2, WORD_COUNT};
                    ssbus.ack <= 1'b1;
                    state <= ST_WAIT_REQUEST;
                end else if (selected && state_enable &&
                             (ssbus.read || ssbus.write)) begin
                    request_addr <= ssbus.addr;
                    request_data <= ssbus.data[31:0];

                    if (ssbus.addr >= WORD_COUNT) begin
                        ssbus.data_out <= 64'd0;
                        ssbus.ack <= 1'b1;
                        state <= ST_WAIT_REQUEST;
                    end else if (ssbus.addr < AUTO_WORDS) begin
                        mapped_location =
                            auto_location(7'd74 - ssbus.addr[6:0]);
                        auto_device_idx <= mapped_location[23:16];
                        auto_state_idx <= mapped_location[15:0];
                        auto_data_in <= ssbus.data[31:0];
                        if (ssbus.write) begin
                            if (restore_enable) begin
                                auto_wr <= 1'b1;
                                state <= ST_AUTO_WRITE;
                            end else begin
                                ssbus.ack <= 1'b1;
                                state <= ST_WAIT_REQUEST;
                            end
                        end else begin
                            auto_rd <= 1'b1;
                            state <= ST_AUTO_READ;
                        end
                    end else if (ssbus.addr == WRAPPER_WORD) begin
                        if (ssbus.write) begin
                            if (restore_enable) begin
                                wrapper_restore_data <= ssbus.data[31:0];
                                wrapper_restore_wr <= 1'b1;
                                state <= ST_DIRECT_WRITE;
                            end else begin
                                ssbus.ack <= 1'b1;
                                state <= ST_WAIT_REQUEST;
                            end
                        end else begin
                            ssbus.data_out <= {32'd0, wrapper_state};
                            ssbus.ack <= 1'b1;
                            state <= ST_WAIT_REQUEST;
                        end
                    end else if (ssbus.addr == FIR_STATE_WORD) begin
                        if (ssbus.write) begin
                            if (restore_enable) begin
                                fir_state_din <= ssbus.data[31:0];
                                fir_state_wr <= 1'b1;
                                state <= ST_DIRECT_WRITE;
                            end else begin
                                ssbus.ack <= 1'b1;
                                state <= ST_WAIT_REQUEST;
                            end
                        end else begin
                            ssbus.data_out <= {32'd0, fir_state_dout};
                            ssbus.ack <= 1'b1;
                            state <= ST_WAIT_REQUEST;
                        end
                    end else begin
                        history_index =
                            (ssbus.addr - FIR_MEMORY_BASE) << 1;
                        fir_mem_addr <= history_index[6:0];
                        memory_second_valid <= history_index < 8'd68;
                        if (ssbus.write) begin
                            if (restore_enable) begin
                                fir_mem_din <= ssbus.data[15:0];
                                fir_mem_wr <= 1'b1;
                                state <= ST_MEM_WRITE_0;
                            end else begin
                                ssbus.ack <= 1'b1;
                                state <= ST_WAIT_REQUEST;
                            end
                        end else begin
                            state <= ST_MEM_READ_0_WAIT;
                        end
                    end
                end
            end

            ST_AUTO_READ: begin
                if (auto_ack) begin
                    auto_rd <= 1'b0;
                    ssbus.data_out <= {32'd0, auto_data_out};
                    ssbus.ack <= 1'b1;
                    state <= ST_WAIT_REQUEST;
                end
            end

            ST_AUTO_WRITE: begin
                auto_wr <= 1'b0;
                ssbus.ack <= 1'b1;
                state <= ST_WAIT_REQUEST;
            end

            ST_DIRECT_WRITE: begin
                ssbus.ack <= 1'b1;
                state <= ST_WAIT_REQUEST;
            end

            ST_MEM_READ_0_WAIT: begin
                state <= ST_MEM_READ_0_CAPTURE;
            end

            ST_MEM_READ_0_CAPTURE: begin
                memory_word_0 <= fir_mem_dout;
                fir_mem_addr <= fir_mem_addr + 7'd1;
                state <= ST_MEM_READ_1_WAIT;
            end

            ST_MEM_READ_1_WAIT: begin
                state <= ST_MEM_READ_1_CAPTURE;
            end

            ST_MEM_READ_1_CAPTURE: begin
                ssbus.data_out <= {
                    32'd0,
                    memory_second_valid ? fir_mem_dout : 16'd0,
                    memory_word_0
                };
                ssbus.ack <= 1'b1;
                state <= ST_WAIT_REQUEST;
            end

            ST_MEM_WRITE_0: begin
                if (memory_second_valid) begin
                    fir_mem_addr <= fir_mem_addr + 7'd1;
                    fir_mem_din <= request_data[31:16];
                    fir_mem_wr <= 1'b1;
                    state <= ST_MEM_WRITE_1;
                end else begin
                    fir_mem_wr <= 1'b0;
                    ssbus.ack <= 1'b1;
                    state <= ST_WAIT_REQUEST;
                end
            end

            ST_MEM_WRITE_1: begin
                fir_mem_wr <= 1'b0;
                ssbus.ack <= 1'b1;
                state <= ST_WAIT_REQUEST;
            end

            ST_WAIT_REQUEST: begin
                auto_rd <= 1'b0;
                auto_wr <= 1'b0;
                fir_mem_wr <= 1'b0;
                if (!request_active)
                    state <= ST_IDLE;
            end

            default: state <= ST_IDLE;
        endcase
    end
end

endmodule
