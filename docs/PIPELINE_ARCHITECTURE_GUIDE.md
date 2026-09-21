# Guia de Arquitetura do Pipeline RV32IM - 5 Estágios

## Visão Geral

O pipeline é composto por **5 estágios** que processam instrções em paralelo:

```
IF (Instruction Fetch)
  ↓ [reg_IF_ID] + HDU + Bubble Mux
ID (Instruction Decode)
  ↓ [reg_ID_EX] + Forwarding Unit
EX (Execute)
  ↓ [reg_EX_MEM]
MEM (Memory)
  ↓ [reg_MEM_WB]
WB (Write Back)
```

---

## Arquivos Principais e Seu Uso

### 1. **rv32im_pipeline_core.vhd** (TOP-LEVEL DO PIPELINE)

**O arquivo principal.** Todas as outras unidades são instanciadas aqui.

**Responsabilidades:**
- Instancia e conecta todos os 5 estágios
- Gerencia os registradores de pipeline (reg_IF_ID, reg_ID_EX, reg_EX_MEM, reg_MEM_WB)
- Aplica controles de hazard (flush, stall, válidas)
- Conecta sinais de forwarding, branch, JALR
- Interface com ROM (leitura de instruções) e RAM (dados)

**Saídas para TOP-LEVEL (FPGA):**
- ROM: `rom_addr`, `rom_rden`, `rom_data` (lê instruções)
- RAM: `ram_addr`, `ram_wdata`, `ram_rdata`, `ram_en`, `ram_wren`, `ram_rden`, `ram_byteena`

**Quando usar:**
- ✅ Integração principal do processador
- ✅ Debug do pipeline completo
- ✅ Testes de instrções com verificação de estado

---

### 2. **rv32im_pipeline_fpga_top.vhd** (TOP-LEVEL DA FPGA)

**Wrapper da FPGA.** Conecta o core do pipeline com a placa.

**Responsabilidades:**
- Instancia `rv32im_pipeline_core`
- Instancia ROM IP (Quartus) via `room.vhd`
- Instancia RAM IP (Quartus) via `ram1port.vhd`
- Conecta relógio, reset e LEDs de debug
- Inverte clock da ROM (ROM síncrona) para que o dado esteja pronto quando o core captura IF/ID

**Quando usar:**
- ✅ Síntese na FPGA (Quartus)
- ✅ Testes em hardware de verdade

---

## Estágios e Registradores de Pipeline

### **Estágio IF (Instruction Fetch)**

**Arquivo:** `pc_fetch.vhd`

**O que faz:**
- Incrementa PC (PC = PC + 4)
- Envia endereço para ROM
- Gera sinal de read enable (`rom_rden`)

**Saídas para reg_IF_ID:**
- `pc` (endereço da instrução)
- `pc4` (próximo PC)
- `rom_data` (instrução da ROM)

---

### **Registrador IF/ID** → `reg_IF_ID.vhd`

**O que faz:**
- Captura instrução, PC e PC+4 no final de cada ciclo
- Marca instrução como "válida" (`ifid_valid`)
- **Hazard Control:** Respeita sinais de controle:
  - `reset` → injeta NOP (bolha)
  - `flush` → injeta NOP (branch tomado)
  - `ifid_write_en = '0'` → stall (congela)
  - `ifid_write_en = '1'` → captura normalmente

**Saídas:**
- `ifid_valid`, `ifid_pc`, `ifid_pc4`, `ifid_instr`

---

### **Estágio ID (Instruction Decode)**

**Arquivos:** 
- `control_unit.vhd` (decodifica opcode e gera sinais de controle)
- `InstructionDecoder.vhd` (extrai campos rs1, rs2, rd, imm)
- `RegFile.vhd` (lê valores dos registradores)

**O que faz:**
1. Decodifica a instrução (campos rs1, rs2, rd, tipo de imediato)
2. Lê valores de rs1 e rs2 no banco de registradores
3. Gera sinais de controle (ALU op, select muxes, etc.)
4. **Suporta bypass interno:** Lê escrita que está acontecendo **no mesmo ciclo** (WB)

**Saídas para reg_ID_EX:**
- Valores: `rs1_val`, `rs2_val`, `imm`, índices `rs1_idx`, `rs2_idx`, `rd_idx`
- Controles: `opALU`, `weReg`, `weRAM`, `opExRAM`, etc.

---

### **Hazard Detection Unit (HDU)** → `hazard_detection_unit.vhd`

