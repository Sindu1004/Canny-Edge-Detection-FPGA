// ============================================================================
// nms3x3.v  -  non-maximum suppression (Canny step 3)
// Keeps the centre magnitude only if it is the peak along the gradient
// direction, which thins every edge to one pixel.
//
//   dir 0 : left  (m10) / right (m12)
//   dir 1 : up-left (m00) / down-right (m22)
//   dir 2 : up    (m01) / down  (m21)
//   dir 3 : up-right (m02) / down-left (m20)
//
// Tie rule  c > a  and  c >= b  keeps exactly one pixel of a flat-topped
// two-pixel ridge.
// ============================================================================
module nms3x3 (
    input  wire [10:0] m00, m01, m02,
    input  wire [10:0] m10, m11, m12,
    input  wire [10:0] m20, m21, m22,
    input  wire [1:0]  dir,           // direction of the centre pixel
    output wire [10:0] nms
);
    reg [10:0] a, b;
    always @(*) begin
        case (dir)
            2'd0:    begin a = m10; b = m12; end
            2'd1:    begin a = m00; b = m22; end
            2'd2:    begin a = m01; b = m21; end
            default: begin a = m02; b = m20; end
        endcase
    end

    assign nms = ((m11 > a) && (m11 >= b)) ? m11 : 11'd0;
endmodule
