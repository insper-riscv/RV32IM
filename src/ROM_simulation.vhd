  library IEEE;
  use IEEE.std_logic_1164.all;
  use ieee.numeric_std.all;
  use std.textio.all;

  entity ROM_simulation is
    generic (
      dataWidth: natural := 32;
      addrWidth: natural := 30;
      memoryAddrWidth: natural := 9;
      ROM_FILE: string := "initROM.hex"
    );
    port (
      addr : in  std_logic_vector (addrWidth-1 downto 0);
      clk  : in  std_logic;
      re   : in  std_logic;
      data : out std_logic_vector (dataWidth-1 downto 0);

      -- Harvard modificado: segunda porta de leitura, mesmo array
      -- memROM, dominio de clock proprio -- paridade com rom2port.vhd
      -- (hardware real), usada pelo estagio MEM do core.
      addr2 : in  std_logic_vector (addrWidth-1 downto 0) := (others => '0');
      clk2  : in  std_logic := '0';
      re2   : in  std_logic := '0';
      data2 : out std_logic_vector (dataWidth-1 downto 0)
    );
  end entity;

  architecture rtl of ROM_simulation is
    type blocoMemoria is array(0 to 2**memoryAddrWidth - 1)
      of std_logic_vector(dataWidth-1 downto 0);

    signal memROM : blocoMemoria := (others => (others => '0'));
    signal localAddress : std_logic_vector(memoryAddrWidth-1 downto 0) := (others => '0');
    signal data_reg : std_logic_vector(dataWidth-1 downto 0) := (others => '0');

    signal localAddress2 : std_logic_vector(memoryAddrWidth-1 downto 0) := (others => '0');
    signal data_reg2 : std_logic_vector(dataWidth-1 downto 0) := (others => '0');

    -- Converte um caractere hex num nibble
    function hex_char_to_nibble(c : character) return std_logic_vector is
      variable nibble : std_logic_vector(3 downto 0);
    begin
      case c is
        when '0' => nibble := "0000";
        when '1' => nibble := "0001";
        when '2' => nibble := "0010";
        when '3' => nibble := "0011";
        when '4' => nibble := "0100";
        when '5' => nibble := "0101";
        when '6' => nibble := "0110";
        when '7' => nibble := "0111";
        when '8' => nibble := "1000";
        when '9' => nibble := "1001";
        when 'a'|'A' => nibble := "1010";
        when 'b'|'B' => nibble := "1011";
        when 'c'|'C' => nibble := "1100";
        when 'd'|'D' => nibble := "1101";
        when 'e'|'E' => nibble := "1110";
        when 'f'|'F' => nibble := "1111";
        when others  => nibble := "0000";
      end case;
      return nibble;
    end function;

    -- Converte string hex de 8 chars numa std_logic_vector(31 downto 0)
    function hex_string_to_slv(s : string) return std_logic_vector is
      variable result : std_logic_vector(31 downto 0) := (others => '0');
    begin
      for i in 1 to s'length loop
        result := result(27 downto 0) & hex_char_to_nibble(s(i));
      end loop;
      return result;
    end function;

  begin

    init: process
      file f : text open read_mode is ROM_FILE;
      variable l    : line;
      variable idx  : integer := 0;
      variable s    : string(1 to 8);
      variable slen : integer;
      variable ch   : character;
      variable ok   : boolean;
    begin
      while not endfile(f) loop
        readline(f, l);
        slen := l'length;
        if slen >= 8 then
          for i in 1 to 8 loop
            read(l, ch, ok);
            s(i) := ch;
          end loop;
          if idx <= memROM'high then
            memROM(idx) <= hex_string_to_slv(s);
          end if;
          idx := idx + 1;
        end if;
      end loop;
      wait;
    end process;

    localAddress <= addr(memoryAddrWidth-1 downto 0);
    localAddress2 <= addr2(memoryAddrWidth-1 downto 0);

    sync_read: process(clk)
    begin
      if rising_edge(clk) then
        if re = '1' then
          data_reg <= memROM(to_integer(unsigned(localAddress)));
        end if;
      end if;
    end process;

    sync_read2: process(clk2)
    begin
      if rising_edge(clk2) then
        if re2 = '1' then
          data_reg2 <= memROM(to_integer(unsigned(localAddress2)));
        end if;
      end if;
    end process;

    data <= data_reg;
    data2 <= data_reg2;

  end architecture;
