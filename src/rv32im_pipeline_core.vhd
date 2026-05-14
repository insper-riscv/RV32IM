-- =============================================================================
-- rv32im_pipeline_core.vhd
-- Top-level do pipeline RV32IM 5 estagios -- PIPELINE COMPLETO
-- M1: IF + ID + Control Unit + Bubble Mux + HDU + reg_IF_ID + reg_ID_EX
-- M2: EX + reg_EX_MEM + Forwarding Unit + muxes de operandos + logica de branch
-- M3: MEM + WB + reg_MEM_WB + ExtenderRAM + mux final de WB
--
-- EVOLUCAO M3 em relacao a M2:
--   1. Estagio MEM: conectado diretamente via sinais exmem_* (ja estava
--      parcialmente feito em M2). A RAM tem leitura sincrona de 1 ciclo.
--   2. Estagio WB completamente instanciado:
--      - reg_MEM_WB captura metadata do MEM (NAO captura ram_rdata, pois
--        a RAM e registrada e o dado chega no ciclo WB naturalmente).
--      - ExtenderRAM posicionado em WB: recebe ram_rdata + opExRAM_WB +
--        alu_out_WB[1:0] (EA = byte offset) e produz o dado de load extendido.
--      - Mux final de WB: seleciona entre ALU, PC+4 e saida do ExtenderRAM
--        de acordo com selMuxALUPc4RAM_WB.
--   3. Loop do RegFile fechado:
--      - wb_we   <- memwb_weReg
--      - wb_rd   <- memwb_rd_idx
--      - wb_data <- saida do mux final de WB
--   4. Forwarding Unit atualizado: agora conecta memwb_rd_idx e memwb_weReg
--      diretamente (em M2 eram stubs apontando para wb_we/wb_rd constantes).
--
-- CONVENCAO DE ENCODING DO wbsel_t (usado em selMuxALUPc4RAM):
--   "00" = ALU (R-type, I-type ALU, AUIPC, LUI)
--   "01" = PC+4 (JAL, JALR)
--   "10" = RAM extendida (LW/LH/LB/LHU/LBU)
--
--   ATENCAO: Verificar se a Control Unit usa este mesmo encoding ao atribuir
--   selMuxALUPc4RAM. Se usar outra convencao, basta reordenar os casos no
--   mux final de WB (procurar por "Mux final de WB" abaixo).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rv32i_ctrl_consts.all;
use work.rv32im_pipeline_types.all;

entity rv32im_pipeline_core is
  port (
    clk   : in  std_logic;
    reset : in  std_logic;

    -- Interface com a ROM
    rom_addr : out std_logic_vector(31 downto 0);
    rom_rden : out std_logic;
    rom_data : in  std_logic_vector(31 downto 0);

    -- Interface com a RAM
    ram_addr    : out std_logic_vector(31 downto 0);
    ram_wdata   : out std_logic_vector(31 downto 0);
    ram_rdata   : in  std_logic_vector(31 downto 0);
    ram_en      : out std_logic;
    ram_wren    : out std_logic;
    ram_rden    : out std_logic;
    ram_byteena : out std_logic_vector(3 downto 0)
  );
end entity rv32im_pipeline_core;

