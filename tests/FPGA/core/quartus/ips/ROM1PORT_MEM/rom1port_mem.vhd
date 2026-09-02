-- Harvard modificado: segunda copia fisica da ROM, so' para leitura de
-- dado pelo estagio MEM (rv32im_pipeline_core.vhd, rom_addr2/rom_rden2/
-- rom_data2). NAO e' uma "porta B" de uma unica ROM dual-port: uma IP
-- altsyncram DUAL_PORT com ENABLE_RUNTIME_MOD=YES (JTAG In-System
-- Memory Content Editor) nao compila nesta edicao do Quartus --
-- confirmado empiricamente (quartus_map real: "Insufficient resources
-- available on RAM to use In-System Memory Content Editor" / assertion
-- de "clear box feature" em altsyncram.tdf, com OU sem os dois clocks
-- iguais). A alternativa e' esta: clone exato de rom1port.vhd (mesma
-- receita, ja' comprovada), so' com INSTANCE_NAME diferente
-- ("ROM_MEM") para o In-System Memory Content Editor tratar como uma
-- instancia JTAG separada.
--
-- As DUAS copias (esta e ips/ROM1PORT/rom1port.vhd) precisam do MESMO
-- conteudo sempre -- Tools/src/riscv_tools/rom_writer regrava as duas
-- via JTAG a cada troca de teste (ver config.yaml quartus.
-- rom_mem_instances, agora uma lista de 2 indices em vez de 1).
LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

ENTITY rom1port_mem IS
	PORT
	(
		address		: IN STD_LOGIC_VECTOR (13 DOWNTO 0);
		clock		: IN STD_LOGIC  := '1';
		rden		: IN STD_LOGIC  := '1';
		wren		: IN STD_LOGIC  := '0';
		data		: IN STD_LOGIC_VECTOR (31 DOWNTO 0) := (OTHERS => '0');
		q		: OUT STD_LOGIC_VECTOR (31 DOWNTO 0)
	);
END rom1port_mem;

ARCHITECTURE SYN OF rom1port_mem IS

	SIGNAL sub_wire0	: STD_LOGIC_VECTOR (31 DOWNTO 0);

BEGIN
	q    <= sub_wire0(31 DOWNTO 0);

	altsyncram_component : altsyncram
	GENERIC MAP (
		address_aclr_a => "NONE",
		clock_enable_input_a => "BYPASS",
		clock_enable_output_a => "BYPASS",
		init_file => "./init.mif",
		intended_device_family => "Cyclone V",
		lpm_hint => "ENABLE_RUNTIME_MOD=YES,INSTANCE_NAME=ROM_MEM",
		lpm_type => "altsyncram",
		numwords_a => 16384,
		operation_mode => "SINGLE_PORT",
		outdata_aclr_a => "NONE",
		outdata_reg_a => "UNREGISTERED",
		read_during_write_mode_port_a => "NEW_DATA_NO_NBE_READ",
		widthad_a => 14,
		width_a => 32,
		width_byteena_a => 1
	)
	PORT MAP (
		address_a => address,
		clock0 => clock,
		rden_a => rden,
		wren_a => wren,
		data_a => data,
		q_a => sub_wire0
	);

END SYN;
