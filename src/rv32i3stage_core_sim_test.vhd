library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rv32i_ctrl_consts.all;

entity rv32i3stage_core_sim_test is
	generic (
	  ROM_FILE : string := "default.hex";
	  -- Word-address width of ROM_simulation/RAM_simulation's internal
	  -- memory array (depth = 2**width words) — both default to 9 (512
	  -- words) inside ROM_simulation/RAM_simulation themselves, too
	  -- small for a program/mailbox address sized for the real
	  -- ROM1PORT/RAM1PORT hardware (8192/4096 words). Exposed here so a
	  -- full-pipeline testbench can size these to match whatever
	  -- memory map its own C tests were compiled against, without
	  -- editing this file. Left at the same 9/9 default so existing
	  -- callers (e.g. tests/python/tests.json's instruction-level
	  -- tests) are unaffected.
	  rom_addr_width : natural := 9;
	  ram_addr_width : natural := 9
  	);
	port (
    	CLK  : in  std_logic;
		reset : in std_logic := '0'   
  	);
end entity;

architecture behaviour of rv32i3stage_core_sim_test is

	signal rom_addr : std_logic_vector(31 downto 0);
	signal rom_rden : std_logic;
	signal rom_data : std_logic_vector(31 downto 0);

	signal ram_addr : std_logic_vector(31 downto 0);
	signal ram_wdata : std_logic_vector(31 downto 0);
	signal ram_rdata : std_logic_vector(31 downto 0);
	signal ram_en : std_logic;
	signal ram_re_gated : std_logic;
	signal ram_we_gated : std_logic;
	signal ram_wren : std_logic;
	signal ram_rden : std_logic;
	signal ram_byteena : std_logic_vector(3 downto 0);

	signal pll_clk_if     : std_logic;
	signal pll_clk_idexmem: std_logic;
	signal pll_clk_wb     : std_logic;
	signal pll_locked     : std_logic;

begin

	-- Sinais intermediarios para port maps (VHDL-93 nao aceita expressoes em port maps)
	ram_re_gated <= ram_rden and ram_en;
	ram_we_gated <= ram_wren and ram_en;

	pll_inst : entity work.clk_gen_3way
    port map (
      clk_in   => CLK,
      reset      => reset, -- reset ativo alto no PLL
      clk0 => pll_clk_if,
      clk1 => pll_clk_idexmem,
      clk2 => pll_clk_wb
    );

	CORE : entity work.rv32im_pipeline_core
		port map (
			clk          => pll_clk_idexmem,
			reset 		=> reset,

			----------------------------------------------------------------------
			-- Interface com a ROM (somente leitura)
			----------------------------------------------------------------------
			rom_addr => rom_addr,	-- endereço de instrução
			rom_rden => rom_rden,	-- enable de leitura
			rom_data => rom_data,	-- dados lidos da ROM

			----------------------------------------------------------------------
			-- Interface com a RAM (leitura e escrita)
			----------------------------------------------------------------------
			ram_addr    => ram_addr, 	-- endereço de palavra
			ram_wdata   => ram_wdata, 	-- dados a escrever (saida do store manager)
			ram_rdata   => ram_rdata, 	-- dados lidos
			ram_en      => ram_en, 		-- enable ram	
			ram_wren    => ram_wren,    -- write enable
			ram_rden    => ram_rden,    -- read enable
			ram_byteena => ram_byteena 	-- máscara de bytes
	);

	ROM : entity work.ROM_simulation
		generic map (ROM_FILE => ROM_FILE, memoryAddrWidth => rom_addr_width)
		port map (
			addr 	=> rom_addr(31 downto 2),--word addressable
			clk 	=> pll_clk_if,
			re 		=> rom_rden,
			data	=> rom_data
	);

	RAM : entity work.RAM_simulation
		generic map (memoryAddrWidth => ram_addr_width)
		port map(
			addr 		=> ram_addr(31 downto 2), -- word addressable
			mask 		=> ram_byteena,
			clk		 	=> pll_clk_idexmem,
			data_in 	=> ram_wdata,
			reRAM 		=> ram_re_gated,
			weRAM 		=> ram_we_gated,
			eRAM 		=> ram_en,
			data_out 	=> ram_rdata
	);

end architecture;