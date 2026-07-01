# 08 — Codex Task Backlog

Este backlog é organizado para execução incremental no Codex. Cada tarefa tem objetivo, escopo e critérios de aceite. Não implementar tudo de uma vez.

## Epic 1 — Tailnet endpoint support

### Task 1.1 — Introduzir modelo de EndpointMode

Objetivo: remover a suposição de que wireless significa LAN.

Escopo:

- Criar enum/modelo para `usb`, `lan`, `tailnet`, `manual`.
- Persistir modo escolhido.
- Garantir que QR antigo sem modo ainda funcione.

Critérios de aceite:

- Android consegue parsear QR antigo.
- Android consegue parsear QR com `mode=tailnet`.
- Mac consegue gerar QR para LAN e Tailnet.

### Task 1.2 — Refatorar geração de QR no Mac

Objetivo: substituir uso direto de `LANAddressResolver.primaryIPv4()` como única fonte.

Escopo:

- Criar `EndpointAdvertiser` ou equivalente.
- Para LAN, usar `LANAddressResolver`.
- Para Tailnet, usar host configurado pelo usuário.
- Incluir `mode` na URL.

Critérios de aceite:

- QR LAN mostra IP LAN.
- QR Tailnet mostra MagicDNS/IP 100.x.
- Reset de auth continua funcionando.

### Task 1.3 — Android não bindar Wi-Fi em Tailnet

Objetivo: permitir que Tailscale VPN roteie o socket.

Escopo:

- Passar `EndpointMode` até `StreamClient.connectWireless`.
- Se modo Tailnet, não chamar `Network.bindSocket`.
- Se modo LAN, manter workaround Wi-Fi opcional.

Critérios de aceite:

- Logs indicam claramente se houve bind ou default route.
- Conexão via 100.x funciona com Tailscale ativo.
- Conexão via LAN não regrediu.

## Epic 2 — Input channel MVP

### Task 2.1 — Criar protocolo mínimo de input

Objetivo: definir wire format simples para MVP.

Eventos mínimos:

```text
KeyboardKey
PointerRelative
PointerButton
PointerWheel
AllInputsUp
Ping/Pong opcional
```

Critérios de aceite:

- Mensagens têm sequence number.
- Teclado e mouse não dependem do socket de vídeo.
- Erro de parse fecha canal de input sem derrubar necessariamente vídeo.

### Task 2.2 — Criar InputServer no Mac

Objetivo: receber input em canal dedicado.

Escopo:

- Listener separado no MVP ou conexão adicional.
- `TCP_NODELAY`.
- Queue dedicada.
- Callback para backend.
- Estado de teclas/botões pressionados.

Critérios de aceite:

- Recebe eventos sem bloquear vídeo.
- Disconnect chama release-all.
- Logs de sequence/latência existem.

### Task 2.3 — Criar InputClient no Android

Objetivo: enviar input sem interferir no decoder.

Escopo:

- Socket TCP dedicado.
- Thread/coroutine própria.
- Backpressure mínimo.
- Envio de AllInputsUp em lifecycle events.

Critérios de aceite:

- Input continua funcionando com vídeo pesado.
- Perda de canal de input não trava UI.
- Reconexão limpa estado.

### Task 2.4 — Capturar teclado sem root

Objetivo: enviar teclas comuns ao Mac.

Escopo:

- Hook em Activity para `dispatchKeyEvent`.
- Mapear down/up.
- Capturar keyCode, scanCode, repeat, metaState.
- Mapa inicial para HID-like.

Critérios de aceite:

- Letras/números funcionam.
- Enter/Escape/Tab funcionam.
- Setas funcionam.
- Modificadores comuns funcionam quando entregues pelo Android.

### Task 2.5 — Capturar mouse sem root

Objetivo: mouse Bluetooth como mouse remoto real.

Escopo:

- `requestPointerCapture`.
- `onCapturedPointerEvent`.
- `onGenericMotionEvent` fallback.
- Movimento relativo.
- Botões.
- Wheel.

Critérios de aceite:

- Movimento relativo não fica preso a coordenadas absolutas do tablet.
- Clique esquerdo/direito funcionam.
- Drag funciona.
- Scroll funciona.
- Existe escape para sair do pointer capture.

