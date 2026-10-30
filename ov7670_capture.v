// ============================================================================
// ov7670_capture.v
// Turns the OV7670 YUV422 byte stream (Y U Y V ...) into 8-bit luma pixels
// with column/row coordinates.  Runs entirely in the camera PCLK domain.
//   VSYNC high  -> vertical blanking (frame start)
//   HREF  high  -> valid line bytes, sampled on PCLK rising edge
// ============================================================================
module ov7670_capture #(
    parameter H_ACT = 640,
    parameter V_ACT = 480
)(
    input  wire       pclk,
    input  wire       rst_n,        // synchronised to pclk
    input  wire       vsync,
    input  wire       href,
    input  wire [7:0] d,
    input  wire       y_phase,      // 0: luma on 1st byte (YUYV), 1: luma on 2nd (UYVY)

    output reg        pix_valid,    // 1-cycle strobe per luma pixel
    output reg  [7:0] pix_y,
    output reg  [9:0] pix_x,
    output reg  [8:0] pix_row,
    output wire [9:0] next_col,     // column of the NEXT pixel (for line-buffer prefetch)
    output reg        frame_tick,   // toggles once per frame (LED heartbeat)
    output reg        frame_start   // 1-cycle pulse at VSYNC rising edge
);
    // register the pad inputs once
    reg       vs_r, hr_r, hr_d;
    reg [7:0] d_r;
    always @(posedge pclk) begin
        vs_r <= vsync;
        hr_r <= href;
        d_r  <= d;
        hr_d <= hr_r;
    end

    reg       byte_sel;
    reg [9:0] col;
    reg [8:0] row;
    reg       vs_d;
    assign next_col = col;

    always @(posedge pclk) begin
        if (!rst_n) begin
            byte_sel <= 1'b0; col <= 10'd0; row <= 9'd0; vs_d <= 1'b0;
            pix_valid <= 1'b0; pix_y <= 8'd0; pix_x <= 10'd0; pix_row <= 9'd0;
            frame_tick <= 1'b0; frame_start <= 1'b0;
        end else begin
            pix_valid   <= 1'b0;
            vs_d        <= vs_r;
            frame_start <= vs_r && !vs_d;
            if (vs_r && !vs_d) frame_tick <= ~frame_tick;

            if (vs_r) begin                       // vertical blanking
                row <= 9'd0; col <= 10'd0; byte_sel <= 1'b0;
            end else if (hr_r) begin              // active line data
                byte_sel <= ~byte_sel;
                if (byte_sel == y_phase) begin    // this byte is luma
                    if (col < H_ACT && row < V_ACT) begin
                        pix_valid <= 1'b1;
                        pix_y     <= d_r;
                        pix_x     <= col;
                        pix_row   <= row;
                    end
                    if (col != 10'h3FF) col <= col + 10'd1;
                end
            end else begin                        // horizontal blanking
                byte_sel <= 1'b0;
                col      <= 10'd0;
                if (hr_d && row != 9'h1FF) row <= row + 9'd1;  // end of a line
            end
        end
    end
endmodule
