# Passo 0 - Contrato de sinais do pipeline RV32IM (5 estagios, 1 clock)

Este documento define o contrato de sinais entre os 4 registradores de pipeline:

- IF/ID
- ID/EX
- EX/MEM
- MEM/WB

Objetivo: permitir implementacao em paralelo (M1 e M2) com interface fechada, sem depender de detalhes internos de cada modulo.

## 1. Premissas adotadas

- Baseado no core de pipeline em `src/rv32im_pipeline_core.vhd` e nos modulos:
  - `src/control_unit.vhd`
  - `src/bubble_mux.vhd`
  - `src/pc_fetch.vhd`
  - `src/reg_IF_ID.vhd`
  - `src/reg_ID_EX.vhd`
  - `src/ExtenderImm.vhd`
  - `src/ExtenderRAM.vhd`
  - `src/StoreManager.vhd`
  - `src/ALU.vhd`
- O pipeline alvo e: IF -> ID -> EX -> MEM -> WB.
- Cada registrador de pipeline tera `clk`, `reset`, `en` (stall) e `flush`.
- Cada registrador tera bit `valid` para bolhas (bubble).
- Nomes seguem prefixo por estagio:
  - `ifid_*`, `idex_*`, `exmem_*`, `memwb_*`.
- Na medida do possivel, manter compatibilidade com nomes do diagrama (ex.: `ALU_out_WB`, `PC4_WB`, `opExRAM_WB`, `rd_WB`, `weReg_WB`, `selMux_WB`, `forward_A`, `forward_B`, `IFID_write`).

## 1.1 Convencao de nomes (alinhada ao diagrama)

Para reduzir atrito na implementacao, usar duas visoes equivalentes:

- Nome estrutural (contrato): `ifid_*`, `idex_*`, `exmem_*`, `memwb_*`.
- Alias legivel no estilo do diagrama: sufixos `_ID`, `_EX`, `_MEM`, `_WB` e sinais classicos de controle (`forward_A`, `forward_B`, `IFID_write`, `PC_write`, `sel_bubble`).

Regra pratica:

- Dentro dos registradores de pipeline: priorizar nome estrutural (`idex_*`, etc.).
- No top-level de integracao (`rv32im_pipeline_core`): pode expor alias no estilo diagrama para debug e roteamento visual.

## 1.2 Tabela de equivalencia (Contrato x Diagrama)

| Contrato (recomendado) | Alias no diagrama | Tipo |
|---|---|---|
| `ifid_write_en` | `IFID_write` | `std_logic` |
| `if_pc_write_en` | `PC_write` | `std_logic` |
| `id_bubble_sel` | `sel_bubble` | `std_logic` |
| `idex_rs1_idx` | `rs1` (na Forwarding Unit) | `reg_t` |
| `idex_rs2_idx` | `rs2` (na Forwarding Unit) | `reg_t` |
| `fwd_sel_a` | `forward_A` | `std_logic_vector(1 downto 0)` |
| `fwd_sel_b` | `forward_B` | `std_logic_vector(1 downto 0)` |
| `exmem_ctrl_reg_we` | `weReg_Mem` | `std_logic` |
| `memwb_ctrl_reg_we` | `weReg_WB` | `std_logic` |
| `exmem_rd_idx` | `rd_Mem` | `reg_t` |
| `memwb_rd_idx` | `rd_WB` | `reg_t` |
| `exmem_alu_result` | `ALU_out_Mem` | `word_t` |
| `memwb_alu_result` | `ALU_out_WB` | `word_t` |
| `memwb_pc4` | `PC4_WB` | `word_t` |
| `memwb_ctrl_wb_sel` | `selMux_WB` | `wbsel_t` |
| `exmem_ctrl_load_op`/`memwb_ctrl_load_op` | `opExRAM_WB` (na borda para WB) | `opexram_t` |
| `idex_ctrl_is_muldiv` | `isMulDiv` | `std_logic` |
| `ex_muldiv_start` | `startMul` | `std_logic` |
| `pipe_stall_muldiv` | `Stall` | `std_logic` |

## 2. Tipos base sugeridos (package)

Sugestao: criar package (ex.: `src/rv32im_pipeline_types.vhd`) para evitar divergencia entre toplevels.

```vhdl
subtype word_t  is std_logic_vector(31 downto 0);
subtype reg_t   is std_logic_vector(4 downto 0);
subtype opalu_t is std_logic_vector(4 downto 0);
subtype opeximm_t is std_logic_vector(2 downto 0);
subtype opexram_t is std_logic_vector(2 downto 0);
subtype wbsel_t is std_logic_vector(1 downto 0);
subtype mask4_t is std_logic_vector(3 downto 0);
```

