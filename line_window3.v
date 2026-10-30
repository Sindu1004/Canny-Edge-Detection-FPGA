// ============================================================================
// line_window3.v
// Generic 3x3 neighbourhood for a raster stream: two line buffers + nine
// registers.  One pixel enters per ce; the stream is 800 samples per line
// (640 active + 160 blanking zeros), so lb1/lb2 always hold exactly the
// previous one and two lines.
//
//   After a ce that loads the sample at stream position p:
//     right column  = p-1600, p-800, p        (w02, w12, w22)
//     centre (w11)  = p-801
//
//   win = {w00,w01,w02, w10,w11,w12, w20,w21,w22}, w00 in the MSBs.
//   row 0 = top, col 0 = left.
// ============================================================================
module line_window3 #(
    parameter W = 8
)(
    input  wire           clk,
    input  wire           ce,          // one pixel per ce
    input  wire [9:0]     col,         // any counter with period 800
    input  wire [W-1:0]   din,
    output wire [9*W-1:0] win
);
    (* ramstyle = "M9K" *) reg [W-1:0] lb1 [0:1023];   // previous line
    (* ramstyle = "M9K" *) reg [W-1:0] lb2 [0:1023];   // line before that
    reg [W-1:0] q1, q2;

    always @(posedge clk) begin
        q1 <= lb1[col];                 // read in the clock before ce
        q2 <= lb2[col];
        if (ce) begin
            lb1[col] <= din;
            lb2[col] <= q1;
        end
    end

    reg [W-1:0] w00, w01, w02, w10, w11, w12, w20, w21, w22;
    always @(posedge clk) begin
        if (ce) begin
            w00 <= w01;  w01 <= w02;  w02 <= q2;     // two lines up
            w10 <= w11;  w11 <= w12;  w12 <= q1;     // one line up
            w20 <= w21;  w21 <= w22;  w22 <= din;    // current line
        end
    end

    assign win = {w00, w01, w02, w10, w11, w12, w20, w21, w22};
endmodule
