library ieee;
use ieee.std_logic_1164.all;

entity rv32im_pipeline_fpga_top is
  port (
    CLOCK_50     : in  std_logic;
    FPGA_RESET_N : in  std_logic;
    LEDR         : out std_logic_vector(9 downto 0)
  );
end entity rv32im_pipeline_fpga_top;

architecture rtl of rv32im_pipeline_fpga_top is
  signal reset : std_logic;

  signal rom_addr : std_logic_vector(31 downto 0);
  signal rom_rden : std_logic;
  signal rom_data : std_logic_vector(31 downto 0);

  signal ram_addr    : std_logic_vector(31 downto 0);
  signal ram_wdata   : std_logic_vector(31 downto 0);
  signal ram_rdata   : std_logic_vector(31 downto 0);
  signal ram_en      : std_logic;
  signal ram_wren    : std_logic;
  signal ram_rden    : std_logic;
  signal ram_byteena : std_logic_vector(3 downto 0);

  signal ram_word_addr : std_logic_vector(11 downto 0);
  signal rom_clk       : std_logic;
begin

  reset <= not FPGA_RESET_N;

  -- The generated ROM IP is synchronous. Clocking it on the opposite phase
  -- lets rom_data settle before the core captures IF/ID on CLOCK_50.
  rom_clk <= not CLOCK_50;

  u_core : entity work.rv32im_pipeline_core
    port map (
      clk   => CLOCK_50,
      reset => reset,

      rom_addr => rom_addr,
      rom_rden => rom_rden,
      rom_data => rom_data,

      -- Harvard modificado: este top nao instancia a segunda porta da
      -- ROM (ainda usa rom1port, somente leitura pelo IF) -- leitura
      -- de dado num endereco de ROM aqui continua voltando 0, mesmo
      -- comportamento de antes desta mudanca, so' nao quebra a
      -- compilacao.
      rom_addr2 => open,
      rom_rden2 => open,
      rom_data2 => (others => '0'),

      ram_addr    => ram_addr,
      ram_wdata   => ram_wdata,
      ram_rdata   => ram_rdata,
      ram_en      => ram_en,
      ram_wren    => ram_wren,
      ram_rden    => ram_rden,
      ram_byteena => ram_byteena
    );

  u_instr_rom : entity work.rom1port
    port map (
      address => rom_addr(14 downto 2),
      clock   => rom_clk,
      q       => rom_data
    );

  ram_word_addr <= ram_addr(13 downto 2);

  u_data_ram : entity work.ram1port
    port map (
      address => ram_word_addr,
      byteena => ram_byteena,
      clock   => CLOCK_50,
      data    => ram_wdata,
      rden    => ram_rden and ram_en,
      wren    => ram_wren and ram_en,
      q       => ram_rdata
    );

  LEDR(0) <= not reset;
  LEDR(1) <= rom_rden;
  LEDR(2) <= ram_en;
  LEDR(3) <= ram_wren;
  LEDR(4) <= ram_rden;
  LEDR(9 downto 5) <= rom_addr(6 downto 2);

end architecture rtl;
