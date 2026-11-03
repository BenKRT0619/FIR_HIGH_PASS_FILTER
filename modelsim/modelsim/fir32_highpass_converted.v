//==============================================================================
// File        : fir32_highpass_converted.v
// Description : 32-tap High-pass FIR Filter - Direct Form - Converted coefficients
//               Bo loc FIR thong cao 32 he so, kien truc Direct Form.
// Format      : Q15 signed 16-bit (x_in, y_out, coefficients)
// Coefficients: Low-pass Q15 reference modulated by (-1)^n; HP fc = 0.3*fs (600 Hz)
//               N = 32, signed two's complement Q15, 32 hardcoded coefficient words
// Accumulator : 37-bit signed  = 32-bit product + ceil(log2(32)) = 5 guard bits
// Latency     : 2 clock (1 clk thanh ghi dich/x_in, 1 clk thanh ghi y_out)
// Reset       : rst_n active-low, asynchronous reset only (no reset synchronizer)
//==============================================================================
`timescale 1ns / 1ps

module fir32_highpass_converted #(
    parameter TAPS = 32,            // So tap cua bo loc / Number of taps
    parameter DW   = 16,            // Do rong du lieu Q15 / Data width
    parameter CW   = 16,            // Do rong he so Q15 / Coefficient width
    parameter AW   = 37             // Do rong accumulator / Accumulator width
)(
    input  wire                 clk,    // Clock he thong / System clock
    input  wire                 rst_n,  // Reset muc thap / Active-low reset
    input  wire signed [DW-1:0] x_in,   // Mau vao Q15 / Input sample Q15
    output reg  signed [DW-1:0] y_out   // Mau ra Q15 / Output sample Q15
);

    //--------------------------------------------------------------------------
    // 1. Bang he so Q15 (hardcode) / Coefficient table (hardcoded)
    //    h[n] phan doi xung (h[n] = -h[31-n]) -> Type IV linear phase.
    //    32 gia tri duoc lay truc tiep tu file HEX cua luong thiet ke.
    //    Gia tri am duoc bieu dien bang bu 2, khong thay doi kien truc MAC.
    //    Dung wire + assign de hang so tong hop duoc tren ca FPGA va ASIC.
    //--------------------------------------------------------------------------
    wire signed [CW-1:0] coeff [0:TAPS-1];

    assign coeff[ 0] = 16'h001F;   //     31
    assign coeff[ 1] = 16'h0025;   //     37
    assign coeff[ 2] = 16'hFFAB;   //    -85
    assign coeff[ 3] = 16'h0000;   //      0
    assign coeff[ 4] = 16'h00BD;   //    189
    assign coeff[ 5] = 16'hFF56;   //   -170
    assign coeff[ 6] = 16'hFF0F;   //   -241
    assign coeff[ 7] = 16'h021A;   //    538
    assign coeff[ 8] = 16'h0000;   //      0
    assign coeff[ 9] = 16'hFC2B;   //   -981
    assign coeff[10] = 16'h032C;   //    812
    assign coeff[11] = 16'h044A;   //   1098
    assign coeff[12] = 16'hF659;   //  -2471
    assign coeff[13] = 16'h0000;   //      0
    assign coeff[14] = 16'h18CC;   //   6348
    assign coeff[15] = 16'hD125;   // -11995
    assign coeff[16] = 16'h2EDB;   //  11995
    assign coeff[17] = 16'hE734;   //  -6348
    assign coeff[18] = 16'h0000;   //      0
    assign coeff[19] = 16'h09A7;   //   2471
    assign coeff[20] = 16'hFBB6;   //  -1098
    assign coeff[21] = 16'hFCD4;   //   -812
    assign coeff[22] = 16'h03D5;   //    981
    assign coeff[23] = 16'h0000;   //      0
    assign coeff[24] = 16'hFDE6;   //   -538
    assign coeff[25] = 16'h00F1;   //    241
    assign coeff[26] = 16'h00AA;   //    170
    assign coeff[27] = 16'hFF43;   //   -189
    assign coeff[28] = 16'h0000;   //      0
    assign coeff[29] = 16'h0055;   //     85
    assign coeff[30] = 16'hFFDB;   //    -37
    assign coeff[31] = 16'hFFE1;   //    -31

    //--------------------------------------------------------------------------
    // 2. Khai bao tin hieu noi bo / Internal signals
    //--------------------------------------------------------------------------
    reg  signed [DW-1:0] shift_reg [0:TAPS-1];  // Thanh ghi dich / Delay line
    reg  signed [AW-1:0] acc;                   // Accumulator 37-bit signed
    reg  signed [DW+CW-1:0] prod;               // Tich rieng 32-bit signed
    wire signed [AW-1:0] acc_shifted;           // acc sau dich phai Q15

    // Gioi han bao hoa Q15 / Q15 saturation limits (sign-extended to AW bits)
    localparam signed [AW-1:0] SAT_MAX =  37'sd32767;
    localparam signed [AW-1:0] SAT_MIN = -37'sd32768;

    integer s;  // Chi so vong lap khoi thanh ghi dich / Shift-block loop index
    integer m;  // Chi so vong lap khoi MAC / MAC-block loop index

    //--------------------------------------------------------------------------
    // 3. Khoi thanh ghi dich / Shift register (delay line) block
    //    shift_reg[0] = x[n], shift_reg[1] = x[n-1], ... shift_reg[31] = x[n-31]
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Xoa toan bo thanh ghi dich / Clear whole delay line
            for (s = 0; s < TAPS; s = s + 1)
                shift_reg[s] <= {DW{1'b0}};
        end else begin
            shift_reg[0] <= x_in;                       // Nap mau moi / Load new sample
            for (s = 1; s < TAPS; s = s + 1)
                shift_reg[s] <= shift_reg[s-1];         // Dich mau cu / Shift old samples
        end
    end

    //--------------------------------------------------------------------------
    // 4. Khoi MAC to hop / Combinational Multiply-Accumulate block
    //    acc = sum( shift_reg[k] * coeff[k] ),  k = 0..TAPS-1
    //    Ca hai toan hang deu signed -> phep nhan co dau, tu dong mo rong dau.
    //    Q15 * Q15 = Q30 (32-bit), cong 32 so -> can them 5 bit = 37-bit.
    //--------------------------------------------------------------------------
    always @(*) begin
        acc = {AW{1'b0}};
        for (m = 0; m < TAPS; m = m + 1) begin
            prod = shift_reg[m] * coeff[m];             // signed 16x16 -> 32-bit
            acc  = acc + prod;                          // sign-extend len 37-bit
        end
    end

    //--------------------------------------------------------------------------
    // 5. Dich phai so hoc >>> 15: dua Q30 ve Q15 / Arithmetic shift Q30 -> Q15
    //--------------------------------------------------------------------------
    assign acc_shifted = acc >>> 15;

    //--------------------------------------------------------------------------
    // 6. Khoi thanh ghi dau ra voi bao hoa / Output register with saturation
    //    Cat 37-bit ve 16-bit Q15; bao hoa neu vuot [-32768, 32767].
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y_out <= {DW{1'b0}};
        end else begin
            if (acc_shifted > SAT_MAX)
                y_out <= 16'sh7FFF;                     // Bao hoa duong / Positive sat
            else if (acc_shifted < SAT_MIN)
                y_out <= 16'sh8000;                     // Bao hoa am / Negative sat
            else
                y_out <= acc_shifted[DW-1:0];           // Cat ve 16-bit / Truncate
        end
    end

endmodule
