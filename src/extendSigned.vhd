library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity extendSigned is
  generic   (
    DATA_WIDTH  : natural :=  8;
    ADDR_WIDTH  : natural :=  8
  );

  port   (
    -- Input ports
	 entradaA : in std_logic_vector(31 downto 0);
	 entradaB : in std_logic_vector(31 downto 0);
	 controle : in std_logic_vector(1 downto 0);

    -- Output ports
    saidaA   : out std_logic_vector(32 downto 0);
	 saidaB   : out std_logic_vector(32 downto 0)
  );
end entity;


architecture arch_name of extendSigned is

  

begin

  -- Para instanciar, a atribuição de sinais (e generics) segue a ordem: (nomeSinalArquivoDefinicaoComponente => nomeSinalNesteArquivo)
  
  -- signed = controle <= '11'
  -- unsigned = controle <= '00'
  -- signed e unsigned <= '10'
  
  -- Ultimo ramo de cada atribuicao SEM condicao (nao "when controle =
  -- ...") de proposito: controle so' tem 3 valores usados de verdade
  -- (11/10/00), mas e' um vetor de 2 bits (4 combinacoes) -- sem um
  -- else incondicional pro "01" nao-usado, o sintetizador nao consegue
  -- provar cobertura total e infere uma latch pra saidaA/saidaB
  -- inteiras (33 bits cada). Cai no mesmo valor que "00" ja' dava,
  -- comportamento identico pros casos reais.
  saidaA <= entradaA(31) & entradaA when controle = "11" else
            entradaA(31) & entradaA when controle = "10" else
            '0' & entradaA;

  saidaB <= entradaB(31) & entradaB when controle = "11" else
            '0' & entradaB when controle = "10" else
            '0' & entradaB;

end architecture;