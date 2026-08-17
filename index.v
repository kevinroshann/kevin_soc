`include "clockworks.v"

module SOC (
      input        CLK,
      input        RESET,
      output [4:0] LEDS,
      input        RXD,
      output       TXD
);

// Local parameters (FSM States)
localparam FETCH_INSTR = 2'd0;
localparam FETCH_REGS  = 2'd1;
localparam EXECUTE     = 2'd2;

// Processor registers & state
reg [1:0]  state = FETCH_INSTR;
reg [31:0] MEM [0:20];
reg [31:0] PC = 0;
reg [31:0] instr;
reg [31:0] RegisterBank [0:31];
reg [31:0] rs1;
reg [31:0] rs2;
reg [31:0] aluOut;

// Clock and reset signals from Slow module
wire clk;
wire resetn;

// Instruction decoder
wire isALUreg  =  (instr[6:0] == 7'b0110011); // rd <- rs1 OP rs2
wire isALUimm  =  (instr[6:0] == 7'b0010011); // rd <- rs1 OP Iimm
wire isBranch  =  (instr[6:0] == 7'b1100011); // if(rs1 OP rs2) PC<-PC+Bimm
wire isJALR    =  (instr[6:0] == 7'b1100111); // rd <- PC+4; PC<-rs1+Iimm
wire isJAL     =  (instr[6:0] == 7'b1101111); // rd <- PC+4; PC<-PC+Jimm
wire isAUIPC   =  (instr[6:0] == 7'b0010111); // rd <- PC + Uimm
wire isLUI     =  (instr[6:0] == 7'b0110111); // rd <- Uimm
wire isLoad    =  (instr[6:0] == 7'b0000011); // rd <- mem[rs1+Iimm]
wire isStore   =  (instr[6:0] == 7'b0100011); // mem[rs1+Simm] <- rs2
wire isSYSTEM  =  (instr[6:0] == 7'b1110011); // special (ebreak / ecall)

wire [4:0] rs1Id = instr[19:15];
wire [4:0] rs2Id = instr[24:20];
wire [4:0] rdId  = instr[11:7];

wire [2:0] funct3 = instr[14:12];
wire [6:0] funct7 = instr[31:25];

// Immediate decode
wire [31:0] Uimm = {    instr[31],    instr[30:12], {12{1'b0}}};
wire [31:0] Iimm = {{21{instr[31]}},  instr[30:20]};
wire [31:0] Simm = {{21{instr[31]}},  instr[30:25], instr[11:7]};
wire [31:0] Bimm = {{20{instr[31]}},  instr[7],     instr[30:25], instr[11:8], 1'b0};
wire [31:0] Jimm = {{12{instr[31]}},  instr[19:12], instr[20],    instr[30:21], 1'b0};

// ALU inputs and control
wire [31:0] aluIn1 = rs1;
wire [31:0] aluIn2 = isALUreg ? rs2 : Iimm;
wire [4:0]  shamt  = isALUreg ? rs2[4:0] : instr[24:20];

wire [31:0] writeBackData = aluOut;
wire        writeBackEn   = (state == EXECUTE && (isALUreg || isALUimm));

// Initial memory program & register clearing
integer i;
initial begin
   for (i = 0; i < 32; i = i + 1) begin
      RegisterBank[i] = 32'b0;
   end

   // 0: add x1, x0, x0
   MEM[0] = 32'b0000000_00000_00000_000_00001_0110011;
   // 1: addi x1, x1, 1
   MEM[1] = 32'b000000000001_00001_000_00001_0010011;
   // 2: nop
   MEM[2] = 32'h00000013;
   // 3: nop
   MEM[3] = 32'h00000013;
   // 4: nop
   MEM[4] = 32'h00000013;
   // 5: lw x2,0(x1)
   MEM[5] = 32'b000000000000_00001_010_00010_0000011;
   // 6: sw x2,0(x1)
   MEM[6] = 32'b0000000_00001_00010_010_00000_0100011;
   // 7: ebreak
   MEM[7] = 32'b000000000001_00000_000_00000_1110011;
end

// Clock generator module
Slow #(
   .SLOW(15)
) sl (
   .clk(CLK),
   .resetn(RESET),
   .CLK(clk),
   .RESETN(resetn)
);

// Combinational ALU
always @(*) begin
   case (funct3)
      3'b000: aluOut = (funct7[5] & instr[5]) ? (aluIn1 - aluIn2) : (aluIn1 + aluIn2);
      3'b001: aluOut = aluIn1 << shamt;
      3'b010: aluOut = ($signed(aluIn1) < $signed(aluIn2)) ? 32'd1 : 32'd0;
      3'b011: aluOut = (aluIn1 < aluIn2) ? 32'd1 : 32'd0;
      3'b100: aluOut = aluIn1 ^ aluIn2;
      3'b101: aluOut = funct7[5] ? ($signed(aluIn1) >>> shamt) : (aluIn1 >> shamt);
      3'b110: aluOut = aluIn1 | aluIn2;
      3'b111: aluOut = aluIn1 & aluIn2;
      default: aluOut = 32'b0;
   endcase
end

// Main Execution FSM
// Main Execution FSM
always @(posedge clk) begin
   if (!resetn) begin
      PC    <= 0;
      state <= FETCH_INSTR;
   end else begin
      case (state)
         FETCH_INSTR: begin
            instr <= MEM[PC];
            state <= FETCH_REGS;
         end

         FETCH_REGS: begin
            rs1   <= RegisterBank[rs1Id];
            rs2   <= RegisterBank[rs2Id];
            state <= EXECUTE;
         end

         EXECUTE: begin
            if (isSYSTEM) begin
               // Halt execution on ebreak/ecall
               state <= EXECUTE;
            end else begin
               if (writeBackEn && rdId != 0) begin
                  RegisterBank[rdId] <= writeBackData;
               end
               PC    <= PC + 1;
               state <= FETCH_INSTR;
            end
         end
      endcase
   end
end

// Outputs
assign LEDS = isSYSTEM ? 5'b11111 : {PC[0], isALUreg, isALUimm, isStore, isLoad};
assign TXD  = 1'b0;

`ifdef BENCH
   always @(posedge clk) begin
      if (state == FETCH_INSTR) begin
         $display("PC=%0d", PC);
         case (1'b1)
            isALUreg: $display("ALUreg rd=%d rs1=%d rs2=%d funct3=%b", rdId, rs1Id, rs2Id, funct3);
            isALUimm: $display("ALUimm rd=%d rs1=%d imm=%0d funct3=%b", rdId, rs1Id, Iimm, funct3);
            isBranch: $display("BRANCH");
            isJAL:    $display("JAL");
            isJALR:   $display("JALR");
            isAUIPC:  $display("AUIPC");
            isLUI:    $display("LUI");
            isLoad:   $display("LOAD");
            isStore:  $display("STORE");
            isSYSTEM: $display("SYSTEM");
         endcase
      end
   end
`endif

endmodule