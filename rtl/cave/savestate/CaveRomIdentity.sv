// ROM-set identity sampled directly from the MRA's HPS-DDR image.
module CaveRomIdentity (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire [3:0]  game_index,
    output reg         busy,
    output reg         done,
    output wire        mem_rd,
    output wire [31:0] mem_addr,
    input  wire [63:0] mem_dout,
    input  wire        mem_wait_n,
    input  wire        mem_valid,
    input  wire        mem_burst_done,
    output reg         identity_valid,
    output reg  [31:0] rom_size,
    output reg  [63:0] signature
);

localparam [31:0] ROM_DDR_BASE = 32'h3000_0000;
localparam [3:0] GAME_DFEVERON = 4'd0;
localparam [3:0] GAME_DDONPACH = 4'd1;
localparam [3:0] GAME_DONPACHI = 4'd2;
localparam [3:0] GAME_ESPRADE  = 4'd3;
localparam [3:0] GAME_UOPOKO   = 4'd4;
localparam [3:0] GAME_GUWANGE  = 4'd5;
localparam [3:0] GAME_GAIA     = 4'd6;
localparam [3:0] GAME_PWRINST2 = 4'd7;
localparam [3:0] GAME_PLEGENDS = 4'd8;

localparam [31:0] DFEVERON_ROM_SIZE = 32'h0110_0080;
localparam [31:0] DDONPACH_ROM_SIZE = 32'h0130_0080;
localparam [31:0] DONPACHI_ROM_SIZE = 32'h009c_0080;
localparam [31:0] ESPRADE_ROM_SIZE  = 32'h0290_0080;
localparam [31:0] UOPOKO_ROM_SIZE   = 32'h00b0_0080;
localparam [31:0] GUWANGE_ROM_SIZE = 32'h0350_0080;
localparam [31:0] GAIA_ROM_SIZE     = 32'h0210_0000;
localparam [31:0] PWRINST2_ROM_SIZE = 32'h01ca_0080;
localparam [31:0] PLEGENDS_ROM_SIZE = 32'h021c_0080;
localparam [3:0] PROBE_COUNT = 4'd10;
localparam [63:0] SIGNATURE_SEED = 64'h4341_5645_524f_4d31;

localparam [1:0] STATE_IDLE = 2'd0;
localparam [1:0] STATE_ISSUE = 2'd1;
localparam [1:0] STATE_WAIT = 2'd2;

reg [1:0] state_reg;
reg [3:0] probe_index;
reg [3:0] game_index_reg;
reg       data_seen;
reg       burst_seen;
reg       nonzero_seen;

function automatic [31:0] rom_size_for_game;
    input [3:0] game;
    begin
        case (game)
            GAME_DFEVERON: rom_size_for_game = DFEVERON_ROM_SIZE;
            GAME_DDONPACH: rom_size_for_game = DDONPACH_ROM_SIZE;
            GAME_DONPACHI: rom_size_for_game = DONPACHI_ROM_SIZE;
            GAME_ESPRADE:  rom_size_for_game = ESPRADE_ROM_SIZE;
            GAME_UOPOKO:   rom_size_for_game = UOPOKO_ROM_SIZE;
            GAME_GUWANGE:  rom_size_for_game = GUWANGE_ROM_SIZE;
            GAME_GAIA:     rom_size_for_game = GAIA_ROM_SIZE;
            GAME_PWRINST2: rom_size_for_game = PWRINST2_ROM_SIZE;
            GAME_PLEGENDS: rom_size_for_game = PLEGENDS_ROM_SIZE;
            default:       rom_size_for_game = 32'd0;
        endcase
    end
endfunction