**O que faz:**
- **Detecta load-use hazard:** Se a instrução anterior é um LOAD e rs1/rs2 dessa instrução é o rd do LOAD
- Gera sinais de controle:
  - `if_pc_write_en = '0'` → stall no IF
  - `ifid_write_en = '0'` → stall no IF/ID
  - `id_bubble_sel = '1'` → injeta NOP no ID/EX via Bubble Mux

**Usa:**
- `ifid_valid`, `ifid_opcode` (sabe se instrução anterior é LOAD)
- `rs1_idx`, `rs2_idx` (instruções atuais)
- `idex_rd_idx`, `idex_reRAM`, `idex_valid` (instrução no EX)

---

### **Bubble Mux** → `bubble_mux.vhd`

**O que faz:**
- Zeroa apenas sinais que causam efeito colateral:
  - `weReg` (escrita em registrador)
  - `weRAM`, `reRAM`, `eRAM` (acesso a RAM)
  - `startMul` (início de multiplicação/divisão)

**Entrada:** `sel_bubble` (vem da HDU)
- `sel_bubble = '0'` → passa sinais normalmente
- `sel_bubble = '1'` → todos para `'0'` (NOP)

---

### **Registrador ID/EX** → `reg_ID_EX.vhd`

**O que faz:**
- Captura todos os dados e controles do estágio ID
- Marca como válido (`idex_valid`)
- **Suporta flush:** Se houver branch tomado, injeta NOP

**Saídas:**
- Dados: `idex_pc`, `idex_pc4`, `idex_rs1_val`, `idex_rs2_val`, `idex_imm`, índices, opcode, funct3
- Controles: `idex_weReg`, `idex_weRAM`, `idex_opALU`, `idex_opExRAM`, `idex_selMuxALUPc4RAM`

---

### **Estágio EX (Execute)**

**Arquivos:**
- `ALU.vhd` (operações aritméticas/lógicas)
- `multdiv.vhd` (multiplicação/divisão)
- `StoreManager.vhd` (máscara de bytes para STORE)

**O que faz:**
1. Realiza operação ALU ou multi/div
2. Calcula e compara para branch (`beq`, `bne`, `blt`, etc.)
3. Calcula JALR target
4. **Forwarding Unit:** Injeta resultados de EX/MEM ou MEM/WB para rs1/rs2 (evita stall)
5. Prepara máscara de bytes para STORE

**Saídas para reg_EX_MEM:**
- `alu_out` (resultado da ALU)
- `pc4` (para futuros JAL/JALR)
- `rs2_val` ou versão propagada (para dados de store)
- `rd_idx`, controles de WB, controles de RAM

---

### **Forwarding Unit** → `forwarding_unit.vhd`

**O que faz:**
- **Prioridade:** EX/MEM > MEM/WB
- Detecta quando rs1 ou rs2 **deve ser substituído** por resultado anterior
- **Proteção:** Não encaminha para rd = x0 (leitura de x0 sempre = 0)
- **Proteção:** Respeita `valid` das instruções anteriores

**Entrada:**
- `idex_rs1_idx`, `idex_rs2_idx` (registradores atuais)
- `exmem_rd_idx`, `exmem_weReg`, `exmem_valid` (instrução em EX/MEM)
- `memwb_rd_idx`, `memwb_weReg`, `memwb_valid` (instrução em MEM/WB)

