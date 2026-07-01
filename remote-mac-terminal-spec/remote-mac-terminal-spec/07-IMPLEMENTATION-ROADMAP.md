# 07 — Implementation Roadmap

## Estratégia geral

A ordem de implementação deve reduzir risco.

Não atacar root, DriverKit próprio ou QUIC primeiro. Validar o produto com o menor número de variáveis novas.

```text
MVP:
  Tailnet + vídeo existente + input separado simples

Alpha:
  HID-like protocol + VirtualHID prático + sessão melhor

Beta:
  diagnóstico, rede real, Accessibility assist, root discovery

Final:
  produto robusto, installer, segurança, modo root opcional
```

## MVP — Tailnet + input dedicado sem root

### Objetivo

Provar que o tablet Android pode ser usado remotamente como terminal do Mac mini via Tailscale, sem root.

### Escopo

#### Rede

- Adicionar modo Tailnet no Mac e Android.
- QR deve aceitar `mode=tailnet`.
- Permitir MagicDNS e IP 100.x.
- Remover bind forçado em Wi-Fi no Android quando `mode=tailnet`.
- Manter LAN e USB funcionando.

#### Vídeo

- Reaproveitar pipeline atual do SideScreen.
- Não trocar ScreenCapture/VideoToolbox/MediaCodec.
- Apenas ajustar endpoints e reconexão se necessário.

#### Input

- Criar canal TCP separado para input.
- Android captura teclado comum via Activity.
- Android captura mouse via pointer capture/generic motion.
- Mac injeta via CGEvent fallback.
- Implementar fail-safe de soltar teclas/botões.

#### Diagnóstico

- Mostrar RTT.
- Mostrar codec.
- Mostrar host conectado.
- Logar eventos de input principais.
- Logar quando pointer capture está ativo/inativo.

### Entregáveis

- `EndpointMode` e parser de QR atualizado.
- `InputClient` Android.
- `InputServer` Mac.
- `CGEventKeyboardMouseBackend` inicial.
- Configuração de Tailnet host.
- Testes manuais documentados.

### Critérios de aceite

- Conectar fora da LAN via Tailscale.
- Teclado básico funciona.
- Mouse relativo funciona.
- Input continua responsivo com vídeo ativo.
- Disconnect não deixa Command/Shift/mouse preso.
- LAN/USB não regrediram.

## Alpha — arquitetura de input profissional

### Objetivo

Transformar o input de protótipo em subsistema confiável.

### Escopo

#### Protocolo

- Criar Remote Input Protocol v1.
- Usar sequence numbers.
- Usar timestamps monotônicos.
- Diferenciar keyboard, pointer, wheel, touch, all-inputs-up.
- Mapear para HID usages quando possível.

#### Mac

- Criar `InputIngress` formal.
- Criar estado de teclas/botões.
- Criar coalescing seguro de mouse move.
- Integrar Karabiner VirtualHID como backend principal.
- Manter CGEvent fallback selecionável.

#### Android

- Separar `InputCapture` da Activity.
- Criar backends independentes.
- Adicionar configuração de modifier mapping.
- Melhorar pointer capture.
- Enviar `AllInputsUp` quando app perde foco.

#### Sessão

- Começar a separar device pairing de session auth.
- Armazenar deviceId.
- Preparar HMAC/nonce por sessão.

### Critérios de aceite

- Hotkeys comuns do Mac funcionam quando Android entrega eventos.
- Virtual HID funciona em apps que exigem input físico comum.
- CGEvent fallback pode ser ativado.
- Teclas presas são tratadas automaticamente.
- Layout US funcional.
- ABNT2 documentado/testado parcialmente.

## Beta — robustez em rede real e modo assistido

### Objetivo

Tornar o sistema utilizável diariamente e preparar root.

### Escopo

#### Rede

- Diagnóstico melhor para MagicDNS/IP 100.x.
- Mensagens de erro específicas.
- Detecção heurística de conexão ruim.
- Bitrate/resolução/FPS ajustáveis por perfil.
- Investigar single-port multi-channel.

#### Input

- Accessibility assist opcional.
- Tela de diagnóstico de teclas capturadas/perdidas.
- Root discovery passivo: listar dispositivos e capabilities.
- Melhorar mapeamento de teclado.

#### Segurança

- Revogação por dispositivo.
- Chave por dispositivo.
- Pairing temporário.
- Logs sem vazamento de token.

#### UX

- Onboarding Tailnet.
- Tela “por que algumas teclas não funcionam sem root”.
- Perfis: Productivity, Low-latency, Low-bandwidth.

Estado implementado sem root:

