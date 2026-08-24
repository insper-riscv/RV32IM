library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;

entity RAM_simulation is
  generic (
    dataWidth: natural := 32;
    addrWidth: natural := 30;
    memoryAddrWidth: natural := 9   -- 0 - 511 posicoes de 32 bits cada
  );
  port (
    clk      : in  std_logic;
    addr     : in  std_logic_vector(addrWidth-1 downto 0);
    data_in  : in  std_logic_vector(dataWidth-1 downto 0);
    data_out : out std_logic_vector(dataWidth-1 downto 0);
    weRAM    : in  std_logic;                     -- habilita escrita
    reRAM    : in  std_logic;                     -- habilita leitura
    eRAM     : in  std_logic;                     -- chip enable (RAM ativa)
    mask     : in  std_logic_vector(3 downto 0)   -- byte enables
  );
end entity;

architecture rtl of RAM_simulation is
  type mem_t is array(0 to 2**memoryAddrWidth - 1) of std_logic_vector(31 downto 0);
  signal mem : mem_t := (others => (others => '0'));

  -- word index (32-bit aligned)
  signal widx : std_logic_vector(memoryAddrWidth-1 downto 0):= (others => '0');

  signal data_out_reg : std_logic_vector(31 downto 0) := (others => '0'); -- registro de saída

begin
  -- Was hardcoded to addr(8 downto 0) regardless of memoryAddrWidth
  -- (ROM_simulation's equivalent slice already used the generic
  -- correctly) — meant any word beyond the fixed 512-word range
  -- silently aliased to (real_word_index mod 512) instead of being
  -- reachable, no matter how large memoryAddrWidth/mem itself was set.
  widx <= addr(memoryAddrWidth - 1 downto 0);

  process(clk)
  begin
    if rising_edge(clk) then
      if (weRAM = '1' and eRAM = '1') then
        -- update selected bytes inside the 32-bit word
        if mask(0) = '1' then
          mem(to_integer(unsigned(widx)))(7 downto 0)   <= data_in(7 downto 0);
        end if;
        if mask(1) = '1' then
          mem(to_integer(unsigned(widx)))(15 downto 8)  <= data_in(15 downto 8);
        end if;
        if mask(2) = '1' then
          mem(to_integer(unsigned(widx)))(23 downto 16) <= data_in(23 downto 16);
        end if;
        if mask(3) = '1' then
          mem(to_integer(unsigned(widx)))(31 downto 24) <= data_in(31 downto 24);
        end if;
      end if;
    end if;
  end process;

  -- leitura síncrona: captura mem(...) na subida do clock se eRAM='1' e reRAM='1'
  sync_read: process(clk)
  begin
    if rising_edge(clk) then
      if (eRAM = '1' and reRAM = '1') then
        data_out_reg <= mem(to_integer(unsigned(widx)));
      end if;
      -- caso contrário, mantém o valor anterior (nenhuma alteração)
    end if;
  end process;

  data_out <= data_out_reg;

end architecture;