architecture rtl of rv32im_pipeline_core is

  -- =========================================================================
  -- Sinais de controle de hazard (gerados pela HDU)
  -- =========================================================================
  signal if_pc_write_en : std_logic;
  signal ifid_write_en  : std_logic;
  signal id_bubble_sel  : std_logic;

  -- =========================================================================
  -- Sinais de controle de branch (gerados no estagio EX)
  -- =========================================================================
  signal ex_branch_taken  : std_logic;
  signal ex_jalr_taken    : std_logic;
  signal ex_branch_target : word_t;
  signal ex_jalr_target   : word_t;
  signal pc_src           : std_logic_vector(1 downto 0);

  signal flush_if_id : std_logic;
  signal flush_id_ex : std_logic;

  -- =========================================================================
  -- Stall do muldiv (combinacional = sempre '0' nesta implementacao)
  -- =========================================================================
  signal muldiv_busy   : std_logic;
  signal muldiv_done   : std_logic;
  signal muldiv_stall  : std_logic;  -- busy OR done (cobre ciclo em que saida_capt atualiza)

  -- =========================================================================
  -- Estagio IF: pc_fetch
  -- =========================================================================
  signal if_pc  : word_t;
  signal if_pc4 : word_t;

  -- =========================================================================
  -- Registrador IF/ID
  -- =========================================================================
  signal ifid_valid : std_logic;
  signal ifid_pc    : word_t;
  signal ifid_pc4   : word_t;
  signal ifid_instr : word_t;

  signal ifid_rs1 : reg_t;
  signal ifid_rs2 : reg_t;

  -- =========================================================================
  -- Estagio ID
  -- =========================================================================
  signal id_rs1_idx : reg_t;
  signal id_rs2_idx : reg_t;
  signal id_rd_idx  : reg_t;
  signal id_rs1_val : word_t;
  signal id_rs2_val : word_t;
  signal id_imm     : word_t;

  -- =========================================================================
  -- Control Unit
  -- =========================================================================
  signal cu_selMuxPc4ALU    : std_logic;
  signal cu_opExImm         : opeximm_t;
  signal cu_selMuxALUPc4RAM : wbsel_t;
  signal cu_weReg           : std_logic;
  signal cu_opExRAM         : opexram_t;
  signal cu_selMuxRS2Imm    : std_logic;
  signal cu_selPCRS1        : std_logic;
  signal cu_opALU           : opalu_t;
  signal cu_isMulDiv        : std_logic;
  signal cu_weRAM           : std_logic;
  signal cu_reRAM           : std_logic;
  signal cu_eRAM            : std_logic;
  signal cu_opCode          : std_logic_vector(6 downto 0);
  signal cu_funct3          : std_logic_vector(2 downto 0);

  signal isMulDiv_d   : std_logic := '0';
  signal startMul_raw : std_logic;

  -- =========================================================================
  -- Bubble Mux
  -- =========================================================================
  signal bm_weReg           : std_logic;
  signal bm_startMul        : std_logic;
  signal bm_weRAM           : std_logic;
  signal bm_reRAM           : std_logic;
  signal bm_eRAM            : std_logic;
  signal idex_in_valid      : std_logic;

  -- =========================================================================
  -- Saidas do reg_ID_EX (entradas do estagio EX)
  -- =========================================================================
  signal ex_valid           : std_logic;
  signal ex_pc              : word_t;
  signal ex_pc4             : word_t;
  signal ex_instr           : word_t;
  signal ex_rs1_idx         : reg_t;
  signal ex_rs2_idx         : reg_t;
  signal ex_rd_idx          : reg_t;
  signal ex_rs1_val         : word_t;
  signal ex_rs2_val         : word_t;
  signal ex_imm             : word_t;
  signal ex_selMuxPc4ALU    : std_logic;
  signal ex_selMuxALUPc4RAM : wbsel_t;
  signal ex_weReg           : std_logic;
  signal ex_opExRAM         : opexram_t;
  signal ex_selMuxRS2Imm    : std_logic;
  signal ex_selPCRS1        : std_logic;
  signal ex_opALU           : opalu_t;
  signal ex_isMulDiv        : std_logic;
  signal ex_startMul        : std_logic;
  signal ex_weRAM           : std_logic;
  signal ex_reRAM           : std_logic;
  signal ex_eRAM            : std_logic;
  signal ex_opCode          : std_logic_vector(6 downto 0);
  signal ex_funct3          : std_logic_vector(2 downto 0);

  -- =========================================================================
  -- Estagio EX: forwarding e operandos
  -- =========================================================================
  signal ex_forward_a   : std_logic_vector(1 downto 0);
  signal ex_forward_b   : std_logic_vector(1 downto 0);
  signal ex_fwd_rs1_val : word_t;
  signal ex_fwd_rs2_val : word_t;
  signal ex_alu_op_a    : word_t;
  signal ex_alu_op_b    : word_t;
  signal exmem_weReg_fwd : std_logic;
  signal memwb_weReg_fwd : std_logic;

  -- =========================================================================
  -- Estagio EX: resultados
  -- =========================================================================
  signal ex_alu_result      : word_t;
  signal ex_alu_branch_flag : std_logic;
  signal ex_muldiv_result   : word_t;
  signal ex_alu_mux_result  : word_t;
  signal ex_final_result    : word_t;

  -- =========================================================================
  -- Estagio EX: StoreManager
  -- =========================================================================
  signal ex_store_data    : word_t;
  signal ex_store_byteena : std_logic_vector(3 downto 0);

  -- =========================================================================
  -- Saidas do reg_EX_MEM (entradas do estagio MEM)
  -- =========================================================================
  signal exmem_valid           : std_logic;
  signal exmem_pc4             : word_t;
  signal exmem_alu_out         : word_t;
  signal exmem_store_data      : word_t;
  signal exmem_byteena         : std_logic_vector(3 downto 0);
  signal exmem_rd_idx          : reg_t;
  signal exmem_weReg           : std_logic;
  signal exmem_weRAM           : std_logic;
  signal exmem_reRAM           : std_logic;
  signal exmem_eRAM            : std_logic;
  signal exmem_opExRAM         : opexram_t;
  signal exmem_selMuxALUPc4RAM : wbsel_t;
  signal exmem_funct3          : std_logic_vector(2 downto 0);

  -- =========================================================================
  -- Saidas do reg_MEM_WB (entradas do estagio WB)
  -- =========================================================================
  signal memwb_valid           : std_logic;
  signal memwb_pc4             : word_t;
  signal memwb_alu_out         : word_t;
  signal memwb_rd_idx          : reg_t;
  signal memwb_weReg           : std_logic;
  signal memwb_opExRAM         : opexram_t;
  signal memwb_selMuxALUPc4RAM : wbsel_t;

  -- =========================================================================
  -- Estagio WB: saida do ExtenderRAM (dado de load extendido)
  -- =========================================================================
  signal wb_ram_extended : word_t;

  -- =========================================================================
  -- Write-back: sinais que fecham o loop no RegFile
  -- =========================================================================
  signal wb_we   : std_logic;
  signal wb_rd   : reg_t;
  signal wb_data : word_t;