**Saída:**
- `rs1_fwd_sel`, `rs2_fwd_sel` (seletores: 2'b00=normal, 2'b01=EX/MEM, 2'b10=MEM/WB)

**Uso:** Muxes no EX selecionam rs1/rs2 baseado em `rs*_fwd_sel`

---

### **Registrador EX/MEM** → `reg_EX_MEM.vhd`

**O que faz:**
- Captura resultados do EX (ALU, RS2 para store, índices)
- Captura sinais de controle para MEM/WB
- Marca como válido (`exmem_valid`)

**Saídas:**
- ALU: `exmem_alu_out`
- Store: `exmem_rs2_val`, `exmem_bytemask`
- Metadados: `exmem_pc4`, `exmem_rd_idx`
- Controles: `exmem_weReg`, `exmem_weRAM`, `exmem_reRAM`, `exmem_eRAM`, `exmem_opExRAM`

---

### **Estágio MEM (Memory)**

**Arquivos:**
- `StoreManager.vhd` (já em EX, mas máscara chega aqui)
- Interface com RAM (lógica combinacional)

**O que faz:**
1. Acessa RAM: leitura (`reRAM`) ou escrita (`weRAM`)
2. Endereço vem de `exmem_alu_out`
3. Dados de escrita vem de `exmem_rs2_val` com máscara `exmem_bytemask`
4. Leitura é **síncrona** (1 ciclo de latência) → dado chega em WB

**Saídas para reg_MEM_WB:**
- `ram_rdata` (será processado em WB)
- Metadados: `pc4`, `alu_out`, `rd_idx`, `weReg`, `opExRAM`

---

### **Registrador MEM/WB** → `reg_MEM_WB.vhd`

**O que faz:**
- Captura metadados de MEM (não captura `ram_rdata` porque RAM é síncrona)
- Marca como válido (`memwb_valid`)

**Saídas:**
- `memwb_pc4`, `memwb_alu_out`, `memwb_rd_idx`
- Controles: `memwb_weReg`, `memwb_opExRAM`, `memwb_selMuxALUPc4RAM`

---

### **Estágio WB (Write Back)**

**Arquivos:**
- `ExtenderRAM.vhd` (extende dado de RAM conforme tipo de load: LW, LH, LB, LHU, LBU)
- Mux final de WB (combinacional)

**O que faz:**
1. **ExtenderRAM:** Recebe `ram_rdata` e `opExRAM` (tipo de load)
   - LW (opExRAM = "000") → retorna palavra inteira
   - LH (opExRAM = "001") → half-word com extensão de sinal
   - LB (opExRAM = "010") → byte com extensão de sinal
   - LHU (opExRAM = "011") → half-word sem sinal
   - LBU (opExRAM = "100") → byte sem sinal

2. **Mux final:** Seleciona qual valor escrever em RegFile:
   - `selMuxALUPc4RAM = "00"` → `alu_out` (R-type, I-type ALU, AUIPC, LUI)
   - `selMuxALUPc4RAM = "01"` → `pc4` (JAL, JALR)
   - `selMuxALUPc4RAM = "10"` → resultado do ExtenderRAM (LOAD)

3. **RegFile:** Escreve em `memwb_rd_idx` com `memwb_weReg` (se válido)

---

## Fluxo de Dados e Sinais de Controle

### **Ciclo Normal (sem hazards):**

```
IF: rom_data[31:0] → reg_IF_ID
ID: instr decodificada → controles → reg_ID_EX
EX: ALU(rs1, rs2 ou imm) → reg_EX_MEM (+ forwarding injeta valores corretos)
MEM: RAM[addr] ou rs2 → reg_MEM_WB
WB: Mux seleciona valor → RegFile (escrita em rd)
```

### **Load-Use Hazard (LOAD seguido de USO do mesmo registrador):**

```
Ciclo 1: LW rd, offset(rs1)
  ├─ IF: LW → IF/ID
  └─ ID: Decodifica, rs1_idx extraído

Ciclo 2: ADD r3, rd, r2
  ├─ IF: ADD → IF/ID
  ├─ ID: ADD → HDU detecta load-use (rd do LW == rs1 do ADD)
  │   └─ HDU sinaliza: if_pc_write_en = '0', ifid_write_en = '0', id_bubble_sel = '1'
  ├─ EX: LW em EX, dado ainda não disponível → Bubble Mux zeroa weReg do ADD
  └─ Resultado: IF/ID congela, ADD vira NOP

Ciclo 3: ADD reexecutado
  ├─ IF: Próxima instrução
  ├─ ID: ADD novamente (não foi avançado)
  ├─ EX: ALU(rs1, rs2) → Forwarding não precisa (dado já está em RegFile depois do ciclo anterior)
  └─ Resultado: ADD executado corretamente
```

### **Forwarding (EX/MEM → EX):**

```
Ciclo 1: ADD r1, r2, r3    → resultado em EX/MEM no fim do ciclo
Ciclo 2: SUB r4, r1, r5
  ├─ Forwarding Unit: detecta r1 = rd do ADD
  ├─ Mux em EX: substitui rs1 (subitamente) pelo resultado do ADD
  └─ Resultado: SUB usa valor correto do ADD **no mesmo ciclo**
```

### **Branch/JALR (Flush):**

```
Ciclo N: BEQ r1, r2, target
  ├─ EX: Comparação indica branch tomado
  ├─ Branch Unit: calcula target
  ├─ pc_src seleciona novo PC
  ├─ reg_IF_ID e reg_ID_EX recebem flush = '1'
  └─ Resultado: IF/ID e ID/EX viram NOPs, próximo ciclo if_pc = target
```

---

## Sinais Críticos de Controle

| Sinal | Origem | Destino | Função |
|-------|--------|---------|--------|
| `if_pc_write_en` | HDU | pc_fetch | '0' = stall no PC |
| `ifid_write_en` | HDU | reg_IF_ID | '0' = stall no IF/ID |
| `id_bubble_sel` | HDU | bubble_mux | '1' = zeroa weReg/weRAM/etc |
| `flush_if_id` | Branch/JALR | reg_IF_ID | '1' = injeta NOP |
| `flush_id_ex` | Branch/JALR | reg_ID_EX | '1' = injeta NOP |
| `ifid_valid` | reg_IF_ID | HDU, Forwarding | '0' = instruç não válida (bolha) |
| `idex_valid` | reg_ID_EX | Forwarding, MEM | '0' = instruç não válida |
| `exmem_valid` | reg_EX_MEM | Forwarding, Bubble | '0' = instruç não válida |
| `memwb_valid` | reg_MEM_WB | Forwarding, WB | '0' = instruç não válida |
| `rs1_fwd_sel` | Forwarding | Mux EX | Seleciona fonte de rs1 |
| `rs2_fwd_sel` | Forwarding | Mux EX | Seleciona fonte de rs2 |

---

## Arquivos Auxiliares (Não são estágios, mas são essenciais)

### **control_unit.vhd**
Decodifica opcode e retorna: opALU, weReg, weRAM, reRAM, opExRAM, selMuxes, etc.

### **RegFile.vhd**
Banco de 32 registradores com:
- 2 leituras: rs1, rs2
- 1 escrita: rd
- **Bypass interno WB→ID:** permite ler escrita do ciclo atual

### **ALU.vhd**
Realiza operações: ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, LT, LTU, EQ

### **multdiv.vhd**
Multiplicador e divisor. Sintetizados via IPs Quartus (mult.qip, div.qip, divu.qip)

### **StoreManager.vhd**
Calcula máscara de bytes (byte_ena) para STORE (SB, SH, SW)

### **ExtenderRAM.vhd**
Estende dados de RAM conforme tipo de LOAD (sinal ou sem sinal)

### **InstructionDecoder.vhd**
Extrai campos da instrução: rs1, rs2, rd, tipos de imediato (I, S, B, U, J)

### **ExtenderImm.vhd**
Calcula valor do imediato conforme tipo

---

## Fluxo de Implementação (Onde usar cada arquivo)

### **Projeto Quartus (FPGA):**
1. Top-level: `rv32im_pipeline_fpga_top.vhd`
2. Core: `rv32im_pipeline_core.vhd`
3. Todos os arquivos do `src/` (estágios, unidades, etc.)
4. ROMs/RAMs IPs: `room.vhd`, `ram1port.vhd`

### **Testes (Cocotb + GHDL):**
1. Para testar um módulo isolado: use como top-level em `tests.json`
2. Para testar pipeline completo: use `rv32im_pipeline_core` como top-level
3. Precisará de simulações da ROM e RAM: veja `ROM_simulation.vhd`, `RAM_simulation.vhd`

### **Debug e Análise:**
1. Abrir `rv32im_pipeline_core.vhd` para entender fluxo geral
2. Verificar `reg_*_*.vhd` para entender validades e controles
3. Verificar `forwarding_unit.vhd` se há problema com valores incorretos
4. Verificar `hazard_detection_unit.vhd` se há stalls indesejados

---

## Checklist de Integração

- ✅ Todos os 5 estágios instanciados em `rv32im_pipeline_core.vhd`?
- ✅ Registradores de pipeline capturando `valid` e respeitando flush/stall?
- ✅ HDU alimentada com `ifid_valid`, `ifid_opcode`, `idex_reRAM`, `idex_rd_idx`?
- ✅ Bubble Mux conectado corretamente entre Control Unit e reg_ID_EX?
- ✅ Forwarding Unit recebendo `*_valid` de todos os registradores?
- ✅ Muxes em EX respeitando `rs1_fwd_sel` e `rs2_fwd_sel`?
- ✅ Branch/JALR controlando `flush_if_id` e `flush_id_ex`?
- ✅ RegFile escrevendo apenas se `memwb_weReg = '1'` e `memwb_valid = '1'`?
- ✅ ExtenderRAM em WB recebendo `ram_rdata` e `memwb_opExRAM`?
- ✅ Mux final de WB selecionando corretamente via `memwb_selMuxALUPc4RAM`?

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../LICENSE).
