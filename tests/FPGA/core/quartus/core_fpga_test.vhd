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

	-- Harvard modificado: porta B da ROM, leitura pelo estagio MEM
	signal rom_addr2 : std_logic_vector(31 downto 0);
	signal rom_rden2 : std_logic;
	signal rom_data2 : std_logic_vector(31 downto 0);

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

	-- rst era amarrado em '0' antes -- nunca pulsado. gui_pll_auto_reset
	-- esta' "Off" nesta IP (ver pll.vhd), ou seja o PLL NAO tenta
	-- re-travar sozinho se perder o lock por qualquer motivo (ruido de
	-- alimentacao, etc.) -- fica preso ate a FPGA inteira ser
	-- reconfigurada, mesmo que o resto do sistema (JTAG TAP, que e' um
	-- bloco fixo independente desta logica) continue respondendo
	-- normalmente. Ligar ao botao fisico de reset da' um caminho de
	-- recuperacao mais barato que desligar a placa inteira -- se essa
	-- for mesmo a causa da instabilidade intermitente de JTAG vista em
	-- HARDWARE_PROGRAMMING.md/docs/DATA_HARVARD_BUG.md, apertar o botao
	-- deve bastar em vez de precisar de power-cycle completo.
	pll_inst : entity work.pll
    port map (
      refclk   => CLOCK_50,
      rst      => not FPGA_RESET_N,
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

			rom_addr2 => rom_addr2,
			rom_rden2 => rom_rden2,
			rom_data2 => rom_data2,

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
      address => rom_addr(15 downto 2),
      clock   => pll_clk_if,
      rden    => rom_rden,
      wren    => '0',
      data    => (others => '0'),
      q       => rom_data
    );

	RAM : entity work.ram1port
	 port map (
		address => ram_addr(15 downto 2),
		byteena => ram_byteena,
		clock   => pll_clk_idexmem,
		data    => ram_wdata,
		rden    => ram_rden and ram_en,
		wren    => ram_wren and ram_en,
		q       => ram_rdata
	 );

	-- Harvard modificado: segunda copia fisica da ROM, so' para leitura
	-- de dado pelo estagio MEM (mesmo clock que a RAM, ja' que e' o
	-- MEM stage que consome as duas). Nao e' uma "porta B" da mesma
	-- IP -- ver o comentario em ips/ROM1PORT_MEM/rom1port_mem.vhd para
	-- o porque (ENABLE_RUNTIME_MOD nao compila em DUAL_PORT nesta
	-- edicao do Quartus). Instanciada DEPOIS de RAM de proposito, para
	-- nao mudar o indice de instancia JTAG que RAM ja' tinha (1) --
	-- ver config.yaml quartus.ram_mem_instance/mailbox_mem_instance.
	ROM_MEM : entity work.rom1port_mem
    port map (
      address => rom_addr2(15 downto 2),
      clock   => pll_clk_idexmem,
      rden    => rom_rden2,
      wren    => '0',
      data    => (others => '0'),
      q       => rom_data2
    );

	 blink : entity work.Blinky
	 port map (
		clk => CLOCK_50,
		led => LEDR(0)
	 );

end architecture;
