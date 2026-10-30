// ============================================================================
// canny_top.v  -  DE2-115 top level  (Canny edge detection, snapshot version)
//
//   OV7670 -> luma capture -> snapshot_ctrl -> frame buffer (1 grayscale frame)
//                                                   |
//                  VGA <- Canny on the fly (vga_canny):
//                         Gaussian -> Sobel -> NMS -> hysteresis
//
// Operation
//   After power-up/reset the camera is configured, auto-exposure is given
//   ~0.5 s to settle, and ONE frame is captured automatically.  That frame
//   stays frozen and its Canny edge image is shown on the monitor.
//   Press KEY[1] to take a new snapshot.
//
// Controls
//   KEY[0]     : reset (re-configures the camera, then auto-captures)
//   KEY[1]     : capture a new snapshot
//   SW[0]      : 0 = Canny edges (default), 1 = grayscale snapshot
//   SW[1]      : luma byte phase (flip if the image looks striped/garbled)
//   SW[2]      : 1 = gradient magnitude (Sobel of the blurred image)
//   SW[3]      : 1 = live mode (capture continuously, for aiming the camera)
//   SW[17:10]  : Canny threshold T: high = 4T, low = 2T (all down -> T = 40)
// Status
//   LEDG[0]    : camera configuration finished
//   LEDG[1]    : snapshot captured and frozen
//   LEDR[0]    : toggles every camera frame (VSYNC heartbeat)
//   LEDR[1]    : PCLK alive (slow blink)
//   LEDR[2]    : capturing a frame now
// ============================================================================
module canny_top #(
    parameter SETTLE_FRAMES = 15
)(
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,
    input  wire [17:0] SW,
    output wire [17:0] LEDR,
    output wire [8:0]  LEDG,

    // OV7670 on the JP5 (GPIO) header
    output wire        CAM_XCLK,
    input  wire        CAM_PCLK,
    input  wire        CAM_VSYNC,
    input  wire        CAM_HREF,
    input  wire [7:0]  CAM_D,
    output wire        CAM_SIOC,
    inout  wire        CAM_SIOD,
    output wire        CAM_RESET,   // active low on the module
    output wire        CAM_PWDN,    // active high on the module

    // VGA (ADV7123)
    output wire [7:0]  VGA_R,
    output wire [7:0]  VGA_G,
    output wire [7:0]  VGA_B,
    output wire        VGA_CLK,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire        VGA_BLANK_N,
    output wire        VGA_SYNC_N
);
    // ---------------- reset synchronisers ----------------
    reg [1:0] rst50_s;
    always @(posedge CLOCK_50 or negedge KEY[0])
        if (!KEY[0]) rst50_s <= 2'b00;
        else         rst50_s <= {rst50_s[0], 1'b1};
    wire rst50_n = rst50_s[1];

    reg [1:0] rstp_s;
    always @(posedge CAM_PCLK or negedge KEY[0])
        if (!KEY[0]) rstp_s <= 2'b00;
        else         rstp_s <= {rstp_s[0], 1'b1};
    wire rstp_n = rstp_s[1];

    // ---------------- camera clock: 25 MHz ----------------
    reg xclk_r = 1'b0;
    always @(posedge CLOCK_50) xclk_r <= ~xclk_r;
    assign CAM_XCLK  = xclk_r;
    assign CAM_RESET = 1'b1;
    assign CAM_PWDN  = 1'b0;

    // ---------------- SCCB configuration ----------------
    wire cfg_done;
    ov7670_config u_cfg (
        .clk(CLOCK_50), .rst_n(rst50_n),
        .sioc(CAM_SIOC), .siod(CAM_SIOD), .done(cfg_done)
    );

    // ---------------- synchronisers ----------------
    // PCLK domain: luma phase, live mode, capture key, cfg_done
    reg [3:0] p_s1, p_s2;
    always @(posedge CAM_PCLK) begin
        p_s1 <= {cfg_done, KEY[1], SW[3], SW[1]};
        p_s2 <= p_s1;
    end
    wire y_phase  = p_s2[0];
    wire live     = p_s2[1];
    wire key1_n   = p_s2[2];
    wire cfg_done_p = p_s2[3];

    // 50 MHz domain: display mode + threshold
    reg [9:0] v_s1, v_s2;
    always @(posedge CLOCK_50) begin
        v_s1 <= {SW[17:10], SW[2], SW[0]};
        v_s2 <= v_s1;
    end
    wire       mode_gray = v_s2[0];
    wire       mode_sobel = v_s2[1];
    wire [7:0] thresh    = v_s2[9:2];

    // ---------------- capture ----------------
    wire       pix_valid, frame_tick, frame_start;
    wire [7:0] pix_y;
    wire [9:0] pix_x, next_col;
    wire [8:0] pix_row;

    ov7670_capture u_cap (
        .pclk(CAM_PCLK), .rst_n(rstp_n),
        .vsync(CAM_VSYNC), .href(CAM_HREF), .d(CAM_D), .y_phase(y_phase),
        .pix_valid(pix_valid), .pix_y(pix_y), .pix_x(pix_x), .pix_row(pix_row),
        .next_col(next_col), .frame_tick(frame_tick), .frame_start(frame_start)
    );

    // ---------------- snapshot control ----------------
    wire        fb_we, capturing, snap_valid;
    wire [18:0] fb_waddr;
    wire [7:0]  fb_wdata;

    snapshot_ctrl #(.SETTLE_FRAMES(SETTLE_FRAMES)) u_snap (
        .pclk(CAM_PCLK), .rst_n(rstp_n),
        .frame_start(frame_start), .cfg_done(cfg_done_p),
        .capture_req_n(key1_n), .live(live),
        .pix_valid(pix_valid), .pix_y(pix_y), .pix_x(pix_x), .pix_row(pix_row),
        .we(fb_we), .waddr(fb_waddr), .wdata(fb_wdata),
        .capturing(capturing), .snap_valid(snap_valid)
    );

    // ---------------- frame buffer (grayscale snapshot) ----------------
    wire [18:0] fb_raddr;
    wire [7:0]  fb_rdata;

    frame_buffer u_fb (
        .wclk(CAM_PCLK), .we(fb_we), .waddr(fb_waddr), .wdata(fb_wdata),
        .rclk(CLOCK_50), .raddr(fb_raddr), .rdata(fb_rdata)
    );

    // ---------------- Canny + VGA ----------------
    vga_canny u_vga (
        .clk(CLOCK_50), .rst_n(rst50_n),
        .mode_gray(mode_gray), .mode_sobel(mode_sobel), .thresh(thresh),
        .fb_raddr(fb_raddr), .fb_rdata(fb_rdata),
        .vga_r(VGA_R), .vga_g(VGA_G), .vga_b(VGA_B),
        .vga_hs(VGA_HS), .vga_vs(VGA_VS),
        .vga_blank_n(VGA_BLANK_N), .vga_sync_n(VGA_SYNC_N), .vga_clk(VGA_CLK)
    );

    // ---------------- status LEDs ----------------
    reg [23:0] pclk_div = 24'd0;
    always @(posedge CAM_PCLK) pclk_div <= pclk_div + 24'd1;

    assign LEDG = {7'd0, snap_valid & ~capturing, cfg_done};
    assign LEDR = {15'd0, capturing, pclk_div[23], frame_tick};
endmodule
