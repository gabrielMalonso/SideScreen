# 10 — Risks and Resolved Questions

## Riscos técnicos principais

### 1. Produto escorregar de volta para "segundo monitor"

A base SideScreen puxa o projeto naturalmente para Virtual Display. Isso não basta para substituir Google Remote Desktop/AnyDesk no uso pessoal.

Mitigação:

- ADR-0007 define Remote Desktop Mode como principal;
- criar `DisplaySource`;
- QA de uso diário só aprova o produto principal quando uma tela real existente é controlada;
- manter Extended Display Mode como opção secundária explícita.

### 2. API privada de Virtual Display

O SideScreen usa `CGVirtualDisplay` via ponte privada. Isso pode quebrar em versões futuras do macOS.

Mitigação:

- encapsular em `VirtualDisplaySource`;
- manter fallback/diagnóstico claro;
- documentar macOS suportado;
- evitar espalhar API privada pelo projeto.

### 3. Input sem root não captura tudo

Sem root, algumas teclas nunca chegarão ao app.

Mitigação:

- UX honesta;
- diagnóstico de teclas;
- Accessibility assist opcional;
- root backend posterior;
- mapeamento configurável.

### 4. Virtual HID no Mac tem atrito de instalação

Karabiner VirtualHID ou DriverKit exigem permissões/system extension.

Mitigação:

- CGEvent fallback;
- onboarding claro;
- detectar estado do backend;
- não bloquear MVP.

### 5. Tailscale pode usar relay/DERP

Conexões relayed podem aumentar latência e reduzir throughput.

Mitigação:

- telemetria de RTT/frame age;
- perfis de qualidade;
- reduzir resolução/FPS em rede ruim;
- instruções de diagnóstico Tailnet.

### 6. Android split tunneling pode excluir o app

Se o app estiver excluído da Tailnet, MagicDNS/IP 100.x pode falhar.

Mitigação:

- mensagens específicas;
- checklist de Tailscale;
- tentativa com IP 100.x;
- documentação de setup.

### 7. Input e vídeo competindo por CPU

Decoder, SurfaceView e captura de input rodam no mesmo tablet.

Mitigação:

- threads dedicadas;
- evitar alocação em hot path;
- vídeo com backpressure;
- input em canal e queue separados.

### 8. Layout de teclado

Layouts físicos e Android key layouts podem divergir.

Mitigação:

- começar com US;
- separar physical key de text commit;
- criar diagnóstico de keyCode/scanCode;
- adicionar layout ABNT2 na Alpha/Beta.

## Perguntas resolvidas ou condicionais

### A. Projeto novo ou fork?

Decisão: manter um fork fortemente refatorado enquanto o motor de vídeo do SideScreen continuar sendo reaproveitado.

Novo projeto só vale se a estrutura herdada começar a atrapalhar mais do que ajuda. Hoje não atrapalha o bastante.

### B. Uma porta ou múltiplas portas?

Decisão MVP: `port` para vídeo/control legacy e `port+1` para input.

Alpha/final: avaliar single-port multi-channel para simplificar Tailscale/firewall.

### C. CGEvent primeiro ou VirtualHID direto?

Decisão: CGEvent fica como fallback e VirtualHID vira backend preferencial quando estiver pronto no Mac.

### D. Karabiner VirtualHID ou DriverKit próprio?

Decisão: Karabiner VirtualHID primeiro, com helper privilegiado do SideScreen quando necessário. DriverKit próprio só entra se o produto justificar o custo.

### E. Accessibility entra quando?

Decisão: Accessibility é assist opcional. Não é base do MVP e não substitui pointer capture/Activity.

### F. Root entra quando?

Decisão: depois da Alpha sem root. Primeiro como diagnóstico passivo, depois como backend de input.

### G. QUIC entra quando?

Decisão: somente se medições mostrarem que TCP multi-channel não é suficiente.

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
10. Remote Desktop Mode com tela real é o produto principal; Virtual Display é modo secundário.
