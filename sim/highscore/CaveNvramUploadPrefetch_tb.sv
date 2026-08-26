`timescale 1ns/1ps

module CaveNvramUploadPrefetch_tb;
  reg         clock = 1'b0;
  reg         reset = 1'b1;
  reg         upload = 1'b0;
  reg  [26:0] upload_addr = 27'd0;
  wire [15:0] upload_dout;
  wire        upload_wait_n;
  wire        mem_rd;
  wire [6:0]  mem_addr;
  reg  [15:0] mem_dout = 16'd0;
  wire        mem_wait_n;
  reg         mem_valid = 1'b0;

  reg         response_pending = 1'b0;
  reg  [2:0]  response_delay = 3'd0;
  reg  [6:0]  response_addr = 7'd0;
  integer     requests = 0;
  integer     checks = 0;
  integer     errors = 0;
  integer     word_index;
  integer     timeout;

  always #5 clock = ~clock;

  function [15:0] expected_word;
    input [6:0] address;
    begin
      expected_word = {8'h80 + address, 8'h40 + address};
    end
  endfunction

  assign mem_wait_n = !response_pending;

  always @(posedge clock) begin
    mem_valid <= 1'b0;

    if (reset) begin
      response_pending <= 1'b0;
      response_delay <= 3'd0;
      response_addr <= 7'd0;
      requests <= 0;
    end else begin
      if (mem_rd && mem_wait_n) begin
        response_pending <= 1'b1;
        response_delay <= 3'd3;
        response_addr <= mem_addr;
        requests <= requests + 1;
      end

      if (response_pending) begin
        if (response_delay == 3'd0) begin
          mem_dout <= expected_word(response_addr);
          mem_valid <= 1'b1;
          response_pending <= 1'b0;
        end else begin
          response_delay <= response_delay - 3'd1;
        end
      end
    end
  end

  CaveNvramUploadPrefetch dut (
    .clock         (clock),
    .reset         (reset),
    .upload        (upload),
    .upload_addr   (upload_addr),
    .upload_dout   (upload_dout),
    .upload_wait_n (upload_wait_n),
    .mem_rd        (mem_rd),
    .mem_addr      (mem_addr),
    .mem_dout      (mem_dout),
    .mem_wait_n    (mem_wait_n),
    .mem_valid     (mem_valid)
  );

  task check;
    input condition;
    input [8*96-1:0] message;
    begin
      checks = checks + 1;
      if (!condition) begin
        errors = errors + 1;
        $display("FAIL: %0s", message);
      end
    end
  endtask

  task wait_for_word;
    input [6:0] address;
    begin
      timeout = 0;
      while (!upload_wait_n && timeout < 100) begin
        @(posedge clock);
        timeout = timeout + 1;
      end
      check(upload_wait_n, "upload word became ready");
      check(upload_dout == expected_word(address),
            "upload word matches the requested EEPROM address");
    end
  endtask

  initial begin
    repeat (4) @(posedge clock);
    @(negedge clock);
    reset = 1'b0;

    // No NVRAM download or prior memory access precedes this first upload.
    upload_addr = 27'd0;
    upload = 1'b1;
    #1;
    check(!upload_wait_n, "first upload stalls before sampling address zero");

    for (word_index = 0; word_index < 64; word_index = word_index + 1) begin
      wait_for_word(word_index * 2);
      @(negedge clock);
      upload_addr = upload_addr + 27'd2;
      #1;
      if (word_index != 63)
        check(!upload_wait_n,
              "address advance removes ready before the next HPS sample");
    end

    check(requests == 64, "first upload issued exactly one request per word");

    @(negedge clock);
    upload = 1'b0;
    upload_addr = 27'd0;
    repeat (3) @(posedge clock);
    check(upload_wait_n, "idle upload path never stalls unrelated transfers");

    // A repeated upload must begin with a fresh address-zero prefetch too.
    @(negedge clock);
    upload = 1'b1;
    #1;
    check(!upload_wait_n, "repeated upload re-arms the first-word stall");
    wait_for_word(7'd0);
    check(requests == 65, "repeated upload issued a fresh address-zero read");

    @(negedge clock);
    upload = 1'b0;

    if (errors == 0)
      $display("PASS: CaveNvramUploadPrefetch %0d checks", checks);
    else
      $display("FAIL: CaveNvramUploadPrefetch %0d errors in %0d checks",
               errors, checks);
    $finish;
  end
endmodule
