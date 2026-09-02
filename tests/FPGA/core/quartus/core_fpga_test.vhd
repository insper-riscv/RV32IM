library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rv32i_ctrl_consts.all;

entity core_fpga_test is
	port (
		CLOCK_50 : in std_logic;
		FPGA_RESET_N : in std_logic := '1';
		LEDR : out std_logic_vector(9 downto 0) := (others => '0')
  	);
end entity;

architecture behaviour of core_fpga_test is

	signal rom_addr : std_logic_vector(31 downto 0);
	signal rom_rden : std_logic;
	signal rom_data : std_logic_vector(31 downto 0);

	signal ram_addr : std_logic_vector(31 downto 0);
	signal ram_wdata : std_logic_vector(31 downto 0);
	signal ram_rdata : std_logic_vector(31 downto 0);
	signal ram_en : std_logic;
	signal ram_wren : std_logic;
	signal ram_rden : std_logic;
	signal ram_byteena : std_logic_vector(3 downto 0);

	signal pll_clk_if     : std_logic;
	signal pll_clk_idexmem: std_logic;
	signal pll_locked     : std_logic;

	-- Mantém core em reset até o PLL estar travado, ou enquanto o
	-- botão físico de reset (FPGA_RESET_N, ativo em nível baixo) for
	-- pressionado o que permite reiniciar o core sem reconfigurar a FPGA
	-- (ex: depois de carregar um novo conteúdo de ROM via JTAG).
	signal core_reset : std_logic;

begin

	pll_inst : entity work.pll
    port map (
      refclk   => CLOCK_50,
      rst      => '0',
      outclk_0 => pll_clk_if,
      outclk_1 => pll_clk_idexmem,
      outclk_2 => open,
      locked   => pll_locked
    );

	core_reset <= (not pll_locked) or (not FPGA_RESET_N);

	CORE : entity work.rv32im_pipeline_core
		port map (
			clk          => pll_clk_idexmem,
			reset        => core_reset,

			rom_addr => rom_addr,
			rom_rden => rom_rden,
			rom_data => rom_data,

			ram_addr    => ram_addr,
			ram_wdata   => ram_wdata,
			ram_rdata   => ram_rdata,
			ram_en      => ram_en,
			ram_wren    => ram_wren,
			ram_rden    => ram_rden,
			ram_byteena => ram_byteena
	);

	ROM : entity work.rom1port
    port map (
      address => rom_addr(14 downto 2),
      clock   => pll_clk_if,
      rden    => rom_rden,
      wren    => '0',
      data    => (others => '0'),
      q       => rom_data
    );

	RAM : entity work.ram1port
	 port map (
		address => ram_addr(13 downto 2),
		byteena => ram_byteena,
		clock   => pll_clk_idexmem,
		data    => ram_wdata,
		rden    => ram_rden and ram_en,
		wren    => ram_wren and ram_en,
		q       => ram_rdata
	 );

	 blink : entity work.Blinky
	 port map (
		clk => CLOCK_50,
		led => LEDR(0)
	 );

end architecture;
