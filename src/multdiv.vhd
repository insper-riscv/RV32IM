--------------------------------------------------------------------------------
-- multdiv.vhd  (versao pipeline - com saida_capt e op_latched)
--
-- Diferente da versao anterior:
--   * op_latched: registra qual operacao foi iniciada (para que done_int
--     e saida sejam corretos mesmo quando opCode muda apos desstall)
--   * saida_capt: registra resultado quando done pulsa, mantém estável
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity multdiv is
  generic (
    DATA_WIDTH  : natural :=  8;
    ADDR_WIDTH  : natural :=  8
  );
  port (
    SW      : in  std_logic_vector(9 downto 0) := (others => '0');
    clk     : in  std_logic;
    opCode  : in  std_logic_vector(2 downto 0);
    valorA  : in  std_logic_vector(31 downto 0);
    valorB  : in  std_logic_vector(31 downto 0);

    LEDR    : out std_logic_vector(9 downto 0);
    saida   : out std_logic_vector(31 downto 0);

    rst     : in  std_logic := '0';
    start   : in  std_logic := '0';
    busy    : out std_logic;
    done    : out std_logic
  );
end entity;

architecture arch_name of multdiv is

  signal resultadoMult : std_logic_vector(65 downto 0);
  signal resMult       : std_logic_vector(31 downto 0);

  signal restoDiv   : std_logic_vector(31 downto 0);
  signal resultDiv  : std_logic_vector(31 downto 0);
  signal restoDivU  : std_logic_vector(31 downto 0);
  signal resultDivU : std_logic_vector(31 downto 0);

  signal palavra   : std_logic_vector(4 downto 0);
  signal signedAB  : std_logic_vector(1 downto 0);
  signal operacao  : std_logic_vector(1 downto 0);
  signal maisMenos : std_logic;

  signal outA : std_logic_vector(32 downto 0);
  signal outB : std_logic_vector(32 downto 0);

  -- Qual unidade esta ativa (combinacional, baseado em opCode atual)
  signal isMult     : std_logic;
  signal isUnsigned : std_logic;

  -- Op travada no inicio da operacao (nao muda durante o calculo)
  signal op_latched    : std_logic_vector(2 downto 0) := (others => '0');
  signal isMult_lat    : std_logic;
  signal isUnsigned_lat: std_logic;
  signal operacao_lat  : std_logic_vector(1 downto 0);

  signal mult_busy : std_logic;
  signal mult_done : std_logic;
  signal div_busy  : std_logic;
  signal div_done  : std_logic;
  signal divu_busy : std_logic;
  signal divu_done : std_logic;

  signal done_int  : std_logic;

  -- Correcao MULHU/MULHSU
  signal high_signed    : unsigned(31 downto 0);
  signal corrA          : unsigned(31 downto 0);
  signal corrB          : unsigned(31 downto 0);
  signal high_corrected : unsigned(31 downto 0);

  -- Resultado registrado
  signal saida_capt : std_logic_vector(31 downto 0) := (others => '0');

