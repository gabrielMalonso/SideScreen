# ADR-0003 — Usar Tailscale como underlay de rede

## Status

Aceita.

## Contexto

O objetivo é acesso pela internet sem construir NAT traversal próprio. Tailscale já resolve identidade de rede, WireGuard, MagicDNS, IPs 100.x e relay quando necessário.

## Decisão

Usar Tailscale como underlay. O app conecta por MagicDNS ou IP 100.x.

O app não deve depender de APIs internas/CLI Tailscale no MVP.

## Consequências

### Positivas

- Evita expor portas públicas diretamente.
- Evita implementar NAT traversal.
- Facilita uso pessoal com Mac mini em casa.
- MagicDNS melhora UX.

### Negativas

- Usuário precisa instalar/configurar Tailscale.
- Conexões podem cair em DERP/relay e aumentar latência.
- Android split tunneling pode excluir o app.

## Implicação arquitetural

Criar `EndpointMode` e `EndpointResolver`.

Regra crítica:

```text
Em modo Tailnet, não chamar bindSocket em Network Wi-Fi.
```

