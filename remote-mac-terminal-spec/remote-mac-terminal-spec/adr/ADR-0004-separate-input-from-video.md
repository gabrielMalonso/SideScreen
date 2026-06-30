# ADR-0004 — Separar input do vídeo

## Status

Aceita.

## Contexto

O SideScreen atual envia vídeo, touch, ping e controle pelo mesmo socket TCP. Isso funciona em LAN/USB, mas input pode ficar atrás de frames grandes em internet.

## Decisão

Input terá canal dedicado.

MVP: socket TCP separado.  
Alpha/final: avaliar single-port multi-channel ou QUIC.

## Consequências

### Positivas

- Input não sofre head-of-line blocking por frames grandes.
- Facilita priorização.
- Facilita debug e métricas.
- Permite evoluir input sem tocar no vídeo.

### Negativas

- Mais complexidade de sessão.
- Mais um canal para autenticar/reconectar.
- MVP pode precisar de porta adicional.

## Implicação arquitetural

Criar:

```text
InputClient
InputServer
InputIngress
InputBackend
```