begin

  -- =========================================================================
  -- Logica combinacional de controle de PC e flush
  -- =========================================================================
  pc_src <= "10" when ex_jalr_taken   = '1' else
            "01" when ex_branch_taken = '1' else
            "00";

  flush_if_id <= ex_branch_taken or ex_jalr_taken;
  flush_id_ex <= ex_branch_taken or ex_jalr_taken;

  -- =========================================================================
  -- Edge detect de isMulDiv para gerar startMul (pulso de 1 ciclo)
  -- =========================================================================
  process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        isMulDiv_d <= '0';
      elsif ifid_write_en = '1' then
        isMulDiv_d <= cu_isMulDiv;
      end if;
    end if;
  end process;

  startMul_raw <= cu_isMulDiv and (not isMulDiv_d);

  -- BUG TIMING (resolvido): saida_capt no multdiv eh atualizado na borda quando done_int=1.
  -- No ciclo em que done_int=1, busy ja caiu para 0 (Booth foi para S_DONE no ciclo anterior).
  -- Sem este OR done, reg_EX_MEM capturaria saida_capt VELHO nesse ciclo.
  -- Com "OR done", o stall continua por 1 ciclo extra ate saida_capt propagar.
  muldiv_stall <= muldiv_busy or muldiv_done;

  idex_in_valid <= ifid_valid and (not id_bubble_sel);

  -- =========================================================================
  -- Campos extraidos da instrucao em IF/ID
  -- =========================================================================
  ifid_rs1   <= ifid_instr(19 downto 15);
  ifid_rs2   <= ifid_instr(24 downto 20);
  id_rs1_idx <= ifid_instr(19 downto 15);
  id_rs2_idx <= ifid_instr(24 downto 20);
  id_rd_idx  <= ifid_instr(11 downto 7);

  -- =========================================================================
  -- IF stage: pc_fetch
  -- =========================================================================
  u_pc_fetch : entity work.pc_fetch
    port map (
      clk            => clk,
      reset          => reset,
      if_pc_write_en => if_pc_write_en,
      pc_src         => pc_src,
      branch_target  => ex_branch_target,
      jalr_target    => ex_jalr_target,
      pc_out         => if_pc,
      pc4_out        => if_pc4,
      rom_addr       => rom_addr,
      rom_rden       => rom_rden
    );

  -- =========================================================================
  -- Registrador IF/ID
  -- =========================================================================
  u_reg_if_id : entity work.reg_IF_ID
    port map (
      clk           => clk,
      reset         => reset,
      ifid_write_en => ifid_write_en,
      flush         => flush_if_id,
      in_pc         => if_pc,
      in_pc4        => if_pc4,
      in_instr      => rom_data,
      ifid_valid    => ifid_valid,
      ifid_pc       => ifid_pc,
      ifid_pc4      => ifid_pc4,
      ifid_instr    => ifid_instr
    );

  -- =========================================================================
  -- ID stage: Control Unit
  -- =========================================================================
  u_control_unit : entity work.control_unit
    port map (
      instruction     => ifid_instr,
      selMuxPc4ALU    => cu_selMuxPc4ALU,
      opExImm         => cu_opExImm,
      selMuxALUPc4RAM => cu_selMuxALUPc4RAM,
      weReg           => cu_weReg,
      opExRAM         => cu_opExRAM,
      selMuxRS2Imm    => cu_selMuxRS2Imm,
      selPCRS1        => cu_selPCRS1,
      opALU           => cu_opALU,
      isMulDiv        => cu_isMulDiv,
      weRAM           => cu_weRAM,
      reRAM           => cu_reRAM,
      eRAM            => cu_eRAM,
      opCode          => cu_opCode,
      funct3_out      => cu_funct3
    );

  -- =========================================================================
  -- ID stage: ExtenderImm
  -- =========================================================================
  u_extender_imm : entity work.ExtenderImm
    port map (
      Inst31downto7 => ifid_instr(31 downto 7),
      opExImm       => std_logic_vector(cu_opExImm),
      signalOut     => id_imm
    );

  -- =========================================================================
  -- ID stage: RegFile
  -- Agora com loop fechado: wb_we/wb_rd/wb_data vem do estagio WB.
  -- =========================================================================
  u_regfile : entity work.RegFile
    port map (
      clk     => clk,
      clear   => reset,
      we      => wb_we,
      rs1     => id_rs1_idx,
      rs2     => id_rs2_idx,
      rd      => wb_rd,
      data_in => wb_data,
      d_rs1   => id_rs1_val,
      d_rs2   => id_rs2_val
    );

  -- =========================================================================
  -- Hazard Detection Unit
  -- =========================================================================
  u_hdu : entity work.hazard_detection_unit
    port map (
      ifid_valid     => ifid_valid,
      ifid_rs1       => ifid_rs1,
      ifid_rs2       => ifid_rs2,
      ifid_opcode    => ifid_instr(6 downto 0),
      idex_rd        => ex_rd_idx,
      idex_reRAM     => ex_reRAM,
      muldiv_busy    => muldiv_stall,
      if_pc_write_en => if_pc_write_en,
      ifid_write_en  => ifid_write_en,
      id_bubble_sel  => id_bubble_sel
    );

  -- =========================================================================
  -- Bubble Mux
  -- =========================================================================
  u_bubble_mux : entity work.bubble_mux
    port map (
      sel_bubble        => id_bubble_sel,
      weReg_i           => cu_weReg,
      weRAM_i           => cu_weRAM,
      reRAM_i           => cu_reRAM,
      eRAM_i            => cu_eRAM,
      startMul_i        => startMul_raw,
      weReg_o           => bm_weReg,
      weRAM_o           => bm_weRAM,
      reRAM_o           => bm_reRAM,
      eRAM_o            => bm_eRAM,
      startMul_o        => bm_startMul
    );

  -- =========================================================================
  -- Registrador ID/EX
  -- =========================================================================
  u_reg_id_ex : entity work.reg_ID_EX
    port map (
      clk    => clk,
      reset  => reset,
      en     => not muldiv_stall,
      flush  => flush_id_ex,

      in_valid   => idex_in_valid,
      in_pc      => ifid_pc,
      in_pc4     => ifid_pc4,
      in_instr   => ifid_instr,
      in_rs1_idx => id_rs1_idx,
      in_rs2_idx => id_rs2_idx,
      in_rd_idx  => id_rd_idx,
      in_rs1_val => id_rs1_val,
      in_rs2_val => id_rs2_val,
      in_imm     => id_imm,

      in_selMuxPc4ALU    => cu_selMuxPc4ALU,
      in_selMuxALUPc4RAM => cu_selMuxALUPc4RAM,
      in_weReg           => bm_weReg,
      in_opExRAM         => cu_opExRAM,
      in_selMuxRS2Imm    => cu_selMuxRS2Imm,
      in_selPCRS1        => cu_selPCRS1,
      in_opALU           => cu_opALU,
      in_isMulDiv        => cu_isMulDiv,
      in_startMul        => bm_startMul,
      in_weRAM           => bm_weRAM,
      in_reRAM           => bm_reRAM,
      in_eRAM            => bm_eRAM,
      in_opCode          => cu_opCode,
      in_funct3          => cu_funct3,

      idex_valid           => ex_valid,
      idex_pc              => ex_pc,
      idex_pc4             => ex_pc4,
      idex_instr           => ex_instr,
      idex_rs1_idx         => ex_rs1_idx,
      idex_rs2_idx         => ex_rs2_idx,
      idex_rd_idx          => ex_rd_idx,
      idex_rs1_val         => ex_rs1_val,
      idex_rs2_val         => ex_rs2_val,
      idex_imm             => ex_imm,
      idex_selMuxPc4ALU    => ex_selMuxPc4ALU,
      idex_selMuxALUPc4RAM => ex_selMuxALUPc4RAM,
      idex_weReg           => ex_weReg,
      idex_opExRAM         => ex_opExRAM,
      idex_selMuxRS2Imm    => ex_selMuxRS2Imm,
      idex_selPCRS1        => ex_selPCRS1,
      idex_opALU           => ex_opALU,
      idex_isMulDiv        => ex_isMulDiv,
      idex_startMul        => ex_startMul,
      idex_weRAM           => ex_weRAM,
      idex_reRAM           => ex_reRAM,
      idex_eRAM            => ex_eRAM,
      idex_opCode          => ex_opCode,
      idex_funct3          => ex_funct3
    );

  -- =========================================================================
  -- EX stage: Forwarding Unit
  -- Agora conectado aos sinais reais memwb_* (em M2 eram stubs constantes).
  -- =========================================================================
  exmem_weReg_fwd <= exmem_weReg and exmem_valid;
  memwb_weReg_fwd <= memwb_weReg and memwb_valid;

  u_forwarding_unit : entity work.forwarding_unit
    port map (
      ex_rs1_idx   => ex_rs1_idx,
      ex_rs2_idx   => ex_rs2_idx,
      exmem_rd_idx => exmem_rd_idx,
      exmem_weReg  => exmem_weReg_fwd,
      memwb_rd_idx => memwb_rd_idx,
      memwb_weReg  => memwb_weReg_fwd,
      forward_A    => ex_forward_a,
      forward_B    => ex_forward_b
    );

  -- =========================================================================
  -- EX stage: Muxes de forwarding 3:1
  -- "10" = EX/MEM, "01" = MEM/WB, "00" = ID/EX (RegFile)
  -- =========================================================================
  ex_fwd_rs1_val <= exmem_alu_out when ex_forward_a = "10" else
                    wb_data       when ex_forward_a = "01" else
                    ex_rs1_val;

  ex_fwd_rs2_val <= exmem_alu_out when ex_forward_b = "10" else
                    wb_data       when ex_forward_b = "01" else
                    ex_rs2_val;

  -- =========================================================================
  -- EX stage: Muxes de operandos da ALU
  -- =========================================================================
  ex_alu_op_a <= ex_fwd_rs1_val when ex_selPCRS1 = '1' else ex_pc;
  ex_alu_op_b <= ex_imm when ex_selMuxRS2Imm = '1' else ex_fwd_rs2_val;

  -- =========================================================================
  -- EX stage: ALU
  -- =========================================================================
  u_alu : entity work.ALU
    port map (
      op      => ex_opALU,
      dA      => ex_alu_op_a,
      dB      => ex_alu_op_b,
      dataOut => ex_alu_result,
      branch  => ex_alu_branch_flag
    );

  -- =========================================================================
  -- EX stage: MulDiv (LPM combinacional, busy sempre '0')
  -- =========================================================================
  u_muldiv : entity work.multdiv
    port map (
      SW     => (others => '0'),
      clk    => clk,
      opCode => ex_funct3,
      valorA => ex_fwd_rs1_val,
      valorB => ex_fwd_rs2_val,
      LEDR   => open,
      saida  => ex_muldiv_result,
      rst    => reset,
      start  => ex_startMul,
      busy   => muldiv_busy,
      done   => muldiv_done
    );

  -- =========================================================================
  -- EX stage: Mux isMulDiv e mux selMuxPc4ALU
  -- =========================================================================
  ex_alu_mux_result <= ex_muldiv_result when ex_isMulDiv     = '1' else ex_alu_result;
  ex_final_result   <= ex_pc4           when ex_selMuxPc4ALU = '1' else ex_alu_mux_result;

  -- =========================================================================
  -- EX stage: Alvos de desvio
  -- =========================================================================
  ex_branch_target <= std_logic_vector(unsigned(ex_pc)          + unsigned(ex_imm));
  ex_jalr_target   <= std_logic_vector(unsigned(ex_fwd_rs1_val) + unsigned(ex_imm))
                        and x"FFFFFFFE";

  -- =========================================================================
  -- EX stage: Decisao de branch/jump tomado
  -- =========================================================================
  ex_branch_taken <= (ex_valid and ex_alu_branch_flag) when ex_opCode = "1100011" else
                      ex_valid                          when ex_opCode = "1101111" else
                     '0';

  ex_jalr_taken   <=  ex_valid when ex_opCode = "1100111" else '0';

  -- =========================================================================
  -- EX stage: StoreManager
  -- =========================================================================
  u_store_manager : entity work.StoreManager
    port map (
      opcode   => ex_opCode,
      funct3   => ex_funct3,
      EA       => ex_alu_result(1 downto 0),
      rs2Val   => ex_fwd_rs2_val,
      data_out => ex_store_data,
      mask     => ex_store_byteena
    );

  -- =========================================================================
  -- Registrador EX/MEM
  -- =========================================================================
  u_reg_ex_mem : entity work.reg_EX_MEM
    port map (
      clk   => clk,
      reset => reset,
      en    => not muldiv_stall,
      flush => '0',

      in_valid           => ex_valid,
      in_pc4             => ex_pc4,
      in_alu_out         => ex_final_result,
      in_store_data      => ex_store_data,
      in_byteena         => ex_store_byteena,
      in_rd_idx          => ex_rd_idx,
      in_weReg           => ex_weReg,
      in_weRAM           => ex_weRAM,
      in_reRAM           => ex_reRAM,
      in_eRAM            => ex_eRAM,
      in_opExRAM         => ex_opExRAM,
      in_selMuxALUPc4RAM => ex_selMuxALUPc4RAM,
      in_funct3          => ex_funct3,

      exmem_valid           => exmem_valid,
      exmem_pc4             => exmem_pc4,
      exmem_alu_out         => exmem_alu_out,
      exmem_store_data      => exmem_store_data,
      exmem_byteena         => exmem_byteena,
      exmem_rd_idx          => exmem_rd_idx,
      exmem_weReg           => exmem_weReg,
      exmem_weRAM           => exmem_weRAM,
      exmem_reRAM           => exmem_reRAM,
      exmem_eRAM            => exmem_eRAM,
      exmem_opExRAM         => exmem_opExRAM,
      exmem_selMuxALUPc4RAM => exmem_selMuxALUPc4RAM,
      exmem_funct3          => exmem_funct3
    );

  -- =========================================================================
  -- MEM stage: interface com a RAM
  --
  -- A RAM_simulation tem leitura SINCRONA: quando reRAM='1' no ciclo N, o
  -- dado aparece em ram_rdata no ciclo N+1. No ciclo N+1 a instrucao ja
  -- estara em WB, e o ExtenderRAM (posicionado em WB) processara ram_rdata.
  --
  -- Endereco e dado de escrita vem diretamente do reg_EX_MEM.
  -- =========================================================================
  ram_addr    <= exmem_alu_out;
  ram_wdata   <= exmem_store_data;
  ram_en      <= exmem_eRAM  and exmem_valid;
  ram_wren    <= exmem_weRAM and exmem_valid;
  ram_rden    <= exmem_reRAM and exmem_valid;
  ram_byteena <= exmem_byteena;

  -- =========================================================================
  -- Registrador MEM/WB
  -- NAO captura ram_rdata: a RAM e registrada e o dado chega naturalmente
  -- no ciclo WB atraves de ram_rdata.
  -- =========================================================================
  u_reg_mem_wb : entity work.reg_MEM_WB
    port map (
      clk   => clk,
      reset => reset,
      en    => not muldiv_stall,
      flush => '0',

      in_valid           => exmem_valid,
      in_pc4             => exmem_pc4,
      in_alu_out         => exmem_alu_out,
      in_rd_idx          => exmem_rd_idx,
      in_weReg           => exmem_weReg,
      in_opExRAM         => exmem_opExRAM,
      in_selMuxALUPc4RAM => exmem_selMuxALUPc4RAM,

      memwb_valid           => memwb_valid,
      memwb_pc4             => memwb_pc4,
      memwb_alu_out         => memwb_alu_out,
      memwb_rd_idx          => memwb_rd_idx,
      memwb_weReg           => memwb_weReg,
      memwb_opExRAM         => memwb_opExRAM,
      memwb_selMuxALUPc4RAM => memwb_selMuxALUPc4RAM
    );

  -- =========================================================================
  -- WB stage: ExtenderRAM
  -- Extende o dado lido da RAM de acordo com o tipo do load (LB/LH/LW/LBU/LHU)
  -- e o byte offset (alu_out[1:0]).
  -- =========================================================================
  u_extender_ram : entity work.ExtenderRAM
    port map (
      signalIn  => ram_rdata,
      opExRAM   => std_logic_vector(memwb_opExRAM),
      EA        => memwb_alu_out(1 downto 0),
      signalOut => wb_ram_extended
    );

  -- =========================================================================
  -- WB stage: Mux final de WB
  --
  -- Encoding assumido (verificar com a Control Unit):
  --   "00" = ALU (R/I/U-type, AUIPC, LUI)
  --   "01" = PC+4 (JAL, JALR)
  --   "10" = RAM extendida (LW/LH/LB/LHU/LBU)
  -- =========================================================================
  wb_data <= memwb_pc4         when memwb_selMuxALUPc4RAM = "01" else
             wb_ram_extended   when memwb_selMuxALUPc4RAM = "10" else
             memwb_alu_out;  -- default "00"

  -- =========================================================================
  -- WB stage: fechamento do loop no RegFile
  -- =========================================================================
  wb_we <= memwb_weReg and memwb_valid;
  wb_rd <= memwb_rd_idx;

end architecture rtl;