begin

  -- Decodifica opCode ATUAL (para roteamento de start e busy)
  isMult     <= '1' when opCode(2) = '0' else '0';
  isUnsigned <= '1' when (opCode = "101" or opCode = "111") else '0';

  -- Decodifica opCode TRAVADO (para done_int e saida_capt - estavel durante calculo)
  -- CORRETO: usa o decoderM para mapear op_latched -> operacao
  -- (op_latched(1:0) NAO bate com operacao do decoderM para DIVU/REM/REMU)
  isMult_lat     <= '1' when op_latched(2) = '0' else '0';
  isUnsigned_lat <= '1' when (op_latched = "101" or op_latched = "111") else '0';
  -- operacao do decoderM:
  --   funct3=000/001/010/011 (MUL*)  -> operacao = "10"
  --   funct3=100 (DIV)               -> operacao = "00"
  --   funct3=101 (DIVU)              -> operacao = "00"
  --   funct3=110 (REM)               -> operacao = "01"
  --   funct3=111 (REMU)              -> operacao = "01"
  operacao_lat   <= "10" when op_latched(2) = '0' else
                    "00" when (op_latched = "100" or op_latched = "101") else
                    "01";  -- REM/REMU (110/111)

  -- Trava o opCode no inicio da operacao
  process(clk, rst)
  begin
    if rst = '1' then
      op_latched <= (others => '0');
    elsif rising_edge(clk) then
      if start = '1' then
        op_latched <= opCode;
      end if;
    end if;
  end process;

  -- BUSY: OR de todas as unidades. Independe de op_latched (que tem 1 ciclo de atraso).
  -- Importante: no primeiro ciclo da operacao, op_latched ainda eh da operacao anterior,
  -- entao usar mux baseado em op_latched daria busy errado.
  busy <= mult_busy or div_busy or divu_busy;

  -- DONE: tambem OR. So uma unidade vai estar ativa por vez (rota via 'start').
  -- O multdiv ja garante isso atraves de 'start and isMult' / 'start and (not isMult) and ...'
  done_int <= mult_done or div_done or divu_done;

  done <= done_int;

  MUL: entity work.mult
      port map(
        clk    => clk,
        rst    => rst,
        start  => start and isMult,
        dataa  => outA,
        datab  => outB,
        result => resultadoMult,
        done   => mult_done,
        busy   => mult_busy
        );

  DIV: entity work.div
      port map(
        clk      => clk,
        rst      => rst,
        start    => start and (not isMult) and (not isUnsigned),
        numer    => valorA,
        denom    => valorB,
        quotient => resultDiv,
        remain   => restoDiv,
        done     => div_done,
        busy     => div_busy
        );

  DIVU_inst: entity work.divu
      port map(
        clk      => clk,
        rst      => rst,
        start    => start and (not isMult) and isUnsigned,
        numer    => valorA,
        denom    => valorB,
        quotient => resultDivU,
        remain   => restoDivU,
        done     => divu_done,
        busy     => divu_busy
        );

  DECODER: entity work.decoderM
      port map(
        instru => opCode,
        palavraControle => palavra
        );

  EXTENDER: entity work.extendSigned
      port map(
        entradaA => valorA,
        entradaB => valorB,
        controle => signedAB,
        saidaA   => outA,
        saidaB   => outB
        );

  signedAB  <= palavra(4 downto 3);
  operacao  <= palavra(2 downto 1);
  maisMenos <= palavra(0);

  -- Correcao MULHU/MULHSU
  high_signed <= unsigned(resultadoMult(63 downto 32));

  corrA <= unsigned(valorB) when (valorA(31) = '1' and signedAB(1) = '0')
           else (others => '0');

  corrB <= unsigned(valorA) when (valorB(31) = '1' and signedAB(0) = '0')
           else (others => '0');

  high_corrected <= high_signed + corrA + corrB;

  resMult <= resultadoMult(31 downto 0) when maisMenos = '0' else
             std_logic_vector(high_corrected);

  -- Captura resultado quando done pulsa usando operacao_lat (estavel)
  process(clk, rst)
  begin
    if rst = '1' then
      saida_capt <= (others => '0');
    elsif rising_edge(clk) then
      if done_int = '1' then
        if isMult_lat = '1' then
          saida_capt <= resMult;
        elsif isUnsigned_lat = '1' then
          if operacao_lat = "00" then
            saida_capt <= resultDivU;
          else
            saida_capt <= restoDivU;
          end if;
        else
          if operacao_lat = "00" then
            saida_capt <= resultDiv;
          else
            saida_capt <= restoDiv;
          end if;
        end if;
      end if;
    end if;
  end process;

  saida <= saida_capt;

  LEDR(7 downto 0) <= resultDiv(31 downto 24) when SW(9) = '1' else
                      resultDiv(23 downto 16) when SW(8) = '1' else
                      resultDiv(15 downto 8)  when SW(7) = '1' else
                      resultDiv(7 downto 0)   when SW(6) = '1' else
                      (others => '0');
  LEDR(9 downto 8) <= (others => '0');

end architecture;
