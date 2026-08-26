module CaveSaveStateMetadata #(
    parameter [7:0]  SS_IDX = 8'd0,
    parameter [63:0] MAGIC = 64'h4341_5645_5353_3031, // "CAVESS01"
    parameter [31:0] SCHEMA_VERSION = 32'h0002_0000,
    parameter [31:0] CORE_ID = 32'h4341_5645             // "CAVE"
) (
    input wire        clk,
    input wire        reset,
    input wire        restore_start,

    input wire [7:0]  current_game_id,
    input wire [31:0] current_set_id,
    input wire [31:0] current_rom_size,
    input wire [63:0] current_rom_signature,
    input wire [63:0] current_support_bitmap,

    output wire       restore_complete,
    output wire       restore_valid,
    output wire [7:0] restored_game_id,
    output wire [63:0] restored_rom_signature,

    cave_ssbus_if.slave ssbus
);

localparam [31:0] WORD_COUNT = 32'd6;

reg [63:0] staged_magic = 64'd0;
reg [63:0] staged_version_core = 64'd0;
reg [63:0] staged_set_size = 64'd0;
reg [63:0] staged_game = 64'd0;
reg [63:0] staged_signature = 64'd0;
reg [63:0] staged_support = 64'd0;
reg        staged_complete = 1'b0;

wire [63:0] expected_version_core = {SCHEMA_VERSION, CORE_ID};
wire [63:0] expected_set_size = {current_set_id, current_rom_size};
wire [63:0] expected_game = {56'd0, current_game_id};

assign restore_complete = staged_complete;
assign restored_game_id = staged_game[7:0];
assign restored_rom_signature = staged_signature;
assign restore_valid = staged_complete &&
                       (staged_magic == MAGIC) &&
                       (staged_version_core == expected_version_core) &&
                       (staged_set_size == expected_set_size) &&
                       (staged_game == expected_game) &&
                       (staged_signature == current_rom_signature) &&
                       (staged_support == current_support_bitmap);

always_ff @(posedge clk) begin
    ssbus.setup(SS_IDX, WORD_COUNT, 2'd3);

    if (reset || restore_start) begin
        staged_magic <= 64'd0;
        staged_version_core <= 64'd0;
        staged_set_size <= 64'd0;
        staged_game <= 64'd0;
        staged_signature <= 64'd0;
        staged_support <= 64'd0;
        staged_complete <= 1'b0;
    end else if (ssbus.access(SS_IDX)) begin
        if (ssbus.read) begin
            case (ssbus.addr)
                32'd0: ssbus.read_response(SS_IDX, MAGIC);
                32'd1: ssbus.read_response(SS_IDX, expected_version_core);
                32'd2: ssbus.read_response(SS_IDX, expected_set_size);
                32'd3: ssbus.read_response(SS_IDX, expected_game);
                32'd4: ssbus.read_response(SS_IDX, current_rom_signature);
                32'd5: ssbus.read_response(SS_IDX, current_support_bitmap);
                default: ssbus.read_response(SS_IDX, 64'd0);
            endcase
        end else if (ssbus.write) begin
            case (ssbus.addr)
                32'd0: staged_magic <= ssbus.data;
                32'd1: staged_version_core <= ssbus.data;
                32'd2: staged_set_size <= ssbus.data;
                32'd3: staged_game <= ssbus.data;
                32'd4: staged_signature <= ssbus.data;
                32'd5: begin
                    staged_support <= ssbus.data;
                    staged_complete <= 1'b1;
                end
                default: begin end
            endcase
            ssbus.write_ack(SS_IDX);
        end
    end
end

endmodule
