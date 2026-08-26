`timescale 1ns/1ps

module CaveNvramUploadIntegration_tb;
  reg         clock = 1'b0;
  reg         reset = 1'b1;
  reg         upload = 1'b0;
  reg  [26:0] upload_addr = 27'd0;

  wire [15:0] upload_dout;
  wire        upload_wait_n;
  wire        prefetch_mem_rd;
  wire [6:0]  prefetch_mem_addr;
  wire [15:0] prefetch_mem_dout;
  wire        prefetch_mem_wait_n;
  wire        prefetch_mem_valid;

  wire        cache_rd;
  wire        cache_wr;
  wire [6:0]  cache_addr;
  wire [15:0] cache_din;
  wire [15:0] cache_dout;
  wire        cache_wait_n;
  wire        cache_valid;

  wire        backing_rd;
  wire        backing_wr;
  wire [24:0] backing_addr;
  wire [15:0] backing_din;
  reg  [15:0] backing_dout = 16'd0;
  wire        backing_wait_n;
  reg         backing_valid = 1'b0;

  reg  [15:0] backing_memory [0:63];
  reg         burst_active = 1'b0;
  reg  [2:0]  burst_delay = 3'd0;
  reg  [1:0]  burst_word = 2'd0;
  reg  [6:0]  burst_base_word = 7'd0;
  integer     burst_requests = 0;
  integer     checks = 0;
  integer     failures = 0;
  integer     i;

  always #5 clock = ~clock;

  assign backing_wait_n = !burst_active;

  always @(posedge clock) begin
    backing_valid <= 1'b0;
    if (reset) begin
      burst_active <= 1'b0;
      burst_delay <= 3'd0;
      burst_word <= 2'd0;
      burst_base_word <= 7'd0;
      burst_requests <= 0;
    end else if (!burst_active && backing_rd) begin
      burst_active <= 1'b1;
      burst_delay <= 3'd2;
      burst_word <= 2'd0;
      burst_base_word <= backing_addr[7:1];
      burst_requests <= burst_requests + 1;
    end else if (burst_active && burst_delay != 3'd0) begin
      burst_delay <= burst_delay - 3'd1;
    end else if (burst_active) begin
      backing_dout <= backing_memory[burst_base_word + burst_word];
      backing_valid <= 1'b1;
      if (burst_word == 2'd3) begin
        burst_active <= 1'b0;
      end else begin
        burst_word <= burst_word + 2'd1;
      end
    end
  end

  task check;
    input condition;
    input [8*96-1:0] message;
    begin
      checks = checks + 1;
      if (!condition) begin
        failures = failures + 1;
        $display("FAIL: %0s", message);
      end
    end
  endtask

  task select_and_check_word;
    input [6:0] address;
    input [15:0] expected;
    integer timeout;
    begin
      @(negedge clock);
      upload_addr = {20'd0, address};
      #1;
      check(!upload_wait_n, "address change stalls before the exact cache word is ready");
      timeout = 0;
      while (!upload_wait_n && timeout < 200) begin
        @(posedge clock);
        #1;
        timeout = timeout + 1;
      end
      check(upload_wait_n, "EEPROM upload word becomes ready without deadlock");
      check(upload_dout == expected, "EEPROM upload returns exact cached word");
    end
  endtask

  CaveNvramUploadPrefetch prefetch (
    .clock         (clock),
    .reset         (reset),
    .upload        (upload),
    .upload_addr   (upload_addr),
    .upload_dout   (upload_dout),
    .upload_wait_n (upload_wait_n),
    .mem_rd        (prefetch_mem_rd),
    .mem_addr      (prefetch_mem_addr),
    .mem_dout      (prefetch_mem_dout),
    .mem_wait_n    (prefetch_mem_wait_n),
    .mem_valid     (prefetch_mem_valid)
  );

  CaveNvramEepromArbiter arbiter (
    .clock          (clock),
    .reset          (reset),
    .io_in_0_rd     (prefetch_mem_rd),
    .io_in_0_wr     (1'b0),
    .io_in_0_addr   (prefetch_mem_addr),
    .io_in_0_din    (16'd0),
    .io_in_0_dout   (prefetch_mem_dout),
    .io_in_0_wait_n (prefetch_mem_wait_n),
    .io_in_0_valid  (prefetch_mem_valid),
    .io_in_1_rd     (1'b0),
    .io_in_1_wr     (1'b0),
    .io_in_1_addr   (7'd0),
    .io_in_1_din    (16'd0),
    .io_in_1_dout   (),
    .io_in_1_wait_n (),
    .io_in_1_valid  (),
    .io_out_rd      (cache_rd),
    .io_out_wr      (cache_wr),
    .io_out_addr    (cache_addr),
    .io_out_din     (cache_din),
    .io_out_dout    (cache_dout),
    .io_out_wait_n  (cache_wait_n),
    .io_out_valid   (cache_valid)
  );

  CaveNvramWriteBackCache cache (
    .clock         (clock),
    .reset         (reset),
    .io_enable     (1'b1),
    .io_in_rd      (cache_rd),
    .io_in_wr      (cache_wr),
    .io_in_addr    (cache_addr),
    .io_in_din     (cache_din),
    .io_in_dout    (cache_dout),
    .io_in_wait_n  (cache_wait_n),
    .io_in_valid   (cache_valid),
    .io_out_rd     (backing_rd),
    .io_out_wr     (backing_wr),
    .io_out_addr   (backing_addr),
    .io_out_din    (backing_din),
    .io_out_dout   (backing_dout),
    .io_out_wait_n (backing_wait_n),
    .io_out_valid  (backing_valid)
  );

  initial begin
    for (i = 0; i < 64; i = i + 1)
      backing_memory[i] = {8'h20 + i[7:0], 8'h80 + i[7:0]};

    repeat (5) @(posedge clock);
    reset = 1'b0;
    repeat (5) @(posedge clock);

    // No index-2 download or prior EEPROM read occurs before this upload.
    upload = 1'b1;
    for (i = 0; i < 64; i = i + 1)
      select_and_check_word(i[6:0] << 1,
                            {backing_memory[i][7:0], backing_memory[i][15:8]});
    check(burst_requests == 16,
          "sequential first upload uses one backing burst per cache line");

    @(negedge clock);
    upload = 1'b0;
    repeat (3) @(posedge clock);
    check(upload_wait_n, "inactive upload never stalls ioctl");
    upload = 1'b1;
    select_and_check_word(7'd0,
                          {backing_memory[0][7:0], backing_memory[0][15:8]});
    check(burst_requests == 17,
          "repeated upload re-arms and refills an evicted first cache line");

    @(negedge clock);
    upload = 1'b0;
    repeat (3) @(posedge clock);
    check(upload_wait_n, "completed upload releases ioctl wait");
    check(!backing_wr, "read-only upload never writes backing EEPROM storage");

    if (failures == 0)
      $display("PASS: CaveNvramUploadIntegration %0d checks", checks);
    else
      $fatal(1, "CaveNvramUploadIntegration %0d/%0d checks failed",
             failures, checks);
    $finish;
  end
endmodule