### Task 2.6 — CGEvent backend inicial

Objetivo: validar input no Mac sem VirtualHID.

Escopo:

- Eventos de teclado com CGEvent.
- Mouse move/click/scroll com CGEvent.
- Permissões necessárias documentadas.
- Release-all.

Critérios de aceite:

- TextEdit recebe texto.
- Terminal recebe comandos.
- Finder recebe atalhos comuns.
- Disconnect solta tudo.

## Epic 3 — HID-like protocol and state

### Task 3.1 — Formalizar RemoteInputProtocol v1

Objetivo: estabilizar protocolo independente de Android.

Escopo:

- versionamento;
- event type;
- sequence;
- timestamp monotônico;
- device id;
- payloads tipados.

Critérios de aceite:

- Documentação do protocolo existe.
- Parser rejeita versões incompatíveis.
- Logs são suficientes para debug.

### Task 3.2 — Estado de input no Mac

Objetivo: evitar stuck keys/buttons.

Escopo:

- pressed keys;
- pressed buttons;
- timeout;
- all-up;
- lifecycle disconnect.

Critérios de aceite:

- Simular queda de rede durante Command pressionado solta Command.
- Simular queda durante drag solta mouse.
- Duplicatas não corrompem estado.

### Task 3.3 — Coalescing seguro de mouse

Objetivo: reduzir backlog sem perder semântica.

Escopo:

- coalescer apenas `PointerRelative` consecutivos;
- preservar ordem com button/wheel;
- não coalescer teclado.

Critérios de aceite:

- Mouse fica suave sob carga.
- Clique/drag não é perdido.
- Logs mostram taxa de coalescing.

## Epic 4 — Virtual HID

### Task 4.1 — Abstrair InputBackend no Mac

Objetivo: trocar backend sem alterar rede.

Backends:

```text
CGEventBackend
VirtualHIDBackend
```

Critérios de aceite:

- Configuração seleciona backend.
- Fallback para CGEvent se VirtualHID indisponível.

### Task 4.2 — Integrar Karabiner VirtualHID

Objetivo: usar teclado/mouse virtual real.

Escopo:

- detectar instalação;
- mostrar instrução de instalação/ativação;
- enviar key reports;
- enviar mouse reports;
- lidar com erro do driver.

Critérios de aceite:

- macOS vê input como dispositivo virtual.
- Hotkeys comuns funcionam de forma mais nativa.
- CGEvent fallback ainda funciona.

## Epic 5 — Security/session

### Task 5.1 — Device registry

Objetivo: pareamento por dispositivo.

Escopo:

- Android cria deviceId persistente.
- Mac registra deviceId e nome.
- Mac lista/revoga dispositivos.

Critérios de aceite:

- Revogar um tablet impede reconexão.
- Reset global ainda existe.

### Task 5.2 — Session auth

Objetivo: separar pairing de sessão.

Escopo:

- nonce por conexão;
- HMAC ou equivalente;
- session id;
- canais adicionais autorizados por sessão.

Critérios de aceite:

- Input channel não abre sem sessão válida.
- Token de QR não é necessário permanentemente em claro.

## Epic 6 — Diagnostics

### Task 6.1 — Tela de diagnóstico Android

Mostrar:

- endpoint;
- mode;
- Tailscale tips;
- codec;
- FPS;
- RTT;
- input events/sec;
- pointer capture state;
- últimos erros.

### Task 6.2 — Tela de diagnóstico Mac

Mostrar:

- cliente pareado;
- endpoint anunciado;
- codec;
- bitrate;
- FPS;
- keyframes;
- input backend;
- pressed state;
- release-all count;
- últimas quedas.

## Epic 7 — Root future

### Task 7.1 — Root discovery passivo

Objetivo: diagnosticar eventos crus sem substituir backend.

Escopo:

- solicitar root em build/dev;
- listar `/dev/input/event*`;
- mostrar capabilities;
- logar eventos.

Critérios de aceite:

- Sem root, app continua normal.
- Com root, tela mostra eventos crus.
- Nada é enviado ao Mac ainda.