Mapeamento para compatibilidade com a control unit:

- `opalu_t` = `opALU`
- `opeximm_t` = `opExImm`
- `opexram_t` = `opExRAM`
- `wbsel_t` = `selMuxALUPc4RAM`

### 2.1 Como usar na pratica

1. O arquivo do package ja foi criado em [src/rv32im_pipeline_types.vhd](src/rv32im_pipeline_types.vhd).
2. Em cada top-level/registrador de pipeline, adicione:

```vhdl
library ieee;
use ieee.std_logic_1164.all;
use work.rv32im_pipeline_types.all;
```

3. Troque vetores "soltos" pelos tipos nomeados.

Exemplo de porta no registrador ID/EX:

```vhdl
entity rv32im_pipe_reg_id_ex_top is
  port (
    clk, reset, en, flush : in  std_logic;
    idex_in_pc            : in  word_t;
    idex_in_rs1_idx       : in  reg_t;
    idex_in_alu_op        : in  opalu_t;
    idex_in_load_op       : in  opexram_t;
    idex_in_wb_sel        : in  wbsel_t;
    idex_in_store_mask    : in  mask4_t;

    idex_out_pc           : out word_t;
    idex_out_rs1_idx      : out reg_t;
    idex_out_alu_op       : out opalu_t;
    idex_out_load_op      : out opexram_t;
    idex_out_wb_sel       : out wbsel_t;
    idex_out_store_mask   : out mask4_t
  );
end entity;
```

4. Ganho pratico: se no futuro mudar largura (ex.: virar RV64), voce muda o tipo em um lugar so e todo mundo herda.

## 3. Contrato IF/ID

Sinais que cruzam IF -> ID:

| Sinal | Tipo | Produtor | Consumidor | Observacao |
|---|---|---|---|---|
| `ifid_valid` | `std_logic` | IF | ID | `0` = bubble |
| `ifid_write_en` | `std_logic` | Hazard Unit | IF/ID reg | equivalente a `IFID_write` |
| `ifid_pc` | `word_t` | IF | ID | PC da instrucao |
| `ifid_pc4` | `word_t` | IF | ID | PC + 4 |
| `ifid_instr` | `word_t` | IF | ID | instrucao da ROM |

## 4. Contrato ID/EX (critico M1/M2)

Sinais que cruzam ID -> EX (contrato principal):

### 4.1 Dados

| Sinal | Tipo | Produtor | Consumidor | Observacao |
|---|---|---|---|---|
| `idex_valid` | `std_logic` | ID | EX | bubble control |
| `idex_pc` | `word_t` | ID | EX | base para branch/jalr |
| `idex_pc4` | `word_t` | ID | EX/WB | usado em JAL/JALR no WB |
| `idex_instr` | `word_t` | ID | EX | debug/tracing opcional |
| `idex_rs1_idx` | `reg_t` | ID | EX | para forwarding/hazard |
| `idex_rs2_idx` | `reg_t` | ID | EX | para forwarding/hazard |
| `idex_rd_idx` | `reg_t` | ID | EX/WB | destino de escrita |
| `idex_rs1_val` | `word_t` | ID | EX | operando A bruto |
| `idex_rs2_val` | `word_t` | ID | EX/MEM | operando B bruto/store |
| `idex_imm` | `word_t` | ID | EX | imediato expandido |

### 4.2 Controle ALU/fluxo

| Sinal | Tipo | Produtor | Consumidor | Observacao |
|---|---|---|---|---|
| `idex_ctrl_sel_pc_rs1` | `std_logic` | ID | EX | equivale a `selPCRS1` |
| `idex_ctrl_sel_rs2_imm` | `std_logic` | ID | EX | equivale a `selMuxRS2Imm` |
| `idex_ctrl_alu_op` | `opalu_t` | ID | EX | codigo ALU/branch/jalr |
| `idex_ctrl_sel_pc_target` | `std_logic` | ID | EX | equivale a `selMuxPc4ALU` |
| `fwd_sel_a` | `std_logic_vector(1 downto 0)` | Forwarding Unit | EX | equivale a `forward_A` |
| `fwd_sel_b` | `std_logic_vector(1 downto 0)` | Forwarding Unit | EX | equivale a `forward_B` |

