`timescale 1ns/1ps

module CaveHighScoreManager_tb;
  reg sys_clock = 1'b0;
  reg cpu_clock = 1'b0;
  always #5 sys_clock = ~sys_clock;
  always #6 cpu_clock = ~cpu_clock;

  reg sys_reset = 1'b1;
  reg cpu_reset = 1'b1;
  reg config_download = 1'b0;
  reg config_wr = 1'b0;
  reg [26:0] config_addr = 27'd0;
  reg [15:0] config_dout = 16'd0;
  reg nvram_download = 1'b0;
  reg nvram_upload = 1'b0;
  reg nvram_rd = 1'b0;
  reg nvram_wr = 1'b0;
  reg [26:0] nvram_addr = 27'd0;
  reg [15:0] nvram_dout = 16'd0;
  wire [15:0] nvram_din;
  wire nvram_wait_n;
  reg ss_hold_cpu = 1'b0;
  reg normal_ram_wr = 1'b0;
  reg [23:0] normal_byte_addr = 24'd0;
  reg [1:0] normal_ram_mask = 2'b00;
  reg [15:0] normal_ram_din = 16'd0;
  wire cpu_hold;
  reg cpu_idle = 1'b0;
  wire ram_owned;
  wire ram_rd;
  wire ram_wr;
  wire [14:0] ram_addr;
  wire [1:0] ram_mask;
  wire [15:0] ram_din;
  reg [15:0] ram_dout = 16'd0;
  wire dirty_sys;
  wire active_sys;

  reg [15:0] work_ram [0:32767];
  integer i;
  integer checks = 0;
  integer errors = 0;

  CaveHighScoreManager dut (
    .sys_clock(sys_clock),
    .sys_reset(sys_reset),
    .cpu_clock(cpu_clock),
    .cpu_reset(cpu_reset),
    .config_download(config_download),
    .config_wr(config_wr),
    .config_addr(config_addr),
    .config_dout(config_dout),
    .nvram_download(nvram_download),
    .nvram_upload(nvram_upload),
    .nvram_rd(nvram_rd),
    .nvram_wr(nvram_wr),
    .nvram_addr(nvram_addr),
    .nvram_dout(nvram_dout),
    .nvram_din(nvram_din),
    .nvram_wait_n(nvram_wait_n),
    .ss_hold_cpu(ss_hold_cpu),
    .cpu_idle(cpu_idle),
    .normal_ram_wr(normal_ram_wr),
    .normal_byte_addr(normal_byte_addr),
    .normal_ram_mask(normal_ram_mask),
    .normal_ram_din(normal_ram_din),
    .cpu_hold(cpu_hold),
    .ram_owned(ram_owned),
    .ram_rd(ram_rd),
    .ram_wr(ram_wr),
    .ram_addr(ram_addr),
    .ram_mask(ram_mask),
    .ram_din(ram_din),
    .ram_dout(ram_dout),
    .dirty_sys(dirty_sys),
    .active_sys(active_sys)
  );

  always @(posedge cpu_clock) begin
    if (cpu_reset)
      cpu_idle <= 1'b0;
    else
      cpu_idle <= cpu_hold;

    if (normal_ram_wr) begin
      if (normal_ram_mask[1])
        work_ram[normal_byte_addr[15:1]][15:8] <= normal_ram_din[15:8];
      if (normal_ram_mask[0])
        work_ram[normal_byte_addr[15:1]][7:0] <= normal_ram_din[7:0];
    end

    if (ram_rd)
      ram_dout <= work_ram[ram_addr];

    if (ram_wr) begin
      if (ram_mask[1])
        work_ram[ram_addr][15:8] <= ram_din[15:8];
      if (ram_mask[0])
        work_ram[ram_addr][7:0] <= ram_din[7:0];
    end
  end

  function [7:0] read_work_byte;
    input [15:0] byte_addr;
    begin
      read_work_byte = byte_addr[0]
        ? work_ram[byte_addr[15:1]][7:0]
        : work_ram[byte_addr[15:1]][15:8];
    end
  endfunction

  task check;
    input condition;
    input [8*80-1:0] message;
    begin
      checks = checks + 1;
      if (!condition) begin
        errors = errors + 1;
        $display("FAIL: %0s", message);
      end
    end
  endtask

  task config_word_write;
    input [3:0] byte_addr;
    input [15:0] value;
    begin
      @(negedge sys_clock);
      config_addr = {23'd0, byte_addr};
      config_dout = {value[7:0], value[15:8]};
      config_wr = 1'b1;
      @(negedge sys_clock);
      config_wr = 1'b0;
    end
  endtask

  task load_two_range_config;
    begin
      @(negedge sys_clock);
      config_download = 1'b1;
      config_word_write(4'd0, 16'h0010);
      config_word_write(4'd2, 16'h0020);
      config_word_write(4'd4, 16'h0003);
      config_word_write(4'd6, 16'hA1A3);
      config_word_write(4'd8, 16'h0010);
      config_word_write(4'd10, 16'h0031);
      config_word_write(4'd12, 16'h0004);
      config_word_write(4'd14, 16'hB1B4);
      @(negedge sys_clock);
      config_download = 1'b0;
      repeat (8) @(posedge cpu_clock);
    end
  endtask

  task load_one_range_config;
    begin
      @(negedge sys_clock);
      config_download = 1'b1;
      config_word_write(4'd0, 16'h0010);
      config_word_write(4'd2, 16'h0040);
      config_word_write(4'd4, 16'h0005);
      config_word_write(4'd6, 16'hC1C5);
      @(negedge sys_clock);
      config_download = 1'b0;
      repeat (8) @(posedge cpu_clock);
    end
  endtask

  task load_invalid_config;
    begin
      @(negedge sys_clock);
      config_download = 1'b1;
      config_word_write(4'd0, 16'h0010);
      config_word_write(4'd2, 16'hFFFF);
      config_word_write(4'd4, 16'h0004);
      config_word_write(4'd6, 16'h0000);
      @(negedge sys_clock);
      config_download = 1'b0;
      repeat (8) @(posedge cpu_clock);
    end
  endtask

  task nvram_file_word_write;
    input [9:0] byte_address;
    input [15:0] file_word;
    begin
      @(negedge sys_clock);
      nvram_addr = byte_address;
      nvram_dout = {file_word[7:0], file_word[15:8]};
      nvram_wr = 1'b1;
      @(negedge sys_clock);
      nvram_wr = 1'b0;
    end
  endtask

  task load_versioned_score_data;
    input [15:0] schema_word;
    input [15:0] range0_start_low;
    input        include_final_word;
    begin
      @(negedge sys_clock);
      nvram_download = 1'b1;
      nvram_file_word_write(10'd128, 16'h4356);
      nvram_file_word_write(10'd130, 16'h4853);
      nvram_file_word_write(10'd132, schema_word);
      nvram_file_word_write(10'd134, 16'h0200);
      nvram_file_word_write(10'd136, 16'h0007);
      nvram_file_word_write(10'd138, 16'h0000);
      nvram_file_word_write(10'd140, 16'h0010);
      nvram_file_word_write(10'd142, range0_start_low);
      nvram_file_word_write(10'd144, 16'h0003);
      nvram_file_word_write(10'd146, 16'hA1A3);
      nvram_file_word_write(10'd148, 16'h0010);
      nvram_file_word_write(10'd150, 16'h0031);
      nvram_file_word_write(10'd152, 16'h0004);
      nvram_file_word_write(10'd154, 16'hB1B4);
      nvram_file_word_write(10'd156, 16'h454E);
      nvram_file_word_write(10'd158, 16'h4421);
      nvram_file_word_write(10'd160, 16'hD0D1);
      nvram_file_word_write(10'd162, 16'hD2E0);
      nvram_file_word_write(10'd164, 16'hE1E2);
      if (include_final_word)
        nvram_file_word_write(10'd166, 16'hE300);
      @(negedge sys_clock);
      nvram_download = 1'b0;
      repeat (8) @(posedge cpu_clock);
    end
  endtask

  task load_unversioned_score_data;
    begin
      @(negedge sys_clock);
      nvram_download = 1'b1;
      nvram_file_word_write(10'd128, 16'hD0D1);
      nvram_file_word_write(10'd130, 16'hD2E0);
      nvram_file_word_write(10'd132, 16'hE1E2);
      nvram_file_word_write(10'd134, 16'hE300);
      @(negedge sys_clock);
      nvram_download = 1'b0;
      repeat (8) @(posedge cpu_clock);
    end
  endtask

  task load_one_range_score_data;
    begin
      @(negedge sys_clock);
      nvram_download = 1'b1;
      nvram_file_word_write(10'd128, 16'h4356);
      nvram_file_word_write(10'd130, 16'h4853);
      nvram_file_word_write(10'd132, 16'h0120);
      nvram_file_word_write(10'd134, 16'h0100);
      nvram_file_word_write(10'd136, 16'h0005);
      nvram_file_word_write(10'd138, 16'h0000);
      nvram_file_word_write(10'd140, 16'h0010);
      nvram_file_word_write(10'd142, 16'h0040);
      nvram_file_word_write(10'd144, 16'h0005);
      nvram_file_word_write(10'd146, 16'hC1C5);
      nvram_file_word_write(10'd148, 16'h0000);
      nvram_file_word_write(10'd150, 16'h0000);
      nvram_file_word_write(10'd152, 16'h0000);
      nvram_file_word_write(10'd154, 16'h0000);
      nvram_file_word_write(10'd156, 16'h454E);
      nvram_file_word_write(10'd158, 16'h4421);
      nvram_file_word_write(10'd160, 16'hF0F1);
      nvram_file_word_write(10'd162, 16'hF2F3);
      nvram_file_word_write(10'd164, 16'hF400);
      @(negedge sys_clock);
      nvram_download = 1'b0;
      repeat (8) @(posedge cpu_clock);
    end
  endtask

  task load_old_nvram_only;
    begin
      @(negedge sys_clock);
      nvram_download = 1'b1;
      repeat (4) @(posedge sys_clock);
      @(negedge sys_clock);
      nvram_download = 1'b0;
      repeat (8) @(posedge cpu_clock);
    end
  endtask

  task write_work_byte;
    input [23:0] byte_addr;
    input [7:0] value;
    begin
      @(negedge cpu_clock);
      normal_byte_addr = {byte_addr[23:1], 1'b0};
      if (byte_addr[0]) begin
        normal_ram_mask = 2'b01;
        normal_ram_din = {8'd0, value};
      end else begin
        normal_ram_mask = 2'b10;
        normal_ram_din = {value, 8'd0};
      end
      normal_ram_wr = 1'b1;
      @(negedge cpu_clock);
      normal_ram_wr = 1'b0;
      normal_ram_mask = 2'b00;
    end
  endtask

  task write_signatures;
    input correct_last;
    begin
      write_work_byte(24'h100020, 8'hA1);
      write_work_byte(24'h100022, correct_last ? 8'hA3 : 8'h00);
      write_work_byte(24'h100031, 8'hB1);
      write_work_byte(24'h100034, correct_last ? 8'hB4 : 8'h00);
      repeat (8) @(posedge cpu_clock);
    end
  endtask

  task write_one_range_signatures;
    begin
      write_work_byte(24'h100040, 8'hC1);
      write_work_byte(24'h100044, 8'hC5);
      repeat (8) @(posedge cpu_clock);
    end
  endtask

  task wait_for_operation;
    integer timeout;
    begin
      timeout = 0;
      while (!active_sys && timeout < 200) begin
        @(posedge sys_clock);
        timeout = timeout + 1;
      end
      check(active_sys, "operation became active");
      timeout = 0;
      while (active_sys && timeout < 2000) begin
        @(posedge sys_clock);
        timeout = timeout + 1;
      end
      check(!active_sys, "operation completed");
    end
  endtask

  task upload_word_check;
    input [9:0] byte_address;
    input [15:0] expected_file_word;
    reg [15:0] actual_file_word;
    begin
      @(negedge sys_clock);
      nvram_addr = byte_address;
      nvram_rd = 1'b1;
      @(posedge sys_clock);
      #1;
      actual_file_word = {nvram_din[7:0], nvram_din[15:8]};
      check(actual_file_word == expected_file_word,
            "uploaded word matches work RAM");
      @(negedge sys_clock);
      nvram_rd = 1'b0;
    end
  endtask

  initial begin
    for (i = 0; i < 32768; i = i + 1)
      work_ram[i] = 16'd0;

    repeat (5) @(posedge sys_clock);
    sys_reset = 1'b0;
    repeat (5) @(posedge cpu_clock);
    cpu_reset = 1'b0;

    // A missing .nvm means Main never performs an index-2 download. The first
    // upload must still capture valid RAM without restoring or mutating it.
    load_two_range_config();
    write_signatures(1'b1);
    @(negedge sys_clock);
    nvram_upload = 1'b1;
    @(posedge sys_clock);
    #1;
    check(!nvram_wait_n, "first upload without a download stalls for capture");
    i = 0;
    while (!nvram_wait_n && i < 2000) begin
      @(posedge sys_clock);
      i = i + 1;
    end
    check(nvram_wait_n, "first upload without a download completes capture");
    upload_word_check(10'd128, 16'h4356);
    upload_word_check(10'd130, 16'h4853);
    upload_word_check(10'd132, 16'h0120);
    upload_word_check(10'd160, 16'hA100);
    upload_word_check(10'd162, 16'hA3B1);
    upload_word_check(10'd164, 16'h0000);
    upload_word_check(10'd166, 16'hB400);
    check(read_work_byte(16'h0020) == 8'hA1,
          "first upload leaves range 0 untouched");
    check(read_work_byte(16'h0034) == 8'hB4,
          "first upload leaves range 1 untouched");
    @(negedge sys_clock);
    nvram_upload = 1'b0;
    repeat (4) @(posedge sys_clock);
    check(!cpu_hold, "first upload releases the CPU hold");

    // Return to the original power-on ordering for the remaining tests.
    sys_reset = 1'b1;
    cpu_reset = 1'b1;
    repeat (5) @(posedge sys_clock);
    sys_reset = 1'b0;
    repeat (5) @(posedge cpu_clock);
    cpu_reset = 1'b0;

    // Main sends MRA NVRAM before the later ROM index-4 descriptor. Buffer
    // the complete header and validate it only after both inputs exist.
    load_one_range_score_data();
    load_one_range_config();
    write_one_range_signatures();
    wait_for_operation();
    check(read_work_byte(16'h0040) == 8'hF0, "one range byte 0 restored");
    check(read_work_byte(16'h0041) == 8'hF1, "one range byte 1 restored");
    check(read_work_byte(16'h0042) == 8'hF2, "one range byte 2 restored");
    check(read_work_byte(16'h0043) == 8'hF3, "one range byte 3 restored");
    check(read_work_byte(16'h0044) == 8'hF4, "one range final byte restored");

    // A legacy 128-byte EEPROM file has no high-score payload and must never
    // overwrite initialized game RAM.
    load_two_range_config();
    load_old_nvram_only();
    write_signatures(1'b1);
    repeat (80) @(posedge cpu_clock);
    check(!cpu_hold, "old EEPROM-only NVRAM does not trigger restore");
    check(read_work_byte(16'h0020) == 8'hA1,
          "legacy file leaves first range untouched");

    // The old unversioned extension is deliberately invalidated while its
    // EEPROM prefix remains usable.
    load_two_range_config();
    load_unversioned_score_data();
    write_signatures(1'b1);
    repeat (80) @(posedge cpu_clock);
    check(!cpu_hold, "unversioned score extension does not trigger restore");
    check(read_work_byte(16'h0020) == 8'hA1,
          "unversioned extension leaves work RAM untouched");

    // A complete header with the wrong schema is rejected before any write.
    load_two_range_config();
    load_versioned_score_data(16'h0220, 16'h0020, 1'b1);
    write_signatures(1'b1);
    repeat (80) @(posedge cpu_clock);
    check(!cpu_hold, "wrong NVRAM schema does not trigger restore");
    check(read_work_byte(16'h0020) == 8'hA1,
          "wrong NVRAM schema leaves work RAM untouched");

    // The complete range descriptors are part of the identity check.
    load_two_range_config();
    load_versioned_score_data(16'h0120, 16'h0021, 1'b1);
    write_signatures(1'b1);
    repeat (80) @(posedge cpu_clock);
    check(!cpu_hold, "wrong range identity does not trigger restore");
    check(read_work_byte(16'h0020) == 8'hA1,
          "wrong range identity leaves work RAM untouched");

    // A valid header with a truncated payload cannot cause a partial restore.
    load_two_range_config();
    load_versioned_score_data(16'h0120, 16'h0020, 1'b0);
    write_signatures(1'b1);
    repeat (80) @(posedge cpu_clock);
    check(!cpu_hold, "truncated payload does not trigger restore");
    check(read_work_byte(16'h0020) == 8'hA1,
          "truncated payload leaves work RAM untouched");

    // Valid versioned score data must still wait for every MAME
    // initialization signature.
    load_two_range_config();
    load_versioned_score_data(16'h0120, 16'h0020, 1'b1);
    write_signatures(1'b0);
    repeat (80) @(posedge cpu_clock);
    check(!cpu_hold, "wrong signatures block restore");
    check(read_work_byte(16'h0020) == 8'hA1,
          "wrong signatures leave work RAM untouched");

    // A concurrent save-state hold has priority over high-score injection.
    ss_hold_cpu = 1'b1;
    write_signatures(1'b1);
    repeat (40) @(posedge cpu_clock);
    check(!cpu_hold, "save-state hold blocks high-score operation start");
    ss_hold_cpu = 1'b0;
    wait_for_operation();

    check(read_work_byte(16'h0020) == 8'hD0, "range 0 byte 0 restored");
    check(read_work_byte(16'h0021) == 8'hD1, "range 0 odd byte restored");
    check(read_work_byte(16'h0022) == 8'hD2, "range 0 final byte restored");
    check(read_work_byte(16'h0031) == 8'hE0, "range 1 odd start restored");
    check(read_work_byte(16'h0032) == 8'hE1, "range 1 byte 1 restored");
    check(read_work_byte(16'h0033) == 8'hE2, "range 1 odd byte restored");
    check(read_work_byte(16'h0034) == 8'hE3, "range 1 final byte restored");

    // Mutate both lane shapes, then prove capture stalls upload and serializes
    // the current work RAM exactly.
    write_work_byte(24'h100021, 8'h5A);
    write_work_byte(24'h100033, 8'h6B);
    repeat (8) @(posedge sys_clock);
    check(dirty_sys, "score mutation marks NVRAM dirty");

    @(negedge sys_clock);
    nvram_upload = 1'b1;
    @(posedge sys_clock);
    #1;
    check(!nvram_wait_n, "upload stalls until CPU snapshot completes");
    i = 0;
    while (!nvram_wait_n && i < 2000) begin
      @(posedge sys_clock);
      i = i + 1;
    end
    check(nvram_wait_n, "upload releases after CPU snapshot");
    upload_word_check(10'd128, 16'h4356);
    upload_word_check(10'd130, 16'h4853);
    upload_word_check(10'd132, 16'h0120);
    upload_word_check(10'd134, 16'h0200);
    upload_word_check(10'd136, 16'h0007);
    upload_word_check(10'd142, 16'h0020);
    upload_word_check(10'd154, 16'hB1B4);
    upload_word_check(10'd156, 16'h454E);
    upload_word_check(10'd158, 16'h4421);
    upload_word_check(10'd160, 16'hD05A);
    upload_word_check(10'd162, 16'hD2E0);
    upload_word_check(10'd164, 16'hE16B);
    upload_word_check(10'd166, 16'hE300);
    check(!dirty_sys, "successful snapshot clears dirty state");
    @(negedge sys_clock);
    nvram_upload = 1'b0;
    repeat (4) @(posedge sys_clock);

    // A malformed range crossing the 64 KiB physical work-RAM boundary is
    // rejected and therefore cannot stall or write during an upload.
    load_invalid_config();
    @(negedge sys_clock);
    nvram_upload = 1'b1;
    @(posedge sys_clock);
    #1;
    check(nvram_wait_n, "invalid config is rejected without an upload stall");
    check(!cpu_hold, "invalid config cannot take ownership of work RAM");
    @(negedge sys_clock);
    nvram_upload = 1'b0;

    if (errors == 0)
      $display("PASS: CaveHighScoreManager %0d checks", checks);
    else
      $display("FAIL: CaveHighScoreManager %0d errors in %0d checks",
               errors, checks);
    $finish;
  end
endmodule