function automatic [31:0] probe_offset;
    input [3:0] game;
    input [3:0] index;
    begin
        case (game)
            GAME_DFEVERON: begin
                case (index)
                    4'd0: probe_offset = 32'h0000_0000;
                    4'd1: probe_offset = 32'h0008_0000;
                    4'd2: probe_offset = 32'h0010_0000;
                    4'd3: probe_offset = 32'h0010_0080;
                    4'd4: probe_offset = 32'h0050_0080;
                    4'd5: probe_offset = 32'h0070_0080;
                    4'd6: probe_offset = 32'h0090_0080;
                    4'd7: probe_offset = 32'h00d0_0080;
                    4'd8: probe_offset = 32'h00f0_0080;
                    default: probe_offset = 32'h0110_0078;
                endcase
            end

            GAME_DDONPACH: begin
                case (index)
                    4'd0: probe_offset = 32'h0000_0000;
                    4'd1: probe_offset = 32'h0009_8000;
                    4'd2: probe_offset = 32'h0010_0000;
                    4'd3: probe_offset = 32'h0010_0080;
                    4'd4: probe_offset = 32'h0050_0080;
                    4'd5: probe_offset = 32'h0070_0080;
                    4'd6: probe_offset = 32'h0090_0080;
                    4'd7: probe_offset = 32'h00b0_0080;
                    4'd8: probe_offset = 32'h00f0_0080;
                    default: probe_offset = 32'h0130_0078;
                endcase
            end

            GAME_DONPACHI: begin
                case (index)
                    4'd0: probe_offset = 32'h0000_0000;
                    4'd1: probe_offset = 32'h0007_fff8;
                    4'd2: probe_offset = 32'h0008_0000;
                    4'd3: probe_offset = 32'h0008_0080;
                    4'd4: probe_offset = 32'h0028_0080;
                    4'd5: probe_offset = 32'h0038_0080;
                    4'd6: probe_offset = 32'h0048_0080;
                    4'd7: probe_offset = 32'h0058_0080;
                    4'd8: probe_offset = 32'h005c_0080;
                    default: probe_offset = 32'h009c_0078;
                endcase
            end

            GAME_ESPRADE: begin
                case (index)
                    4'd0: probe_offset = 32'h0000_0000;
                    4'd1: probe_offset = 32'h0008_0000;
                    4'd2: probe_offset = 32'h0010_0000;
                    4'd3: probe_offset = 32'h0010_0080;
                    4'd4: probe_offset = 32'h0050_0080;
                    4'd5: probe_offset = 32'h00d0_0080;
                    4'd6: probe_offset = 32'h0150_0080;
                    4'd7: probe_offset = 32'h0190_0080;
                    4'd8: probe_offset = 32'h0210_0080;
                    default: probe_offset = 32'h0290_0078;
                endcase
            end

            GAME_UOPOKO: begin
                case (index)
                    4'd0: probe_offset = 32'h0000_0000;
                    4'd1: probe_offset = 32'h0008_0000;
                    4'd2: probe_offset = 32'h0010_0000;
                    4'd3: probe_offset = 32'h0010_0080;
                    4'd4: probe_offset = 32'h0030_0080;
                    4'd5: probe_offset = 32'h0050_0080;
                    4'd6: probe_offset = 32'h0070_0080;
                    4'd7: probe_offset = 32'h0080_0080;
                    4'd8: probe_offset = 32'h00a0_0080;
                    default: probe_offset = 32'h00b0_0078;
                endcase
            end

            GAME_GUWANGE: begin
                case (index)
                    4'd0: probe_offset = 32'h0000_0000;
                    4'd1: probe_offset = 32'h0008_0000;
                    4'd2: probe_offset = 32'h0010_0080;
                    4'd3: probe_offset = 32'h0050_0080;
                    4'd4: probe_offset = 32'h00d0_0080;
                    4'd5: probe_offset = 32'h0110_0080;
                    4'd6: probe_offset = 32'h0150_0080;
                    4'd7: probe_offset = 32'h0250_0080;
                    4'd8: probe_offset = 32'h02d0_0080;
                    default: probe_offset = 32'h0350_0078;
                endcase
            end

            GAME_GAIA: begin
                case (index)
                    4'd0: probe_offset = 32'h0000_0000;
                    4'd1: probe_offset = 32'h0008_0000;
                    4'd2: probe_offset = 32'h0010_0000;
                    4'd3: probe_offset = 32'h0050_0000;
                    4'd4: probe_offset = 32'h0090_0000;
                    4'd5: probe_offset = 32'h00d0_0000;
                    4'd6: probe_offset = 32'h0110_0000;
                    4'd7: probe_offset = 32'h0150_0000;
                    4'd8: probe_offset = 32'h0190_0000;
                    default: probe_offset = 32'h020f_fff8;
                endcase
            end

            GAME_PWRINST2: begin
                case (index)
                    4'd0: probe_offset = 32'h0000_0000;
                    4'd1: probe_offset = 32'h0010_0000;
                    4'd2: probe_offset = 32'h0020_0000;
                    4'd3: probe_offset = 32'h0020_0080;
                    4'd4: probe_offset = 32'h0022_0080;
                    4'd5: probe_offset = 32'h0062_0080;
                    4'd6: probe_offset = 32'h00a2_0080;
                    4'd7: probe_offset = 32'h00d2_0080;
                    4'd8: probe_offset = 32'h00ea_0080;
                    default: probe_offset = 32'h01ca_0078;
                endcase
            end

            GAME_PLEGENDS: begin
                case (index)
                    4'd0: probe_offset = 32'h0000_0000;
                    4'd1: probe_offset = 32'h0010_0000;
                    4'd2: probe_offset = 32'h0020_0000;
                    4'd3: probe_offset = 32'h0030_0000;
                    4'd4: probe_offset = 32'h0030_0080;
                    4'd5: probe_offset = 32'h0034_0080;
                    4'd6: probe_offset = 32'h0074_0080;
                    4'd7: probe_offset = 32'h00b4_0080;
                    4'd8: probe_offset = 32'h011c_0080;
                    default: probe_offset = 32'h021c_0078;
                endcase
            end

            default: probe_offset = 32'd0;
        endcase
    end
