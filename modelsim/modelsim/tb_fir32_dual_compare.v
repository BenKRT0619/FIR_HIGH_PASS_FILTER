//==============================================================================
// File        : tb_fir32_dual_compare.v
// Description : Dual-track testbench (fir32_highpass_direct + fir32_highpass_converted)
//   - Doc N_SAMPLES mau tu file hex (mac dinh fir_input.hex), cap vao CA 2 DUT tai negedge clk
//   - Ghi y_out (so nguyen co dau, %0d) tai posedge clk ra file text
//   - Cap them LAT=2 chu ky x_in = 0 de xa pipeline -> du N_SAMPLES+LAT dong
//     (dong 1..LAT la 0 do reset/pipeline-fill, dong LAT+1 la y[0], dong cuoi la y[N-1])
//   - TU KIEM TRA: so sanh tung dong voi file expected (hex) do golden model sinh ra
//   - Dem so lan dau ra cham +32767 / -32768 (chung minh nhanh saturation duoc chay)
//
// Plusargs (tat ca tuy chon, co gia tri mac dinh cho bai test "main"):
//   +IN=<hex dau vao>   +EXP_D=<hex expected direct>   +EXP_C=<hex expected converted>
//   +OUT_D=<txt ra direct>   +OUT_C=<txt ra converted>   +FINISH (dung $finish thay $stop)
//==============================================================================
`timescale 1ns / 1ps

module tb_fir32_dual_compare;

    localparam N_SAMPLES = 1000;
    localparam LAT       = 2;                   // do tre RTL (clk)
    localparam N_CAP     = N_SAMPLES + LAT;     // so dong ghi ra / so dong expected

    reg                clk;
    reg                rst_n;
    reg  signed [15:0] x_in;
    wire signed [15:0] y_out_direct;
    wire signed [15:0] y_out_converted;

    reg [15:0] test_data  [0:N_SAMPLES-1];      // bit pattern 16-bit (bu 2)
    reg [15:0] exp_direct [0:N_CAP-1];
    reg [15:0] exp_conv   [0:N_CAP-1];

    reg [8*64-1:0] in_file, exp_d_file, exp_c_file, out_d_file, out_c_file;

    integer fd_direct, fd_converted;
    integer i, dummy;
    integer cap_idx;
    integer err_d, err_c;
    integer sat_hi_d, sat_lo_d, sat_hi_c, sat_lo_c;
    reg     capture_en;

    //--------------------------------------------------------------------------
    // 2 DUT dung chung clk / rst_n / x_in
    //--------------------------------------------------------------------------
    fir32_highpass_direct u_direct (
        .clk(clk), .rst_n(rst_n), .x_in(x_in), .y_out(y_out_direct)
    );

    fir32_highpass_converted u_converted (
        .clk(clk), .rst_n(rst_n), .x_in(x_in), .y_out(y_out_converted)
    );

    //--------------------------------------------------------------------------
    // Clock 100 MHz
    //--------------------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    //--------------------------------------------------------------------------
    // Ghi file + so sanh tai posedge clk (DUT dung NBA nen doc duoc gia tri CU
    // truoc khi y_out cap nhat -> khong race; x_in chi doi o negedge)
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        if (capture_en) begin
            $fdisplay(fd_direct,    "%0d", y_out_direct);
            $fdisplay(fd_converted, "%0d", y_out_converted);

            if (y_out_direct !== exp_direct[cap_idx]) begin
                err_d = err_d + 1;
                if (err_d <= 5)
                    $display("[MISMATCH direct]    line %0d: rtl=%0d expected=%0d",
                             cap_idx+1, y_out_direct, $signed(exp_direct[cap_idx]));
            end
            if (y_out_converted !== exp_conv[cap_idx]) begin
                err_c = err_c + 1;
                if (err_c <= 5)
                    $display("[MISMATCH converted] line %0d: rtl=%0d expected=%0d",
                             cap_idx+1, y_out_converted, $signed(exp_conv[cap_idx]));
            end

            if (y_out_direct    === 16'sh7FFF) sat_hi_d = sat_hi_d + 1;
            if (y_out_direct    === 16'sh8000) sat_lo_d = sat_lo_d + 1;
            if (y_out_converted === 16'sh7FFF) sat_hi_c = sat_hi_c + 1;
            if (y_out_converted === 16'sh8000) sat_lo_c = sat_lo_c + 1;

            cap_idx = cap_idx + 1;
        end
    end

    //--------------------------------------------------------------------------
    // Kich ban chinh
    //--------------------------------------------------------------------------
    initial begin
        capture_en = 1'b0;
        rst_n      = 1'b0;
        x_in       = 16'sd0;
        cap_idx    = 0;
        err_d = 0; err_c = 0;
        sat_hi_d = 0; sat_lo_d = 0; sat_hi_c = 0; sat_lo_c = 0;

        // Gia tri mac dinh (bai test "main"), co the ghi de bang plusargs
        in_file    = "fir_input.hex";
        exp_d_file = "fir_expected_main_direct.hex";
        exp_c_file = "fir_expected_main_converted.hex";
        out_d_file = "fir_out_main_direct.txt";
        out_c_file = "fir_out_main_converted.txt";
        dummy = $value$plusargs("IN=%s",    in_file);
        dummy = $value$plusargs("EXP_D=%s", exp_d_file);
        dummy = $value$plusargs("EXP_C=%s", exp_c_file);
        dummy = $value$plusargs("OUT_D=%s", out_d_file);
        dummy = $value$plusargs("OUT_C=%s", out_c_file);

        // Nap du lieu + kiem tra nap thanh cong (file thieu -> o nho con X)
        $readmemh(in_file,    test_data);
        $readmemh(exp_d_file, exp_direct);
        $readmemh(exp_c_file, exp_conv);
        if ((^test_data[0] === 1'bx) || (^test_data[N_SAMPLES-1] === 1'bx) ||
            (^exp_direct[N_CAP-1] === 1'bx) || (^exp_conv[N_CAP-1] === 1'bx)) begin
            $display("[ERROR] $readmemh that bai hoac file khong du dong (kiem tra duong dan / so dong).");
            $stop;
        end

        fd_direct    = $fopen(out_d_file, "w");
        fd_converted = $fopen(out_c_file, "w");
        if (fd_direct == 0 || fd_converted == 0) begin
            $display("[ERROR] Khong mo duoc file ket qua.");
            $stop;
        end

        #23 rst_n = 1'b1;

        // N_SAMPLES mau that + LAT mau 0 de xa pipeline
        for (i = 0; i < N_CAP; i = i + 1) begin
            @(negedge clk);
            x_in       = (i < N_SAMPLES) ? test_data[i] : 16'sd0;
            capture_en = 1'b1;          // bat dau ghi tu posedge ke tiep
        end

        @(posedge clk);                 // posedge cuoi: ghi dong thu N_CAP
        #1;
        capture_en = 1'b0;

        $fclose(fd_direct);
        $fclose(fd_converted);

        $display("------------------------------------------------------------");
        $display(" Captured lines : %0d (expected %0d)", cap_idx, N_CAP);
        $display(" Direct    : mismatches = %0d | sat +32767 = %0d, -32768 = %0d", err_d, sat_hi_d, sat_lo_d);
        $display(" Converted : mismatches = %0d | sat +32767 = %0d, -32768 = %0d", err_c, sat_hi_c, sat_lo_c);
        if (err_d == 0 && err_c == 0 && cap_idx == N_CAP)
            $display(" *** PASS: RTL khop 100%% voi golden model (bit-exact) ***");
        else
            $display(" *** FAIL: RTL khac golden model ***");
        $display("------------------------------------------------------------");

        if ($test$plusargs("FINISH")) $finish;
        else                          $stop;       // $stop de con xem waveform
    end

endmodule