### 4.3 Controle MEM/WB

| Sinal | Tipo | Produtor | Consumidor | Observacao |
|---|---|---|---|---|
| `idex_ctrl_wb_sel` | `wbsel_t` | ID | EX/MEM/WB | mux WB: ALU/PC4/LOAD |
| `idex_ctrl_reg_we` | `std_logic` | ID | WB | write enable do RegFile |
| `idex_ctrl_ram_en` | `std_logic` | ID | MEM | enable memoria |
| `idex_ctrl_ram_we` | `std_logic` | ID | MEM | store |
| `idex_ctrl_ram_re` | `std_logic` | ID | MEM | load |
| `idex_ctrl_load_op` | `opexram_t` | ID | MEM/WB | LB/LBU/LH/LHU/LW |

### 4.4 RV32M e store-format

| Sinal | Tipo | Produtor | Consumidor | Observacao |
|---|---|---|---|---|
| `idex_ctrl_is_muldiv` | `std_logic` | ID | EX | habilita mult/div |
| `idex_muldiv_funct3` | `std_logic_vector(2 downto 0)` | ID | EX | operacao M ext |
| `idex_store_funct3` | `std_logic_vector(2 downto 0)` | ID | EX/MEM | usado pelo StoreManager |

Sinais RV32M de controle global (sideband, fora dos registradores de pipeline):

| Sinal | Tipo | Origem | Destino | Observacao |
|---|---|---|---|---|
| `ex_muldiv_start` | `std_logic` | EX | multdiv | pulso de inicio (ex.: borda de `idex_ctrl_is_muldiv`) |
| `ex_muldiv_busy` | `std_logic` | multdiv | hazard/stall unit | while `1`, congela fetch/decode e hold de registradores |
| `ex_muldiv_done` | `std_logic` | multdiv | EX/control | fim da operacao multi-ciclo |
| `pipe_stall_muldiv` | `std_logic` | hazard/stall unit | IF/ID/EX regs | stall dedicado por RV32M |
| `ex_muldiv_result` | `word_t` | multdiv | EX | resultado paralelo a ULA |

### 4.5 Justificativa do contrato ID/EX

- M1 (decode/hazard) produz tudo que M2 (execute/mem/wb) precisa sem olhar `ifid_instr` diretamente.
- Forwarding/hazard ficam viaveis com `idex_rs1_idx`, `idex_rs2_idx`, `idex_rd_idx`.
- RV32M fica desacoplado com `idex_ctrl_is_muldiv` + `idex_muldiv_funct3`.
- Store path fica fechado sem depender de opcode bruto.
- Handshake RV32M (`start/busy/done`) fica explicito para evitar ambiguidade de stall no pipeline de 1 clock.

## 5. Contrato EX/MEM

Sinais que cruzam EX -> MEM:

| Sinal | Tipo | Produtor | Consumidor | Observacao |
|---|---|---|---|---|
| `exmem_valid` | `std_logic` | EX | MEM | bubble control |
| `exmem_pc4` | `word_t` | EX | WB | retorno JAL/JALR |
| `exmem_rd_idx` | `reg_t` | EX | WB | destino final |
| `exmem_alu_result` | `word_t` | EX | MEM/WB | endereco ou resultado ALU |
| `exmem_rs2_fwd_val` | `word_t` | EX | MEM | dado de store (apos forwarding) |
| `exmem_store_wdata` | `word_t` | EX | MEM | saida formatada do StoreManager |
| `exmem_store_mask` | `mask4_t` | EX | MEM | byteena |
| `exmem_ea_lsb` | `std_logic_vector(1 downto 0)` | EX | MEM/WB | alinhamento LB/LH |
| `exmem_ctrl_wb_sel` | `wbsel_t` | EX | WB | mux WB |
| `exmem_ctrl_reg_we` | `std_logic` | EX | WB | write enable |
| `exmem_ctrl_ram_en` | `std_logic` | EX | MEM | ram_en |
| `exmem_ctrl_ram_we` | `std_logic` | EX | MEM | ram_wren |
| `exmem_ctrl_ram_re` | `std_logic` | EX | MEM | ram_rden |
| `exmem_ctrl_load_op` | `opexram_t` | EX | MEM/WB | tipo de load |

Sinais de redirecionamento (nao passam em registrador, mas sao obrigatorios no top-level):

| Sinal | Tipo | Origem | Destino |
|---|---|---|---|
| `ex_branch_taken` | `std_logic` | EX | IF (controle de flush/PC) |
| `ex_branch_target` | `word_t` | EX | IF (novo PC) |

