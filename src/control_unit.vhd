-- =============================================================================
-- control_unit.vhd
-- Control Unit do pipeline RV32IM 5 estagios
--
-- SUBSTITUI completamente o InstructionDecoder.vhd.
-- O InstructionDecoder pode ser REMOVIDO do projeto.
--
-- Diferencas em relacao ao InstructionDecoder:
--   1. Entrada e a instrucao completa de 32 bits (instruction),
--      nao tres campos separados. Os campos opcode/funct3/funct7
--      sao extraidos internamente.
--   2. Expoe opCode e funct3_out explicitamente nas portas de saida,
--      necessarios para a Hazard Detection Unit e para propagar
--      pelo registrador ID/EX ate o StoreManager no estagio MEM.
--   3. Expoe funct3_out tambem para o multdiv (operacao M).
--   4. Mantém TODOS os sinais de saida do InstructionDecoder com
--      os MESMOS nomes, para compatibilidade com o core existente:
--        selMuxPc4ALU, opExImm, selMuxALUPc4RAM, weReg, opExRAM,
--        selMuxRS2Imm, selPCRS1, opALU, isMulDiv, weRAM, reRAM, eRAM
--
-- Uso no top-level do pipeline (substituicao direta):
--   -- Antes (core multi-cycle):
--   InstructionDecoder port map(
--       opcode => ROM_out(6 downto 0),
--       funct3 => ROM_out(14 downto 12),
--       funct7 => ROM_out(31 downto 25), ...);
--
--   -- Depois (pipeline):
--   ControlUnit : entity work.control_unit
--       port map(
--           instruction => ifid_instr,   -- saida do reg_IF_ID
--           selMuxPc4ALU => ...,
--           opCode       => idex_opcode, -- NOVO: para HDU e StoreManager
--           funct3_out   => idex_funct3, -- NOVO: para multdiv e StoreManager
--           ...);
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rv32i_ctrl_consts.all;

entity control_unit is
  port (
    -- Instrucao completa vinda do reg_IF_ID
    instruction     : in  std_logic_vector(31 downto 0);

    -- -------------------------------------------------------------------------
    -- Saidas identicas ao InstructionDecoder (mesmos nomes, mesma semantica)
    -- -------------------------------------------------------------------------
    selMuxPc4ALU    : out std_logic;
    opExImm         : out std_logic_vector(2 downto 0);
    selMuxALUPc4RAM : out std_logic_vector(1 downto 0);
    weReg           : out std_logic;
    opExRAM         : out std_logic_vector(2 downto 0);
    selMuxRS2Imm    : out std_logic;
    selPCRS1        : out std_logic;
    opALU           : out std_logic_vector(4 downto 0);
    isMulDiv        : out std_logic;
    weRAM           : out std_logic;
    reRAM           : out std_logic;
    eRAM            : out std_logic;

    -- -------------------------------------------------------------------------
    -- Saidas NOVAS para o pipeline
    -- -------------------------------------------------------------------------
    -- opCode: necessario para a Hazard Detection Unit detectar loads ("0000011")
    --         e para propagar pelo ID/EX ate o StoreManager no estagio MEM.
    opCode          : out std_logic_vector(6 downto 0);

    -- funct3_out: necessario para o multdiv (operacao M) e para o StoreManager
    --             (LB/LH/LW/SB/SH/SW). Propagado pelo ID/EX.
    funct3_out      : out std_logic_vector(2 downto 0)
  );
end entity control_unit;

architecture behaviour of control_unit is

  -- Campos extraidos da instrucao (combinacional, sem registrador)
  signal opcode_i : std_logic_vector(6 downto 0);
  signal funct3_i : std_logic_vector(2 downto 0);
  signal funct7_i : std_logic_vector(6 downto 0);

