### Linha 0 → `addi ra, x0, 5` 

* ra = 0 + 5 = **0x00000005**
* **ULA saída:** `0x00000005`

### Linha 4 → `addi sp, x0, 7`

* sp = 0 + 7 = **0x00000007** 
* **ULA saída:** `0x00000007`

### Linha 8 → `add gp, ra, sp` 

* gp = 5 + 7 = **0x0000000C**
* **ULA saída:** `0x0000000C`

### Linha 12 → `sub tp, sp, ra` 

* tp = 7 – 5 = **0x00000002**
* **ULA saída:** `0x00000002`

### Linha 16 → `and t0, ra, sp`

* 5 = `0101₂`, 7 = `0111₂`
* 5 AND 7 = `0101₂` = **0x00000005**
* **ULA saída:** `0x00000005`

### Linha 20 → `or t1, ra, sp`

* 5 OR 7 = `0111₂` = **0x00000007**
* **ULA saída:** `0x00000007`

### Linha 24 → `xor t2, ra, sp`

* 5 XOR 7 = `0010₂` = **0x00000002**
* **ULA saída:** `0x00000002`

### Linha 28 → `sll s0, ra, sp`

* ra = 5 (`0b0101`)
* sp = 7 → shift amount = 7
* 5 << 7 = 640 = **0x00000280**
* **ULA saída:** `0x00000280`

### Linha 32 → `srl s1, s0, sp`

* s0 = 0x280 = 640
* 640 >> 7 = 5 = **0x00000005**
* **ULA saída:** `0x00000005`

### Linha 36 → `slt a0, ra, sp`

* compara ra=5 < sp=7? Verdade → 1
* **ULA saída:** `0x00000001`

### Linha 40 → `addi a1, a1, 1`

* a1 inicial = 0
* a1 = 0 + 1 = **0x00000001**
* **ULA saída:** `0x00000001` (vai continuar incrementando em cada volta do loop)

### Linha 44 → `jal x0, loop`

* Desvia para label `loop` (linha 40)
* **ULA saída:** PC+4 (mas como dest é x0, resultado é descartado)
* **Efeito:** processador entra num **loop infinito** incrementando `a1`.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../LICENSE).
