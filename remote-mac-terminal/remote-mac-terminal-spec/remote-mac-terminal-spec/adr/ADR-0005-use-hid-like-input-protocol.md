# ADR-0005 — Usar protocolo de input HID-like

## Status

Aceita.

## Contexto

Enviar `Android KeyEvent` diretamente ao Mac seria simples, mas não é correto arquiteturalmente. `KeyEvent` é pós-framework e não preserva totalmente intenção física.

## Decisão

O protocolo remoto deve ser HID-like.

Eventos devem representar teclas físicas, modificadores, mouse relativo, botões, wheel e touch separadamente.

## Consequências

### Positivas

- Fica independente do Android.
- Prepara integração com Virtual HID no Mac.
- Permite root backend futuro sem mudar protocolo.
- Melhora mapeamento de teclado/mouse.

### Negativas

- Mais trabalho inicial.
- Exige tabelas de mapping.
- Layouts complexos exigem tratamento posterior.

## Implicação arquitetural

Eventos principais:

```text
KeyboardKey
TextCommit
PointerRelative
PointerButton
PointerWheel
PointerAbsolute
AllInputsUp
```

