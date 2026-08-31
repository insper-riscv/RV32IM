library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity decoderM is
  generic   (
    DATA_WIDTH  : natural :=  8;
    ADDR_WIDTH  : natural :=  8
  );

  port   (
    -- Input ports
    instru  : in std_logic_vector(2 downto 0);

    -- Output ports
    palavraControle : out std_logic_vector(4 downto 0)
  );
end entity;


architecture arch_name of decoderM is

  -- Declarations (optional):

begin

  -- Para instanciar, a atribuição de sinais (e generics) segue a ordem: (nomeSinalArquivoDefinicaoComponente => nomeSinalNesteArquivo)
  -- Ultimo ramo SEM condicao (nao "when instru = "111"") de proposito:
  -- as 8 combinacoes de instru (3 bits) estao todas listadas aqui, mas
  -- um "when" condicional no ultimo ramo nao basta pro sintetizador
  -- provar cobertura total (nao cobre metavalores) -- sem um else
  -- incondicional, infere uma latch pra palavraControle inteira (5
  -- bits). Mesmo valor que "111" ja' dava, comportamento identico pro
  -- caso real.
  palavraControle <= '1' & '1' & "10" & '0' when instru = "000" else --Mul
                     '1' & '1' & "10" & '1' when instru = "001" else --MulH
							'1' & '0' & "10" & '1' when instru = "010" else --MulHSU
							'0' & '0' & "10" & '1' when instru = "011" else --MulHU
							'1' & '1' & "00" & '0' when instru = "100" else --Div
							'0' & '0' & "00" & '0' when instru = "101" else --DivU
							'1' & '1' & "01" & '0' when instru = "110" else --Rem
							'0' & '0' & "01" & '0';                          --RemU
end architecture;