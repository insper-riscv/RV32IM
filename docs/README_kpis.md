# Scripts de KPI — RV32IM Capstone

Rodar sempre da raiz do repositório (`~/RV32I`).

## Como usar

```bash
# 1. Gerar KPIs da versão atual
python3 scripts/kpi_report.py --output docs/current_2026_1.json

# 2. Comparar com o baseline do grupo anterior
python3 scripts/compare_kpis.py \
  --baseline docs/baseline_2025_2.json \
  --current  docs/current_2026_1.json
```

## O que cada KPI mede

- **KPI 1** — Frequência do clock da CPU
- **KPI 2** — Cobertura de testes cocotb (% de testes passando)
- **KPI 3** — Instruções suportadas (RV32I e RV32M)
- **KPI 4** — Ciclos e tempo de execução do benchmark `full.S`

## Arquivos

```
docs/baseline_2025_2.json  ← NÃO EDITAR — snapshot do grupo anterior
docs/current_2026_1.json   ← gerado pelo kpi_report.py
```

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../LICENSE).
