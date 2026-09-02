library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity L2IP is
  port   (
    CLOCK_50 : in std_logic;
    LEDR : out std_logic_vector(9 downto 0) := (others => '0');
    SW : in std_logic_vector(9 downto 0);
    FPGA_RESET_N : in std_logic;
    GPIO_P : inout std_logic_vector(31 downto 0)
  );
end entity;

architecture behaviour of L2IP is

  -- ======= sinais do PLL ======
  signal pll_clk_if     : std_logic;
  signal rom_clk        : std_logic;
  signal pll_clk_idexmem: std_logic;
  signal pll_clk_wb     : std_logic;
  signal pll_locked     : std_logic;
  signal sys_reset_n    : std_logic;

  -- ======= cpu <-> memorias =======
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
  signal weGPIO, reGPIO, weTIMER, reTIMER, weLEDS : std_logic;
  signal periph_id : std_logic_vector(2 downto 0);
  signal gpio_op : std_logic_vector(3 downto 0);
  signal timer_op : std_logic_vector(2 downto 0);
  signal gpio_read_data, timer_read_data, periphs_data : std_logic_vector(31 downto 0);

  constant PERIPH_GPIO  : std_logic_vector(2 downto 0) := "010"; -- ex.: 0xA...
  constant PERIPH_LED   : std_logic_vector(2 downto 0) := "001"; -- 0x9...
  constant PERIPH_TIMER : std_logic_vector(2 downto 0) := "011"; -- se precisar

  -- ======= perifericos =======
  signal enable_ram, enable_led, enable_gpio, enable_timer : std_logic;

begin
  ------------------------------------------------------------------------
  -- PLL instantiation
  ------------------------------------------------------------------------
  pll_inst : entity work.pll
    port map (
      refclk   => CLOCK_50,
      rst      => not FPGA_RESET_N, -- reset ativo alto no PLL
      outclk_0 => pll_clk_if,
      outclk_1 => pll_clk_idexmem,
      outclk_2 => pll_clk_wb,
      locked   => pll_locked
    );

  -- O sistema só sai do reset quando o PLL estiver travado
  sys_reset_n <= FPGA_RESET_N;
  rom_clk <= not pll_clk_idexmem;

   -- Decodificação (substituir o bloco antigo)
  periph_id <= ram_addr(30 downto 28);
  gpio_op   <= ram_addr(5 downto 2);

  -- RAM enable: quando bit31 = '1' e periph_id = "000" (0x8xxx_xxxx)
  enable_ram <= '1' when (ram_addr(31) = '1' and periph_id = "000") else '0';

  -- perifericos: somente quando bit31='1' e periph_id correspondem
  enable_gpio <= '1' when (ram_addr(31) = '1' and periph_id = PERIPH_GPIO) else '0';
  enable_led  <= '1' when (ram_addr(31) = '1' and periph_id = PERIPH_LED)  else '0';
  -- enable_timer <= '1' when (ram_addr(31) = '1' and periph_id = PERIPH_TIMER) else '0';

  reGPIO <= enable_gpio and ram_rden;
  weGPIO <= enable_gpio and ram_wren;
  weLEDS <= enable_led and ram_wren;

  -- route read data: peripherals first, else RAM
  periphs_data <= gpio_read_data 
              when (ram_addr(31)='1' and periph_id=PERIPH_GPIO) else
                 timer_read_data
              when (ram_addr(31)='1' and periph_id=PERIPH_TIMER) else
                 ram_rdata;

  ------------------------------------------------------------------------
  -- Núcleo principal (RV32I)
  ------------------------------------------------------------------------
  CORE : entity work.rv32im_pipeline_core
    port map (
      clk          => pll_clk_idexmem,
      reset        => not sys_reset_n,

      ----------------------------------------------------------------------
      -- Interface com a ROM (somente leitura)
      ----------------------------------------------------------------------
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

      ----------------------------------------------------------------------
      -- Interface com a RAM (leitura e escrita)
      ----------------------------------------------------------------------
      ram_addr    => ram_addr,
      ram_wdata   => ram_wdata,
      ram_rdata   => periphs_data,
      ram_en      => ram_en,
      ram_wren    => ram_wren,
      ram_rden    => ram_rden,
      ram_byteena => ram_byteena
    );

  ------------------------------------------------------------------------
  -- ROM e RAM
  ------------------------------------------------------------------------
  ROM : entity work.rom1port
    port map (
      address => rom_addr(14 downto 2),
      clock   => rom_clk,
      rden    => rom_rden,
      q       => rom_data
    );

	RAM : entity work.ram1port
	 port map (
		address => ram_addr(13 downto 2),
		byteena => ram_byteena,
		clock   => pll_clk_idexmem,
		data    => ram_wdata,
		rden    => ram_rden and enable_ram,
		wren    => ram_wren and enable_ram,
		q       => ram_rdata
	 );

  ------------------------------------------------------------------------
  -- Periféricos
  ------------------------------------------------------------------------
  leds : entity work.genericRegister
    generic map ( data_width => 8 )
    port map (
      clock       => pll_clk_idexmem,
      clear       => not sys_reset_n,
      enable      => weLEDS,
      source      => ram_wdata(7 downto 0),
      destination => LEDR(7 downto 0)
    );

  GPIO : entity work.GPIO
    port map (
      clock      => pll_clk_idexmem,
      clear      => not sys_reset_n,
      data_in    => ram_wdata,
      address    => gpio_op,
      write      => weGPIO,
      read       => reGPIO,
      data_out   => gpio_read_data,
      irq        => open,
      gpio_pins  => GPIO_P
    );

  ------------------------------------------------------------------------
  -- LED de status do PLL (opcional)
  ------------------------------------------------------------------------
  LEDR(9) <= pll_locked;  -- acende quando o PLL está travado

end architecture;