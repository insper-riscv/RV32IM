library ieee;
use ieee.std_logic_1164.all;
use work.rv32im_pipeline_types.all;

entity reg_ID_EX is
  port (
    clk   : in  std_logic;
    reset : in  std_logic;
    en    : in  std_logic;
    flush : in  std_logic;

    -- Validade do pacote ID/EX
    in_valid : in  std_logic;

    -- Dados do estagio ID
    in_pc      : in  word_t;
    in_pc4     : in  word_t;
    in_rs1_idx : in  reg_t;
    in_rs2_idx : in  reg_t;
    in_rd_idx  : in  reg_t;
    in_rs1_val : in  word_t;
    in_rs2_val : in  word_t;
    in_imm     : in  word_t;

    -- Controle vindo da Control Unit + Bubble Mux
    in_selMuxPc4ALU    : in  std_logic;
    in_selMuxALUPc4RAM : in  wbsel_t;
    in_weReg           : in  std_logic;
    in_opExRAM         : in  opexram_t;
    in_selMuxRS2Imm    : in  std_logic;
    in_selPCRS1        : in  std_logic;
    in_opALU           : in  opalu_t;
    in_isMulDiv        : in  std_logic;
    in_startMul        : in  std_logic;
    in_weRAM           : in  std_logic;
    in_reRAM           : in  std_logic;
    in_eRAM            : in  std_logic;
    in_opCode          : in  std_logic_vector(6 downto 0);
    in_funct3          : in  std_logic_vector(2 downto 0);

    -- Saidas para EX
    idex_valid : out std_logic;

    idex_pc      : out word_t;
    idex_pc4     : out word_t;
    idex_rs1_idx : out reg_t;
    idex_rs2_idx : out reg_t;
    idex_rd_idx  : out reg_t;
    idex_rs1_val : out word_t;
    idex_rs2_val : out word_t;
    idex_imm     : out word_t;

    idex_selMuxPc4ALU    : out std_logic;
    idex_selMuxALUPc4RAM : out wbsel_t;
    idex_weReg           : out std_logic;
    idex_opExRAM         : out opexram_t;
    idex_selMuxRS2Imm    : out std_logic;
    idex_selPCRS1        : out std_logic;
    idex_opALU           : out opalu_t;
    idex_isMulDiv        : out std_logic;
    idex_startMul        : out std_logic;
    idex_weRAM           : out std_logic;
    idex_reRAM           : out std_logic;
    idex_eRAM            : out std_logic;
    idex_opCode          : out std_logic_vector(6 downto 0);
    idex_funct3          : out std_logic_vector(2 downto 0)
  );
end entity reg_ID_EX;

architecture rtl of reg_ID_EX is
  signal r_valid : std_logic := '0';

  signal r_pc      : word_t := (others => '0');
  signal r_pc4     : word_t := (others => '0');
  signal r_rs1_idx : reg_t  := (others => '0');
  signal r_rs2_idx : reg_t  := (others => '0');
  signal r_rd_idx  : reg_t  := (others => '0');
  signal r_rs1_val : word_t := (others => '0');
  signal r_rs2_val : word_t := (others => '0');
  signal r_imm     : word_t := (others => '0');

  signal r_selMuxPc4ALU    : std_logic := '0';
  signal r_selMuxALUPc4RAM : wbsel_t   := (others => '0');
  signal r_weReg           : std_logic := '0';
  signal r_opExRAM         : opexram_t := (others => '0');
  signal r_selMuxRS2Imm    : std_logic := '0';
  signal r_selPCRS1        : std_logic := '0';
  signal r_opALU           : opalu_t   := (others => '0');
  signal r_isMulDiv        : std_logic := '0';
  signal r_startMul        : std_logic := '0';
  signal r_weRAM           : std_logic := '0';
  signal r_reRAM           : std_logic := '0';
  signal r_eRAM            : std_logic := '0';
  signal r_opCode          : std_logic_vector(6 downto 0) := (others => '0');
  signal r_funct3          : std_logic_vector(2 downto 0) := (others => '0');