endfunction

wire [31:0] selected_rom_size = rom_size_for_game(game_index);
wire [31:0] current_offset = probe_offset(game_index_reg, probe_index);
wire [63:0] address_mix = {current_offset, ~current_offset};
wire [63:0] signature_rotated = {signature[52:0], signature[63:53]};
wire [63:0] signature_next =
    signature_rotated ^ mem_dout ^ address_mix ^
    {56'h0, 4'hc, probe_index};
wire response_complete =
    state_reg == STATE_WAIT &&
    (data_seen || mem_valid) &&
    (burst_seen || mem_burst_done);
wire final_probe = probe_index == (PROBE_COUNT - 1'b1);

always @(posedge clk) begin
    if (reset) begin
        state_reg <= STATE_IDLE;
        probe_index <= 4'd0;
        game_index_reg <= 4'd0;
        data_seen <= 1'b0;
        burst_seen <= 1'b0;
        nonzero_seen <= 1'b0;
        busy <= 1'b0;
        done <= 1'b0;
        identity_valid <= 1'b0;
        rom_size <= 32'd0;
        signature <= 64'd0;
    end else begin
        done <= 1'b0;

        if (start && !busy) begin
            identity_valid <= 1'b0;
            signature <= SIGNATURE_SEED;
            probe_index <= 4'd0;
            game_index_reg <= game_index;
            data_seen <= 1'b0;
            burst_seen <= 1'b0;
            nonzero_seen <= 1'b0;

            if (selected_rom_size != 0) begin
                busy <= 1'b1;
                rom_size <= selected_rom_size;
                state_reg <= STATE_ISSUE;
            end else begin
                busy <= 1'b0;
                done <= 1'b1;
                rom_size <= 32'd0;
                signature <= 64'd0;
                state_reg <= STATE_IDLE;
            end
        end else begin
            case (state_reg)
                STATE_ISSUE: begin
                    if (mem_wait_n) begin
                        data_seen <= 1'b0;
                        burst_seen <= 1'b0;
                        state_reg <= STATE_WAIT;
                    end
                end

                STATE_WAIT: begin
                    if (mem_valid) begin
                        signature <= signature_next;
                        nonzero_seen <= nonzero_seen || (|mem_dout);
                        data_seen <= 1'b1;
                    end
                    if (mem_burst_done)
                        burst_seen <= 1'b1;

                    if (response_complete) begin
                        data_seen <= 1'b0;
                        burst_seen <= 1'b0;
                        if (final_probe) begin
                            busy <= 1'b0;
                            done <= 1'b1;
                            identity_valid <=
                                nonzero_seen || (mem_valid && (|mem_dout));
                            state_reg <= STATE_IDLE;
                        end else begin
                            probe_index <= probe_index + 1'b1;
                            state_reg <= STATE_ISSUE;
                        end
                    end
                end

                default: state_reg <= STATE_IDLE;
            endcase
        end
    end
end

assign mem_rd = state_reg == STATE_ISSUE;
assign mem_addr = ROM_DDR_BASE + current_offset;

endmodule