- Mac Settings tem seletor de perfil Manual/Productivity/Low latency/Low bandwidth.
- Os perfis aplicam resolução, FPS, bitrate, qualidade e HiDPI de forma conjunta.
- Ajustes manuais voltam o perfil para Manual.
- Mudanças de resolução/FPS/HiDPI com servidor rodando reiniciam o pipeline com debounce.
- Android Wireless Diagnostics mostra endpoint, rota, input, limitação sem root e últimos erros relevantes do log local.
- Android Wireless Diagnostics mostra contadores de teclas capturadas, unsupported, assistidas por Accessibility e duplicatas filtradas.
- Android Wireless Diagnostics mostra transporte ativo da rota, validação e alerta quando Tailnet está sem VPN/Tailscale ativa para o app.
- Mac Settings mostra diagnóstico de host Tailnet no card de QR.
- Android Settings permite configurar Meta/Super como Command, Option, Control ou Off.

### Critérios de aceite

- Usável por horas sem stuck keys.
- Reconnect confiável.
- Diagnóstico ajuda a resolver falhas comuns.
- Accessibility é opcional e claramente explicado.
- Root ainda não é obrigatório.

## Versão final — produto consistente

### Objetivo

Consolidar arquitetura, instalação e modos avançados.

### Escopo

#### Mac

- Decidir entre Karabiner VirtualHID permanente ou DriverKit próprio.
- Criar installer/permission flow.
- Melhorar serviço de background.
- Endurecer segurança de sessão.

#### Android

- Modo normal.
- Modo assistido.
- Modo root Pro.
- Escape seguro para root/grab.
- Configurações avançadas de teclado/mouse.

Estado implementado sem root:

- Configuração de Meta/Super para Command, Option, Control ou Off.
- Sensibilidade de pointer configurável.
- Sensibilidade de scroll configurável.
- Natural scroll configurável.
- `TextCommit` para IME/dead keys via `InputConnection`, sem logar texto digitado.
- `AllInputsUp` com motivo específico.
- Latência de input com último RTT, média e p95.
- Captura de teclado/mouse sem root separada em classes dedicadas no Android.

#### Transporte

- Manter TCP multi-channel se suficiente.
- Migrar para QUIC apenas se medições justificarem.
- Otimizar reconexão e resume.

#### Extras opcionais

- Clipboard.
- Áudio.
- Multi-monitor.
- File drop.
- Wake-on-LAN/Tailscale SSH helper.

### Critérios de aceite

- Experiência sem root boa para uso real.
- Modo root melhora fidelidade sem comprometer segurança.
- Instalação Mac compreensível.
- Diagnóstico operacional completo.
- Arquitetura suportável a longo prazo.

## Sequência detalhada recomendada

### Sprint 1 — Tailnet MVP

1. Adicionar `EndpointMode` ao modelo de conexão.
2. Atualizar `PairingURL` Mac e Android para aceitar `mode`.
3. Adicionar campo de Tailnet host nas settings Mac.
4. Adicionar UI Android para mostrar host escaneado.
5. Em `connectWireless`, condicionar `bindSocket` a modo LAN.
6. Testar MagicDNS.
7. Testar IP 100.x.
8. Confirmar que LAN antigo ainda funciona.

### Sprint 2 — Input channel simples

1. Criar `InputServer` Mac em `port+1`.
2. Criar `InputClient` Android.
3. Criar mensagem `KeyboardKey` mínima.
4. Criar mensagem `PointerRelative` mínima.
5. Criar mensagem `PointerButton` mínima.
6. Criar mensagem `PointerWheel` mínima.
7. Injetar no Mac via CGEvent.
8. Implementar release-all em disconnect.

### Sprint 3 — Pointer capture e UX

1. Solicitar pointer capture ao entrar em modo remoto.
2. Mostrar estado de pointer capture.
3. Implementar escape local para soltar capture.
4. Melhorar mouse buttons.
5. Implementar scroll horizontal se disponível.
6. Testar com mouse Bluetooth real.

### Sprint 4 — Protocolo HID-like

1. Adicionar sequence/timestamp.
2. Adicionar deviceId.
3. Mapear HID usages básicos.
4. Separar TextCommit de KeyboardKey.
5. Adicionar coalescing seguro de mouse.
6. Adicionar métricas de input latency.

### Sprint 5 — VirtualHID

1. Investigar versão/instalação do Karabiner VirtualHID.
2. Criar backend abstrato no Mac.
3. Implementar CGEventBackend como fallback formal.
4. Implementar KarabinerVirtualHIDBackend.
5. Testar em Terminal, Finder, browser e editor.
6. Documentar permissões e onboarding.

### Sprint 6 — Segurança e sessão

1. Introduzir deviceId persistente no Android.
2. Registrar dispositivos no Mac.
3. Revogar dispositivo.
4. Separar pairing token de session token.
5. Introduzir nonce/HMAC por sessão.
6. Remover logs sensíveis.

### Sprint 7 — Root discovery opcional

1. Criar build/dev flag para root.
2. Listar `/dev/input/event*` com root.
3. Mostrar eventos crus em tela de diagnóstico.
4. Comparar com Activity backend.
5. Não substituir backend ainda.