## 6. Contrato MEM/WB

Sinais que cruzam MEM -> WB:

| Sinal | Tipo | Produtor | Consumidor | Observacao |
|---|---|---|---|---|
| `memwb_valid` | `std_logic` | MEM | WB | bubble control |
| `memwb_pc4` | `word_t` | MEM | WB | para `wb_sel="01"` |
| `memwb_rd_idx` | `reg_t` | MEM | WB | rd final |
| `memwb_alu_result` | `word_t` | MEM | WB | para `wb_sel="00"` |
| `memwb_load_data_ext` | `word_t` | MEM | WB | load ja estendido |
| `memwb_ctrl_wb_sel` | `wbsel_t` | MEM | WB | mux final |
| `memwb_ctrl_reg_we` | `std_logic` | MEM | WB | escrita no banco |

## 7. Convenio de reset, stall e flush

- `reset='1'`: limpa registradores e coloca `*_valid <= '0'`.
- `en='0'`: hold do registrador (stall).
- Sinais de stall com nomes alinhados ao diagrama:
  - `if_pc_write_en` (alias `PC_write`)
  - `ifid_write_en` (alias `IFID_write`)
  - `id_bubble_sel` (alias `sel_bubble`)
- `flush='1'`: injeta bubble (`*_valid <= '0'`) e zera controles destrutivos:
  - `*_ctrl_reg_we <= '0'`
  - `*_ctrl_ram_we <= '0'`
  - `*_ctrl_ram_re <= '0'`
  - `*_ctrl_ram_en <= '0'`

## 8. Nomes implementados no repositorio

Nomes efetivamente usados ate agora:

- `pc_fetch`
- `reg_IF_ID`
- `reg_ID_EX`
- `control_unit`
- `bubble_mux`
- `rv32im_pipeline_core`

Observacao: os nomes sugeridos com prefixo `rv32im_pipe_reg_*_top` continuam validos como alias conceitual, mas o codigo implementado usa os nomes acima.

## 9. Estado de integracao atual (abril/2026)

- `rv32im_pipeline_core` ja e o core de pipeline ligado no wrapper de FPGA (`L2IP.vhd`).
- `control_unit` substitui `InstructionDecoder` no caminho de pipeline.
- `bubble_mux` ja esta entre `control_unit` e `reg_ID_EX`.
- `reg_IF_ID` e `reg_ID_EX` estao instanciados no core.
- `reg_EX_MEM` e `reg_MEM_WB` ainda nao foram criados/instanciados.

### 9.1 Interface implementada de reg_ID_EX

Controle:

- `clk`, `reset`, `en`, `flush`, `in_valid`, `idex_valid`

Dados ID -> EX:

- `in_pc`, `in_pc4`, `in_instr`, `in_rs1_idx`, `in_rs2_idx`, `in_rd_idx`, `in_rs1_val`, `in_rs2_val`, `in_imm`
- saem como `idex_pc`, `idex_pc4`, `idex_instr`, `idex_rs1_idx`, `idex_rs2_idx`, `idex_rd_idx`, `idex_rs1_val`, `idex_rs2_val`, `idex_imm`

Controle ID -> EX:

- `in_selMuxPc4ALU`, `in_opExImm`, `in_selMuxALUPc4RAM`, `in_weReg`, `in_opExRAM`, `in_selMuxRS2Imm`, `in_selPCRS1`, `in_opALU`, `in_isMulDiv`, `in_startMul`, `in_weRAM`, `in_reRAM`, `in_eRAM`, `in_opCode`, `in_funct3`
- saem como `idex_selMuxPc4ALU`, `idex_opExImm`, `idex_selMuxALUPc4RAM`, `idex_weReg`, `idex_opExRAM`, `idex_selMuxRS2Imm`, `idex_selPCRS1`, `idex_opALU`, `idex_isMulDiv`, `idex_startMul`, `idex_weRAM`, `idex_reRAM`, `idex_eRAM`, `idex_opCode`, `idex_funct3`

## 10. Checklist rapido para comecar M1/M2 em paralelo

- M1 entrega `ifid_*` e `idex_*` completos (especialmente secao 4).
- M2 assume contrato fixo de `idex_*` e implementa EX/MEM/WB sem ler decoder direto.
- Integracao fecha no `rv32im_pipeline5_top` com sinais sideband de branch (`ex_branch_taken`, `ex_branch_target`).

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../LICENSE).
