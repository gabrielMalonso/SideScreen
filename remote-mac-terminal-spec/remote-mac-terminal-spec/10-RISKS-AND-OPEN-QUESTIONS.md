# 10 — Risks and Open Questions

## Riscos técnicos principais

### 1. API privada de Virtual Display

O SideScreen usa `CGVirtualDisplay` via ponte privada. Isso pode quebrar em versões futuras do macOS.

Mitigação:

- encapsular em `VirtualDisplayService`;
- manter fallback/diagnóstico claro;
- documentar macOS suportado;
- evitar espalhar API privada pelo projeto.

### 2. Input sem root não captura tudo

Sem root, algumas teclas nunca chegarão ao app.

Mitigação:

- UX honesta;
- diagnóstico de teclas;
- Accessibility assist opcional;
- root backend posterior;
- mapeamento configurável.

### 3. Virtual HID no Mac tem atrito de instalação

Karabiner VirtualHID ou DriverKit exigem permissões/system extension.

Mitigação:

- CGEvent fallback;
- onboarding claro;
- detectar estado do backend;
- não bloquear MVP.

### 4. Tailscale pode usar relay/DERP

Conexões relayed podem aumentar latência e reduzir throughput.

Mitigação:

- telemetria de RTT/frame age;
- perfis de qualidade;
- reduzir resolução/FPS em rede ruim;
- instruções de diagnóstico Tailnet.

### 5. Android split tunneling pode excluir o app

Se o app estiver excluído da Tailnet, MagicDNS/IP 100.x pode falhar.

Mitigação:

- mensagens específicas;
- checklist de Tailscale;
- tentativa com IP 100.x;
- documentação de setup.

### 6. Input e vídeo competindo por CPU

Decoder, SurfaceView e captura de input rodam no mesmo tablet.

Mitigação:

- threads dedicadas;
- evitar alocação em hot path;
- vídeo com backpressure;
- input em canal e queue separados.

### 7. Layout de teclado

Layouts físicos e Android key layouts podem divergir.

Mitigação:

- começar com US;
- separar physical key de text commit;
- criar diagnóstico de keyCode/scanCode;
- adicionar layout ABNT2 na Alpha/Beta.

## Perguntas em aberto

### A. Projeto novo ou fork?

Recomendação: fork fortemente refatorado ou novo projeto que importe partes do SideScreen.

Decisão prática depende de quanto histórico/estrutura atual se quer preservar.

### B. Uma porta ou múltiplas portas?

MVP: `port` para vídeo/control legacy e `port+1` para input.

Alpha/final: avaliar single-port multi-channel para simplificar Tailscale/firewall.

### C. CGEvent primeiro ou VirtualHID direto?

Recomendação: CGEvent primeiro para validar input channel. VirtualHID na Alpha.

### D. Karabiner VirtualHID ou DriverKit próprio?

Recomendação: Karabiner VirtualHID primeiro. DriverKit próprio só se o produto justificar custo.

### E. Accessibility entra quando?

Depois do input normal funcionar. Não usar como base do MVP.

### F. Root entra quando?

Depois da Alpha sem root. Primeiro como diagnóstico passivo, depois como backend de input.

### G. QUIC entra quando?

Somente se medições mostrarem que TCP multi-channel não é suficiente.

## Decisões já tomadas nesta spec

1. MVP será sem root.
2. Vídeo do SideScreen será reaproveitado.
3. Tailscale será underlay, não substitui auth do app.
4. Tailnet não deve bindar socket explicitamente em Wi-Fi.
5. Input terá canal dedicado.
6. Protocolo de input será HID-like.
7. CGEvent será fallback/MVP.
8. Virtual HID será backend profissional posterior.
9. Root será backend opcional futuro.

