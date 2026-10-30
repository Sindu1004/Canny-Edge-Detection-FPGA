// ============================================================================
// gauss3x3.v  -  combinational 3x3 Gaussian blur (Canny step 1)
//
//            | 1 2 1 |
//   blur  =  | 2 4 2 |  / 16      (weights are powers of two: shifts only)
//            | 1 2 1 |
// ============================================================================
module gauss3x3 (
    input  wire [71:0] win,        // {p00..p22}, 8 bits each, p00 in MSBs
    output wire [7:0]  blur
);
    wire [7:0] p00 = win[71:64], p01 = win[63:56], p02 = win[55:48];
    wire [7:0] p10 = win[47:40], p11 = win[39:32], p12 = win[31:24];
    wire [7:0] p20 = win[23:16], p21 = win[15:8],  p22 = win[7:0];

    wire [11:0] corners = {4'd0, p00} + {4'd0, p02} + {4'd0, p20} + {4'd0, p22};
    wire [11:0] edges   = {3'd0, p01, 1'b0} + {3'd0, p10, 1'b0}
                        + {3'd0, p12, 1'b0} + {3'd0, p21, 1'b0};
    wire [11:0] sum     = corners + edges + {2'd0, p11, 2'b0};   // max 4080

    assign blur = sum[11:4];                                     // divide by 16
endmodule
