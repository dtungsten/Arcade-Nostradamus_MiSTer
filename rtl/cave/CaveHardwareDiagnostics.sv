// Compact Cave-local startup snapshot for macro-gated ISSP diagnostics.
module CaveHardwareDiagnostics(
  input          system_clock,
  input          cpu_clock,
  input          video_clock,
  input          clear,
  input          system_reset,
  input          cpu_reset,
  input          video_reset,
  input  [3:0]   game_index_system,
  input  [3:0]   game_index_cpu,
  input          game_index_latched,
  input          ioctl_download,
  input          rom_identity_read,
  input          mem_prog_done,
  input  [7:0]   mem_startup_debug,
  input          mem_ready,
  input          rom_identity_valid,
  input  [31:0]  rom_size,
  input          mem_prog_rom_rd,
  input          mem_prog_rom_wait_n,
  input          mem_prog_rom_valid,
  input          mem_cache_rom_rd,
  input          mem_cache_rom_wait_n,
  input          mem_cache_rom_valid,
  input          sdram_rd,
  input          sdram_wait_n,
  input          sdram_valid,
  input  [15:0]  sdram_dout,
  input          sdram_wr_event,
  input          ddr_rd_event,
  input          ddr_wr_event,
  input          framebuffer_wr_event,
  input          cpu_prog_rom_rd,
  input          cpu_prog_rom_valid,
  input          cpu_frame_swap,
  input          video_vblank,
  input          frame_force_blank,
  input          ss_available,
  input          ss_active,
  input          ss_busy,
  input          ss_save_request,
  input          ss_load_request,
  input          ss_block_clients,
  input          ss_cpu_idle,
  input          ss_cpu_clients_idle,
  input          ss_main_clients_idle_cpu,
  input          ss_sound_idle_cpu,
  input          ss_video_clients_idle,
  input          ss_video_clients_idle_raw,
  input          ss_gpu_idle,
  input          ss_sprite_framebuffer_idle,
  input          ss_system_framebuffer_idle,
  input          ss_tile_0_idle,
  input          ss_tile_1_idle,
  input          ss_tile_2_idle,
  input          ss_pwrinst_tile_idle,
  input          ss_ddr_idle,
  input          ss_gameplay_sources_idle,
  input  [3:0]   ss_state,
  input  [3:0]   ss_last_error,
  output [127:0] probe
);
  localparam [15:0] PROBE_SIGNATURE = 16'hC450;
  localparam [3:0]  PROBE_VERSION = 4'd6;

  reg [7:0]  loader_seen = 8'd0;
  reg [11:0] memory_seen = 12'd0;
  reg [2:0]  cpu_seen = 3'd0;
  reg        video_seen = 1'b0;
  reg [3:0]  ss_seen = 4'd0;
  reg [1:0]  main_clients_idle_sync = 2'd0;
  reg [1:0]  sound_idle_sync = 2'd0;
  reg [15:0] drain_idle_snapshot = 16'd0;

  wire [15:0] drain_idle_flags = {
    ss_block_clients,
    ss_cpu_idle,
    ss_cpu_clients_idle,
    main_clients_idle_sync[1],
    sound_idle_sync[1],
    ss_video_clients_idle,
    ss_video_clients_idle_raw,
    ss_gpu_idle,
    ss_sprite_framebuffer_idle,
    ss_system_framebuffer_idle,
    ss_tile_0_idle,
    ss_tile_1_idle,
    ss_tile_2_idle,
    ss_pwrinst_tile_idle,
    ss_ddr_idle,
    ss_gameplay_sources_idle
  };

  always @(posedge system_clock) begin
    if (system_reset) begin
      main_clients_idle_sync <= 2'd0;
      sound_idle_sync <= 2'd0;
    end
    else begin
      main_clients_idle_sync <= {
        main_clients_idle_sync[0], ss_main_clients_idle_cpu
      };
      sound_idle_sync <= {sound_idle_sync[0], ss_sound_idle_cpu};
    end

    if (clear) begin
      loader_seen <= 8'd0;
      memory_seen <= 12'd0;
      ss_seen <= 4'd0;
      drain_idle_snapshot <= 16'd0;
    end
    else begin
      loader_seen <= loader_seen | {
        ioctl_download,
        rom_identity_read,
        mem_prog_done | mem_startup_debug[0],
        mem_startup_debug[1],
        mem_startup_debug[2] | mem_startup_debug[4],
        mem_startup_debug[3] | mem_startup_debug[6],
        mem_ready | mem_startup_debug[7],
        rom_identity_valid
      };
      memory_seen <= memory_seen | {
        mem_prog_rom_rd,
        mem_cache_rom_rd,
        mem_cache_rom_rd & mem_cache_rom_wait_n,
        sdram_rd,
        sdram_rd & sdram_wait_n,
        sdram_valid,
        mem_cache_rom_valid,
        mem_prog_rom_valid,
        framebuffer_wr_event,
        ddr_wr_event,
        ddr_rd_event,
        sdram_wr_event
      };
      ss_seen <= ss_seen | {
        ss_save_request,
        ss_load_request,
        ss_active,
        ss_busy
      };
      if (ss_state == 4'd3)
        drain_idle_snapshot <= drain_idle_flags;
    end
  end

  always @(posedge cpu_clock) begin
    if (clear)
      cpu_seen <= 3'd0;
    else
      cpu_seen <= cpu_seen | {
        cpu_prog_rom_rd,
        cpu_prog_rom_valid,
        cpu_frame_swap
      };
  end

  always @(posedge video_clock) begin
    if (clear)
      video_seen <= 1'b0;
    else
      video_seen <= video_seen | video_vblank;
  end

  wire [23:0] seen_flags = {
    loader_seen,
    cpu_seen[2],
    memory_seen[11:4],
    cpu_seen[1:0],
    memory_seen[3],
    video_seen,
    memory_seen[2:0]
  };
  wire [15:0] current_flags = {
    system_reset,
    cpu_reset,
    video_reset,
    ioctl_download,
    game_index_latched,
    mem_ready,
    rom_identity_valid,
    frame_force_blank,
    ss_available,
    ss_active,
    cpu_prog_rom_rd,
    mem_prog_rom_rd,
    mem_cache_rom_rd,
    sdram_rd,
    sdram_wait_n,
    sdram_valid
  };

  assign probe = {
    PROBE_SIGNATURE,
    PROBE_VERSION,
    game_index_system,
    game_index_cpu,
    drain_idle_snapshot,
    seen_flags,
    current_flags,
    rom_size,
    ss_seen,
    ss_last_error,
    ss_state
  };
endmodule
