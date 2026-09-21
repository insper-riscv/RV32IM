| INST | IMPL | OpCode[6:0] | funct3[2:0] | funct7[6:0] | SelMuxPc4ALU  | opExImm[2:0] | selMuxALUPc4RAM[1:0] | weReg | opExRAM[2:0] | selMuxRS2Imm | selMUXPcRS1 | opALU[4:0] | mask[3:0] | weRAM |
|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|
| LUI       | x[rd] = sext(imm << 12) | 0110111 | - | - |0|U|00|1|XXX|1|X|PASS_B|XXXX|0|
| AUIPC     | x[rd] = pc + sext(imm << 12) | 0010111 | - | - |0|U|00|1|XXX|1|0|ADD|XXXX|0|
| ADDI      | x[rd] = x[rs1] + sext(imm) | 0010011 | 000 | - |0|I|00|1|XXX|1|1|ADD|XXXX|0|
| XORI      | x[rd] = x[rs1] ^ sext(imm) | 0010011 | 100 | - |0|I|00|1|XXX|1|1|XOR|XXXX|0|
| ORI       | x[rd] = x[rs1] \| sext(imm) | 0010011 | 110 | -|0|I|00|1|XXX|1|1|OR |XXXX|0|
| ANDI      | x[rd] = x[rs1] & sext(imm) | 0010011 | 111 | - |0|I|00|1|XXX|1|1|AND|XXXX|0|
| SLLI      | x[rd] = x[rs1] << shamt    | 0010011 | 001 | 0000000  |0|I_shamt|00|1|XXX|1|1|SLL|XXXX|0|
| SRLI      | x[rd] = x[rs1] >>u shamt   | 0010011 | 101 | 0000000  |0|I_shamt|00|1|XXX|1|1|SRL|XXXX|0|
| SRAI      | x[rd] = x[rs1] >>s shamt   | 0010011 | 101 | 0100000  |0|I_shamt|00|1|XXX|1|1|SRA|XXXX|0|
| ADD       | x[rd] = x[rs1] + x[rs2]   | 0110011 | 000 | 0000000  |0|XXX|00|1|XXX|0|1|ADD|XXXX|0|
| SUB       | x[rd] = x[rs1] - x[rs2]   | 0110011 | 000 | 0100000  |0|XXX|00|1|XXX|0|1|SUB|XXXX|0|
| XOR       | x[rd] = x[rs1] ^ x[rs2]   | 0110011 | 100 | 0000000  |0|XXX|00|1|XXX|0|1|XOR|XXXX|0|
| OR        | x[rd] = x[rs1] \| x[rs2]  | 0110011 | 110 | 0000000  |0|XXX|00|1|XXX|0|1|OR|XXXX|0|
| AND       | x[rd] = x[rs1] & x[rs2]   | 0110011 | 111 | 0000000  |0|XXX|00|1|XXX|0|1|AND|XXXX|0|
| SLL       | x[rd] = x[rs1] << x[rs2]  | 0110011 | 001 | 0000000  |0|XXX|00|1|XXX|0|1|SLL|XXXX|0|
| SRL       | x[rd] = x[rs1] >>u x[rs2] | 0110011 | 101 | 0000000  |0|XXX|00|1|XXX|0|1|SRL|XXXX|0|
| SRA       | x[rd] = x[rs1] >>s x[rs2] | 0110011 | 101 | 0100000  |0|XXX|00|1|XXX|0|1|SRA|XXXX|0|
| SLT       | x[rd] = (x[rs1] <s x[rs2]) ? 1:0 | 0110011 | 010 | 0000000 |0|XXX|00|1|XXX|0|1|SLT|XXXX|0|
| SLTU      | x[rd] = (x[rs1] <u x[rs2]) ? 1:0 | 0110011 | 011 | 0000000 |0|XXX|00|1|XXX|0|1|SLTU|XXXX|0|
| JAL       | x[rd] = pc+4; pc=pc+off   | 1101111 | - | - |1|JAL|01|1|XXX|1|0|ADD|XXXX|0|
| JALR      | t=pc+4; pc=(x[rs1]+off)&~1; x[rd]=t | 1100111 | - | - |1|JALR|01|1|XXX|1|1|ADD|XXXX|0|
| BEQ       | if(x[rs1]==x[rs2]) pc+=off | 1100011 | 000 | -       |0|XXX|XX|0|XXX|0|1|BEQ|XXXX|0|
| BNE       | if(x[rs1]!=x[rs2]) pc+=off | 1100011 | 001 | -       |0|XXX|XX|0|XXX|0|1|BNE|XXXX|0|
| BLT       | if(x[rs1]<s x[rs2]) pc+=off | 1100011 | 100 | -      |0|XXX|XX|0|XXX|0|1|BLT|XXXX|0|
| BGE       | if(x[rs1]>=s x[rs2]) pc+=off | 1100011 | 101 | -     |0|XXX|XX|0|XXX|0|1|BGE|XXXX|0|
| BLTU      | if(x[rs1]<u x[rs2]) pc+=off | 1100011 | 110 | -      |0|XXX|XX|0|XXX|0|1|BLTU|XXXX|0|
| BGEU      | if(x[rs1]>=u x[rs2]) pc+=off | 1100011 | 111 | -     |0|XXX|XX|0|XXX|0|1|BGEU|XXXX|0|
| LW        | x[rd] = sext(M[x[rs1]+off][31:0]) | 0000011 | 010 | - |0|I|10|1|LW|1|1|ADD|XXXX|0|
| LH        | x[rd] = sext(M[x[rs1]+off][15:0]) | 0000011 | 001 | - |0|I|10|1|LH|1|1|ADD|XXXX|0|
| LHU       | x[rd] = zeroext(M[x[rs1]+off][15:0]) | 0000011 | 101 | - |0|I|10|1|LHU|1|1|ADD|XXXX|0|
| LB        | x[rd] = sext(M[x[rs1]+off][7:0]) | 0000011 | 000 | - |0|I|10|1|LB|1|1|ADD|XXXX|0|
| LBU       | x[rd] = zeroext(M[x[rs1]+off][7:0]) | 0000011 | 100 | - |0|I|10|1|LBU|1|1|ADD|XXXX|0|
| SW        | M[x[rs1]+off] = x[rs2][31:0] | 0100011 | 010 | - |0|S|XX|0|XXX|1|1|PASS_B|1111|1|
| SH        | M[x[rs1]+off] = x[rs2][15:0] | 0100011 | 001 | - |0|S|XX|0|XXX|1|1|PASS_B|0011|1|
| SB        | M[x[rs1]+off] = x[rs2][7:0] | 0100011 | 000 | -  |0|S|XX|0|XXX|1|1|PASS_B|0001|1|
| NOP       | - | 0000000 | XXX | XXXXXXX | X |XXX|XX|0|XXX|X|X|X|XXXX|0|

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../LICENSE).
