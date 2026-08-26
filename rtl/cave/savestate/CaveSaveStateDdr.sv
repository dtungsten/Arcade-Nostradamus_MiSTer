// Cave-local view of the MiSTer 64-bit DDR port. Addresses are byte addresses.
interface cave_ss_ddr_if();
    logic        acquire;
    logic [31:0] addr;
    logic [63:0] wdata;
    logic [63:0] rdata;
    logic        read;
    logic        write;
    logic [7:0]  burstcnt;
    logic [7:0]  byteenable;
    logic        busy;
    logic        rdata_ready;

    modport to_host(
        output acquire, addr, wdata, read, write, burstcnt, byteenable,
        input rdata, busy, rdata_ready
    );

    modport from_host(
        output rdata, busy, rdata_ready,
        input acquire, addr, wdata, read, write, burstcnt, byteenable
    );
endinterface

module CaveSaveStateDdrArbiter (
    input wire clk,
    input wire reset,
    input wire game_idle,

    input wire game_rd,
    input wire game_wr,
    input wire [31:0] game_addr,
    input wire [7:0] game_mask,
    input wire [63:0] game_din,
    input wire [7:0] game_burst_length,
    output wire [63:0] game_dout,
    output wire game_wait_n,
    output wire game_valid,

    cave_ss_ddr_if.from_host save,

    output wire ddr_rd,
    output wire ddr_wr,
    output wire [31:0] ddr_addr,
    output wire [7:0] ddr_mask,
    output wire [63:0] ddr_din,
    output wire [7:0] ddr_burst_length,
    input wire [63:0] ddr_dout,
    input wire ddr_wait_n,
    input wire ddr_valid,

    output wire save_granted
);

reg        grant_save = 1'b0;
reg        command_valid = 1'b0;
reg        command_save = 1'b0;
reg        command_read = 1'b0;
reg        command_write = 1'b0;
reg [31:0] command_addr = 32'd0;
reg [7:0]  command_mask = 8'd0;
reg [63:0] command_din = 64'd0;
reg [7:0]  command_burst_length = 8'd0;
reg        save_read_pending = 1'b0;

wire selected_read = grant_save ? save.read : game_rd;
wire selected_write = grant_save ? save.write : game_wr;
wire [31:0] selected_addr = grant_save ? save.addr : game_addr;
wire [7:0] selected_mask = grant_save ? save.byteenable : game_mask;
wire [63:0] selected_din = grant_save ? save.wdata : game_din;
wire [7:0] selected_burst_length =
    grant_save ? save.burstcnt : game_burst_length;
wire selected_valid = selected_read || selected_write;

// A full command may be replaced on the same edge that DDR accepts it. This
// keeps sustained write bursts at one beat per clock while registering every
// signal that reaches the HPS DDR boundary.
wire command_ready = !command_valid || ddr_wait_n;
wire command_accept = command_valid && ddr_wait_n;
wire save_read_accept =
    command_accept && command_save && command_read;

always @(posedge clk) begin
    if (reset) begin
        grant_save <= 1'b0;
        command_valid <= 1'b0;
        command_save <= 1'b0;
        command_read <= 1'b0;
        command_write <= 1'b0;
        command_addr <= 32'd0;
        command_mask <= 8'd0;
        command_din <= 64'd0;
        command_burst_length <= 8'd0;
        save_read_pending <= 1'b0;
    end else begin
        if (command_ready) begin
            command_valid <= selected_valid;
            if (selected_valid) begin
                command_save <= grant_save;
                command_read <= selected_read;
                command_write <= selected_write;
                command_addr <= selected_addr;
                command_mask <= selected_mask;
                command_din <= selected_din;
                command_burst_length <= selected_burst_length;
            end
        end

        if (save_read_pending && ddr_valid)
            save_read_pending <= 1'b0;
        if (save_read_accept)
            save_read_pending <= 1'b1;

        if (grant_save && !save.acquire && !command_valid &&
            !save_read_pending)
            grant_save <= 1'b0;
        else if (!grant_save && save.acquire && game_idle &&
                 !command_valid)
            grant_save <= 1'b1;
    end
end

assign save_granted = grant_save;

assign ddr_rd = command_valid && command_read;
assign ddr_wr = command_valid && command_write;
assign ddr_addr = command_addr;
assign ddr_mask = command_mask;
assign ddr_din = command_din;
assign ddr_burst_length = command_burst_length;

assign game_dout = ddr_dout;
assign game_wait_n = !grant_save && command_ready;
assign game_valid = grant_save ? 1'b0 : ddr_valid;

assign save.rdata = ddr_dout;
assign save.busy = !grant_save || !command_ready;
assign save.rdata_ready = grant_save && ddr_valid;

endmodule