begin

  process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        r_valid <= '0';

        r_pc      <= (others => '0');
        r_pc4     <= (others => '0');
        r_rs1_idx <= (others => '0');
        r_rs2_idx <= (others => '0');
        r_rd_idx  <= (others => '0');
        r_rs1_val <= (others => '0');
        r_rs2_val <= (others => '0');
        r_imm     <= (others => '0');

        r_selMuxPc4ALU    <= '0';
        r_selMuxALUPc4RAM <= (others => '0');
        r_weReg           <= '0';
        r_opExRAM         <= (others => '0');
        r_selMuxRS2Imm    <= '0';
        r_selPCRS1        <= '0';
        r_opALU           <= (others => '0');
        r_isMulDiv        <= '0';
        r_startMul        <= '0';
        r_weRAM           <= '0';
        r_reRAM           <= '0';
        r_eRAM            <= '0';
        r_opCode          <= (others => '0');
        r_funct3          <= (others => '0');

      elsif flush = '1' then
        -- Flush injeta bolha e limpa sinais com efeito colateral.
        r_valid <= '0';

        r_pc      <= (others => '0');
        r_pc4     <= (others => '0');
        r_rs1_idx <= (others => '0');
        r_rs2_idx <= (others => '0');
        r_rd_idx  <= (others => '0');
        r_rs1_val <= (others => '0');
        r_rs2_val <= (others => '0');
        r_imm     <= (others => '0');

        r_selMuxPc4ALU    <= '0';
        r_selMuxALUPc4RAM <= (others => '0');
        r_weReg           <= '0';
        r_opExRAM         <= (others => '0');
        r_selMuxRS2Imm    <= '0';
        r_selPCRS1        <= '0';
        r_opALU           <= (others => '0');
        r_isMulDiv        <= '0';
        r_startMul        <= '0';
        r_weRAM           <= '0';
        r_reRAM           <= '0';
        r_eRAM            <= '0';
        r_opCode          <= (others => '0');
        r_funct3          <= (others => '0');

      elsif en = '1' then
        r_valid <= in_valid;

        r_pc      <= in_pc;
        r_pc4     <= in_pc4;
        r_rs1_idx <= in_rs1_idx;
        r_rs2_idx <= in_rs2_idx;
        r_rd_idx  <= in_rd_idx;
        r_rs1_val <= in_rs1_val;
        r_rs2_val <= in_rs2_val;
        r_imm     <= in_imm;

        r_selMuxPc4ALU    <= in_selMuxPc4ALU;
        r_selMuxALUPc4RAM <= in_selMuxALUPc4RAM;
        r_weReg           <= in_weReg;
        r_opExRAM         <= in_opExRAM;
        r_selMuxRS2Imm    <= in_selMuxRS2Imm;
        r_selPCRS1        <= in_selPCRS1;
        r_opALU           <= in_opALU;
        r_isMulDiv        <= in_isMulDiv;
        r_startMul        <= in_startMul;
        r_weRAM           <= in_weRAM;
        r_reRAM           <= in_reRAM;
        r_eRAM            <= in_eRAM;
        r_opCode          <= in_opCode;
        r_funct3          <= in_funct3;
      end if;
      -- en = '0': hold
    end if;
  end process;

  idex_valid <= r_valid;

  idex_pc      <= r_pc;
  idex_pc4     <= r_pc4;
  idex_rs1_idx <= r_rs1_idx;
  idex_rs2_idx <= r_rs2_idx;
  idex_rd_idx  <= r_rd_idx;
  idex_rs1_val <= r_rs1_val;
  idex_rs2_val <= r_rs2_val;
  idex_imm     <= r_imm;

  idex_selMuxPc4ALU    <= r_selMuxPc4ALU;
  idex_selMuxALUPc4RAM <= r_selMuxALUPc4RAM;
  idex_weReg           <= r_weReg;
  idex_opExRAM         <= r_opExRAM;
  idex_selMuxRS2Imm    <= r_selMuxRS2Imm;
  idex_selPCRS1        <= r_selPCRS1;
  idex_opALU           <= r_opALU;
  idex_isMulDiv        <= r_isMulDiv;
  idex_startMul        <= r_startMul;
  idex_weRAM           <= r_weRAM;
  idex_reRAM           <= r_reRAM;
  idex_eRAM            <= r_eRAM;
  idex_opCode          <= r_opCode;
  idex_funct3          <= r_funct3;

end architecture rtl;
