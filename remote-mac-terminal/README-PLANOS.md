# Planos de Execução — Remote Mac Terminal

Data: 2026-07-01

Este pacote contém planos técnicos gerados a partir dos specs enviados e organizados para execução eficiente, com paralelismo onde ele realmente reduz tempo sem criar retrabalho.

Direção central: o produto deve substituir, para uso pessoal, Google Remote Desktop/Chrome Remote Desktop ou AnyDesk com uma experiência minimalista. Remote Desktop Mode, capturando telas reais existentes do Mac, vem antes de Extended Display Mode. O modo segundo monitor continua útil, mas não é o eixo do projeto.

## Arquivos principais

| Arquivo | Uso |
|---|---|
| `plano-master-execucao-paralela-2026-07-01.md` | Orquestração geral, dependências, trilhos paralelos e gate de release candidate. |
| `plano-qa-uso-diario-evidencias-2026-07-01.md` | Execução de QA real: sessões 30 min USB/Tailnet, input hardware, logs e evidências. |
| `plano-input-virtualhid-hardware-2026-07-01.md` | Validação e hardening de input real, VirtualHID e fallback CGEvent. |
| `plano-seguranca-revogacao-sessao-ativa-2026-07-01.md` | Revogação/reset em sessão ativa, input sem auth, release-all e logs seguros. |
| `plano-release-permissoes-distribuicao-2026-07-01.md` | Assinatura, permissões macOS, notarização, Android release signing e smoke pós-release. |

Cada Markdown segue o template técnico anexado. Cada HTML é o painel visual de aprovação correspondente.

## Ordem sugerida de leitura

1. Comece pelo plano master.
2. Aprove os trilhos que deseja executar agora.
3. Use os HTMLs como painel de aprovação humana.
4. Use os Markdown como fonte da verdade para execução.

## Estratégia resumida

```text
Baseline obrigatório
  ├─ Remote Desktop Mode em tela real
  ├─ QA longa USB/Tailnet
  ├─ Input real + VirtualHID
  ├─ Segurança/revogação
  └─ Release/permissões
        ↓
Consolidação cirúrgica
        ↓
Release candidate interno
        ↓
Decisões condicionais: root, QUIC, DriverKit próprio
```

A decisão forte do pacote: não gastar energia com root/QUIC/DriverKit próprio antes de fechar os gates de uso diário em tela real do Mac.