begin

  -- -------------------------------------------------------------------------
  -- Extracao dos campos da instrucao (combinacional)
  -- -------------------------------------------------------------------------
  opcode_i <= instruction(6  downto 0);
  funct3_i <= instruction(14 downto 12);
  funct7_i <= instruction(31 downto 25);

  -- Repassa os campos extraidos para as saidas do pipeline
  opCode     <= opcode_i;
  funct3_out <= funct3_i;

  -- -------------------------------------------------------------------------
  -- Decodificador principal
  -- Logica identica ao InstructionDecoder.vhd original.
  -- -------------------------------------------------------------------------
  process(opcode_i, funct3_i, funct7_i)
  begin
    -- Defaults (mesmos do InstructionDecoder)
    selMuxPc4ALU    <= '0';
    opExImm         <= (others => '0');
    selMuxALUPc4RAM <= (others => '0');
    weReg           <= '0';
    opExRAM         <= (others => '0');
    selMuxRS2Imm    <= '0';
    selPCRS1        <= '0';
    opALU           <= (others => '0');
    isMulDiv        <= '0';
    weRAM           <= '0';
    reRAM           <= '0';
    eRAM            <= '0';

    case opcode_i is

      -- -----------------------------------------------------------------------
      -- I-type ALU (imediatos e shifts)
      -- -----------------------------------------------------------------------
      when "0010011" =>
        case funct3_i is
          when "001" =>   -- SLLI
            if funct7_i = "0000000" then
              selMuxPc4ALU    <= '0';
              opExImm         <= OPEXIMM_I_SHAMT;
              selMuxALUPc4RAM <= "00";
              weReg           <= '1';
              opExRAM         <= "000";
              selMuxRS2Imm    <= '1';
              selPCRS1        <= '1';
              opALU           <= OPALU_SLL;
              weRAM           <= '0';
              reRAM           <= '0';
              eRAM            <= '0';
            end if;

          when "101" =>   -- SRLI / SRAI
            if funct7_i = "0000000" then
              selMuxPc4ALU    <= '0';
              opExImm         <= OPEXIMM_I_SHAMT;
              selMuxALUPc4RAM <= "00";
              weReg           <= '1';
              opExRAM         <= "000";
              selMuxRS2Imm    <= '1';
              selPCRS1        <= '1';
              opALU           <= OPALU_SRL;
              weRAM           <= '0';
              reRAM           <= '0';
              eRAM            <= '0';
            elsif funct7_i = "0100000" then
              selMuxPc4ALU    <= '0';
              opExImm         <= OPEXIMM_I_SHAMT;
              selMuxALUPc4RAM <= "00";
              weReg           <= '1';
              opExRAM         <= "000";
              selMuxRS2Imm    <= '1';
              selPCRS1        <= '1';
              opALU           <= OPALU_SRA;
              weRAM           <= '0';
              reRAM           <= '0';
              eRAM            <= '0';
            end if;

          when "000" =>   -- ADDI
            selMuxPc4ALU    <= '0';
            opExImm         <= OPEXIMM_I;
            selMuxALUPc4RAM <= "00";
            weReg           <= '1';
            opExRAM         <= "000";
            selMuxRS2Imm    <= '1';
            selPCRS1        <= '1';
            opALU           <= OPALU_ADD;
            weRAM           <= '0';
            reRAM           <= '0';
            eRAM            <= '0';

          when "100" =>   -- XORI
            selMuxPc4ALU    <= '0';
            opExImm         <= OPEXIMM_I;
            selMuxALUPc4RAM <= "00";
            weReg           <= '1';
            opExRAM         <= "000";
            selMuxRS2Imm    <= '1';
            selPCRS1        <= '1';
            opALU           <= OPALU_XOR;
            weRAM           <= '0';
            reRAM           <= '0';
            eRAM            <= '0';

          when "110" =>   -- ORI
            selMuxPc4ALU    <= '0';
            opExImm         <= OPEXIMM_I;
            selMuxALUPc4RAM <= "00";
            weReg           <= '1';
            opExRAM         <= "000";
            selMuxRS2Imm    <= '1';
            selPCRS1        <= '1';
            opALU           <= OPALU_OR;
            weRAM           <= '0';
            reRAM           <= '0';
            eRAM            <= '0';

          when "111" =>   -- ANDI
            selMuxPc4ALU    <= '0';
            opExImm         <= OPEXIMM_I;
            selMuxALUPc4RAM <= "00";
            weReg           <= '1';
            opExRAM         <= "000";
            selMuxRS2Imm    <= '1';
            selPCRS1        <= '1';
            opALU           <= OPALU_AND;
            weRAM           <= '0';
            reRAM           <= '0';
            eRAM            <= '0';

          when "010" =>   -- SLTI
            selMuxPc4ALU    <= '0';
            opExImm         <= OPEXIMM_I;
            selMuxALUPc4RAM <= "00";
            weReg           <= '1';
            opExRAM         <= "000";
            selMuxRS2Imm    <= '1';
            selPCRS1        <= '1';
            opALU           <= OPALU_SLT;
            weRAM           <= '0';
            reRAM           <= '0';
            eRAM            <= '0';

          when "011" =>   -- SLTIU
            selMuxPc4ALU    <= '0';
            opExImm         <= OPEXIMM_I;
            selMuxALUPc4RAM <= "00";
            weReg           <= '1';
            opExRAM         <= "000";
            selMuxRS2Imm    <= '1';
            selPCRS1        <= '1';
            opALU           <= OPALU_SLTU;
            weRAM           <= '0';
            reRAM           <= '0';
            eRAM            <= '0';

          when others => null;
        end case;

      -- -----------------------------------------------------------------------
      -- R-type: RV32I + RV32M (funct7 = "0000001")
      -- -----------------------------------------------------------------------
      when "0110011" =>
        if funct7_i = "0000001" then
          -- Extensao M: MUL / MULH / MULHSU / MULHU / DIV / DIVU / REM / REMU
          isMulDiv        <= '1';
          selMuxPc4ALU    <= '0';
          opExImm         <= (others => '0');
          selMuxALUPc4RAM <= "00";
          weReg           <= '1';
          opExRAM         <= "000";
          selMuxRS2Imm    <= '0';
          selPCRS1        <= '1';
          weRAM           <= '0';
          reRAM           <= '0';
          eRAM            <= '0';
          -- opALU nao e usado quando isMulDiv='1', mas deixa default

        else
          -- RV32I R-type normal
          case funct3_i is
            when "000" =>
              if funct7_i = "0000000" then
                opALU <= OPALU_ADD;
              elsif funct7_i = "0100000" then
                opALU <= OPALU_SUB;
              end if;
              selMuxPc4ALU    <= '0';
              opExImm         <= (others => '0');
              selMuxALUPc4RAM <= "00";
              weReg           <= '1';
              opExRAM         <= "000";
              selMuxRS2Imm    <= '0';
              selPCRS1        <= '1';
              weRAM           <= '0';
              reRAM           <= '0';
              eRAM            <= '0';

            when "100" =>
              opALU    <= OPALU_XOR;
              weReg    <= '1';
              selPCRS1 <= '1';

            when "110" =>
              opALU    <= OPALU_OR;
              weReg    <= '1';
              selPCRS1 <= '1';

            when "111" =>
              opALU    <= OPALU_AND;
              weReg    <= '1';
              selPCRS1 <= '1';

            when "001" =>
              opALU    <= OPALU_SLL;
              weReg    <= '1';
              selPCRS1 <= '1';

            when "101" =>
              if funct7_i = "0000000" then
                opALU <= OPALU_SRL;
              elsif funct7_i = "0100000" then
                opALU <= OPALU_SRA;
              end if;
              weReg    <= '1';
              selPCRS1 <= '1';

            when "010" =>
              opALU    <= OPALU_SLT;
              weReg    <= '1';
              selPCRS1 <= '1';

            when "011" =>
              opALU    <= OPALU_SLTU;
              weReg    <= '1';
              selPCRS1 <= '1';

            when others => null;
          end case;
        end if;

      -- -----------------------------------------------------------------------
      -- Branch (B-type)
      -- -----------------------------------------------------------------------
      when "1100011" =>
        selMuxPc4ALU    <= '0';
        opExImm         <= OPEXIMM_B;
        selMuxALUPc4RAM <= "00";
        weReg           <= '0';
        opExRAM         <= "000";
        selMuxRS2Imm    <= '0';
        selPCRS1        <= '1';
        weRAM           <= '0';
        reRAM           <= '0';
        eRAM            <= '0';

        case funct3_i is
          when "000"  => opALU <= OPALU_BEQ;
          when "001"  => opALU <= OPALU_BNE;
          when "100"  => opALU <= OPALU_BLT;
          when "101"  => opALU <= OPALU_BGE;
          when "110"  => opALU <= OPALU_BLTU;
          when "111"  => opALU <= OPALU_BGEU;
          when others => opALU <= (others => '0');
        end case;

      -- -----------------------------------------------------------------------
      -- Load (I-type loads)
      -- -----------------------------------------------------------------------
      when "0000011" =>
        selMuxPc4ALU    <= '0';
        opExImm         <= OPEXIMM_I;
        selMuxALUPc4RAM <= "10";
        weReg           <= '1';
        selMuxRS2Imm    <= '1';
        selPCRS1        <= '1';
        opALU           <= OPALU_ADD;
        weRAM           <= '0';
        reRAM           <= '1';
        eRAM            <= '1';

        case funct3_i is
          when "010"  => opExRAM <= "000";         -- LW
          when "001"  => opExRAM <= OPEXRAM_LH;    -- LH
          when "101"  => opExRAM <= OPEXRAM_LHU;   -- LHU
          when "000"  => opExRAM <= OPEXRAM_LB;    -- LB
          when "100"  => opExRAM <= OPEXRAM_LBU;   -- LBU
          when others => opExRAM <= "000";
        end case;

      -- -----------------------------------------------------------------------
      -- Store (S-type)
      -- -----------------------------------------------------------------------
      when "0100011" =>
        selMuxPc4ALU    <= '0';
        opExImm         <= OPEXIMM_S;
        selMuxALUPc4RAM <= "00";
        weReg           <= '0';
        opExRAM         <= "000";
        selMuxRS2Imm    <= '1';
        selPCRS1        <= '1';
        opALU           <= OPALU_ADD;
        weRAM           <= '1';
        reRAM           <= '0';
        eRAM            <= '1';

      -- -----------------------------------------------------------------------
      -- LUI
      -- -----------------------------------------------------------------------
      when "0110111" =>
        selMuxPc4ALU    <= '0';
        opExImm         <= OPEXIMM_U;
        selMuxALUPc4RAM <= "00";
        weReg           <= '1';
        opExRAM         <= "000";
        selMuxRS2Imm    <= '1';
        selPCRS1        <= '0';
        opALU           <= OPALU_PASS_B;
        weRAM           <= '0';
        reRAM           <= '0';
        eRAM            <= '0';

      -- -----------------------------------------------------------------------
      -- AUIPC
      -- -----------------------------------------------------------------------
      when "0010111" =>
        selMuxPc4ALU    <= '0';
        opExImm         <= OPEXIMM_U;
        selMuxALUPc4RAM <= "00";
        weReg           <= '1';
        opExRAM         <= "000";
        selMuxRS2Imm    <= '1';
        selPCRS1        <= '0';
        opALU           <= OPALU_ADD;
        weRAM           <= '0';
        reRAM           <= '0';
        eRAM            <= '0';

      -- -----------------------------------------------------------------------
      -- JAL
      -- -----------------------------------------------------------------------
      when "1101111" =>
        selMuxPc4ALU    <= '1';
        opExImm         <= OPEXIMM_J;
        selMuxALUPc4RAM <= "01";
        weReg           <= '1';
        opExRAM         <= "000";
        selMuxRS2Imm    <= '1';
        selPCRS1        <= '0';
        opALU           <= OPALU_ADD;
        weRAM           <= '0';
        reRAM           <= '0';
        eRAM            <= '0';

      -- -----------------------------------------------------------------------
      -- JALR
      -- -----------------------------------------------------------------------
      when "1100111" =>
        selMuxPc4ALU    <= '1';
        opExImm         <= OPEXIMM_I;
        selMuxALUPc4RAM <= "01";
        weReg           <= '1';
        opExRAM         <= "000";
        selMuxRS2Imm    <= '1';
        selPCRS1        <= '1';
        opALU           <= OPALU_JALR;
        weRAM           <= '0';
        reRAM           <= '0';
        eRAM            <= '0';

      when others => null;

    end case;
  end process;

end architecture behaviour;
