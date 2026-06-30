# ADR-0001 — Começar sem root

## Status

Aceita.

## Contexto

O objetivo final é chegar o mais próximo possível de um terminal remoto real para Mac. Root no Android permitiria capturar input em camada muito mais baixa, mas aumenta drasticamente complexidade, risco, segurança e dificuldade de distribuição.

## Decisão

A primeira implementação será sem root.

O app deve ser desenhado com abstração de backends de input para permitir root futuramente, mas nenhuma funcionalidade crítica do MVP dependerá de root.

## Consequências

### Positivas

- Desenvolvimento inicial mais rápido.
- Menos risco operacional.
- Valida vídeo, Tailnet, sessão e input básico.
- Mantém caminho para distribuição normal.
- Evita misturar problema de produto com problema de root.

### Negativas

- Algumas teclas de sistema não serão capturáveis.
- Meta/Super/Home podem continuar problemáticos.
- Experiência não será 100% terminal na primeira fase.

## Implicação arquitetural

Criar:

```text
InputCaptureBackend
  ActivityKeyboardBackend
  PointerCaptureBackend
  AccessibilityAssistBackend futuro
  RootEvdevBackend futuro
```

