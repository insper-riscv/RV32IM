-- =============================================================================
-- reg_EX_MEM.vhd
-- Registrador de pipeline entre os estagios EX e MEM
--
-- Captura, a cada borda de subida, os resultados computados no estagio EX
-- e os disponibiliza ao estagio MEM (M3).
--
-- Campos armazenados:
--   valid             : validade do pacote (0 = bolha)
--   pc4               : PC+4, propagado para instrucoes JAL/JALR (rd <- PC+4)
--   alu_out           : resultado final do estagio EX (saida do mux selMuxPc4ALU)
--                       tambem serve como endereco de RAM para loads e stores
--   store_data        : dado alinhado para escrita (saida do StoreManager)
--   byteena           : habilitacao de bytes para escrita na RAM (StoreManager)
--   rd_idx            : indice do registrador destino (para WB e Forwarding)
--   weReg             : write enable para o RegFile (propagado ate WB)
--   weRAM / reRAM / eRAM : controles de acesso a RAM
--   opExRAM           : tipo de extensao para leituras de RAM (ExtenderRAM)
--   selMuxALUPc4RAM   : selecao do mux de WB (ALU / PC4 / RAM)
--
-- Controle de en e flush:
--   en    : '0' congela o registrador (load-use no futuro ou muldiv_busy).
--           Como muldiv_busy='0' nesta versao, en e sempre '1'.
--   flush : '0' nesta versao; reservado para flush por excecao (M3+).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.rv32im_pipeline_types.all;

entity reg_EX_MEM is
  port (
    clk   : in  std_logic;
    reset : in  std_logic;
    en    : in  std_logic;
    flush : in  std_logic;

    -- Validade do pacote EX/MEM
    in_valid : in  std_logic;

    -- PC+4 propagado (retorno de JAL/JALR)
    in_pc4 : in  word_t;

    -- Resultado final do estagio EX (saida do mux selMuxPc4ALU)
    -- Para instrucoes de memoria: tambem e o endereco calculado pela ALU.
    in_alu_out : in  word_t;

    -- Dado e mascara de bytes para stores (saidas do StoreManager)
    in_store_data : in  word_t;
    in_byteena    : in  std_logic_vector(3 downto 0);

    -- Indice do registrador destino
    in_rd_idx : in  reg_t;

    -- Sinais de controle propagados para o estagio MEM / WB
    in_weReg           : in  std_logic;
    in_weRAM           : in  std_logic;
    in_reRAM           : in  std_logic;
    in_eRAM            : in  std_logic;
    in_opExRAM         : in  opexram_t;
    in_selMuxALUPc4RAM : in  wbsel_t;

    -- =========================================================================
    -- Saidas para o estagio MEM (consumidas por M3)
    -- =========================================================================
    exmem_valid : out std_logic;

    -- Dados
    exmem_pc4         : out word_t;
    exmem_alu_out     : out word_t;
    exmem_store_data  : out word_t;
    exmem_byteena     : out std_logic_vector(3 downto 0);
    exmem_rd_idx      : out reg_t;

    -- Controle
    exmem_weReg           : out std_logic;
    exmem_weRAM           : out std_logic;
    exmem_reRAM           : out std_logic;
    exmem_eRAM            : out std_logic;
    exmem_opExRAM         : out opexram_t;
    exmem_selMuxALUPc4RAM : out wbsel_t
  );
end entity reg_EX_MEM;

architecture rtl of reg_EX_MEM is
  signal r_valid : std_logic := '0';

  signal r_pc4        : word_t                    := (others => '0');
  signal r_alu_out    : word_t                    := (others => '0');
  signal r_store_data : word_t                    := (others => '0');
  signal r_byteena    : std_logic_vector(3 downto 0) := (others => '0');
  signal r_rd_idx     : reg_t                     := (others => '0');

  signal r_weReg           : std_logic := '0';
  signal r_weRAM           : std_logic := '0';
  signal r_reRAM           : std_logic := '0';
  signal r_eRAM            : std_logic := '0';
  signal r_opExRAM         : opexram_t := (others => '0');
  signal r_selMuxALUPc4RAM : wbsel_t   := (others => '0');
begin

  process(clk)
  begin
    if rising_edge(clk) then

      if reset = '1' then
        r_valid <= '0';

        r_pc4        <= (others => '0');
        r_alu_out    <= (others => '0');
        r_store_data <= (others => '0');
        r_byteena    <= (others => '0');
        r_rd_idx     <= (others => '0');

        r_weReg           <= '0';
        r_weRAM           <= '0';
        r_reRAM           <= '0';
        r_eRAM            <= '0';
        r_opExRAM         <= (others => '0');
        r_selMuxALUPc4RAM <= (others => '0');

      elsif flush = '1' then
        -- Flush zera o pacote e todos os sinais com efeito colateral.
        -- Reservado para flush por excecao (M3+). Por ora flush='0'.
        r_valid <= '0';

        r_pc4        <= (others => '0');
        r_alu_out    <= (others => '0');
        r_store_data <= (others => '0');
        r_byteena    <= (others => '0');
        r_rd_idx     <= (others => '0');

        r_weReg           <= '0';
        r_weRAM           <= '0';
        r_reRAM           <= '0';
        r_eRAM            <= '0';
        r_opExRAM         <= (others => '0');
        r_selMuxALUPc4RAM <= (others => '0');

      elsif en = '1' then
        r_valid <= in_valid;

        r_pc4        <= in_pc4;
        r_alu_out    <= in_alu_out;
        r_store_data <= in_store_data;
        r_byteena    <= in_byteena;
        r_rd_idx     <= in_rd_idx;

        r_weReg           <= in_weReg;
        r_weRAM           <= in_weRAM;
        r_reRAM           <= in_reRAM;
        r_eRAM            <= in_eRAM;
        r_opExRAM         <= in_opExRAM;
        r_selMuxALUPc4RAM <= in_selMuxALUPc4RAM;
      end if;
      -- en = '0': hold (stall por muldiv_busy)

    end if;
  end process;

  -- Saidas diretamente dos registros internos
  exmem_valid <= r_valid;

  exmem_pc4        <= r_pc4;
  exmem_alu_out    <= r_alu_out;
  exmem_store_data <= r_store_data;
  exmem_byteena    <= r_byteena;
  exmem_rd_idx     <= r_rd_idx;

  exmem_weReg           <= r_weReg;
  exmem_weRAM           <= r_weRAM;
  exmem_reRAM           <= r_reRAM;
  exmem_eRAM            <= r_eRAM;
  exmem_opExRAM         <= r_opExRAM;
  exmem_selMuxALUPc4RAM <= r_selMuxALUPc4RAM;

end architecture rtl;
