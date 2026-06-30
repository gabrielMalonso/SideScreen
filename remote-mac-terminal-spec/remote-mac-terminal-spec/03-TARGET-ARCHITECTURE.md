# 03 — Target Architecture

## Objetivo arquitetural

Construir um terminal remoto de Mac para Android, não apenas um app de tela remota.

A arquitetura deve separar claramente:

```text
Video subsystem
Input subsystem
Session/auth subsystem
Transport subsystem
Diagnostics subsystem
```

## Visão macro

```text
┌───────────────────────────────────────────────┐
│ Android Tablet                                 │
│                                               │
│  TerminalClient                                │
│    ├─ SessionClient                            │
│    ├─ EndpointResolver                         │
│    ├─ VideoClient                              │
│    │   ├─ StreamReceiver                       │
│    │   └─ MediaCodecRenderer                   │
│    ├─ InputCapture                             │
│    │   ├─ ActivityKeyboardBackend              │
│    │   ├─ PointerCaptureBackend                │
│    │   ├─ AccessibilityAssistBackend opcional  │
│    │   └─ RootEvdevBackend futuro              │
│    ├─ InputClient                              │
│    └─ Diagnostics                              │
│                                               │
│  Tailscale Android VPN                         │
└───────────────────────┬───────────────────────┘
                        │ Tailnet
                        │ MagicDNS / 100.x
                        ▼
┌───────────────────────────────────────────────┐
│ Mac mini                                      │
│                                               │
│  MacHostAgent                                 │
│    ├─ SessionServer                           │
│    ├─ EndpointAdvertiser                      │
│    ├─ VideoService                            │
│    │   ├─ VirtualDisplayService               │
│    │   ├─ CaptureService                      │
│    │   ├─ EncodeService                       │
│    │   └─ VideoTransport                      │
│    ├─ InputIngress                            │
│    ├─ InputBackend                            │
│    │   ├─ VirtualHIDBackend principal futuro  │
│    │   └─ CGEventBackend fallback             │
│    ├─ DeviceRegistry                          │
│    └─ Diagnostics                             │
└───────────────────────────────────────────────┘
```

## Princípio de separação

O SideScreen atual mistura muito no `AppDelegate` e na `MainActivity`. O novo produto deve tratar vídeo e input como pipelines independentes.

```text
Vídeo:
  tolera drop de frames
  consome muita banda
  precisa de backpressure
  deve priorizar frame mais novo

Input:
  não tolera perda de key up/down
  consome pouca banda
  precisa de prioridade
  deve preservar ordem e estado
```

Não colocar os dois na mesma fila/socketeamento crítico.

## Canais de comunicação

### MVP recomendado

Para o MVP, usar TCP separado é suficiente:

```text
Control/Video channel:
  reaproveita StreamingServer existente

Input channel:
  novo InputServer/InputClient
  TCP_NODELAY
  protocolo binário simples
```

Pode ser `port + 1` inicialmente para reduzir risco de refatoração.

### Alpha recomendada

Na Alpha, evoluir para um único listener com múltiplas conexões classificadas por preamble:

```text
porta P:
  conexão 1 → CONTROL
  conexão 2 → VIDEO
  conexão 3 → INPUT
  conexão 4 → TELEMETRY opcional
```

Isso evita abrir múltiplas portas na Tailnet e simplifica configuração.

### Versão final possível

Na versão final, considerar QUIC se houver evidência real de necessidade.

Não migrar para QUIC por estética. Migrar apenas se medições mostrarem que TCP multi-channel ainda causa problemas em rede real.

## Camadas do MacHost

### SessionServer

Responsabilidades:

- aceitar conexão inicial;
- autenticar dispositivo;
- negociar capabilities;
- autorizar criação de canais;
- manter sessão ativa;
- detectar disconnect;
- emitir evento de fail-safe para soltar input.

### VideoService

Responsabilidades:

- criar/destruir Virtual Display;
- configurar resolução/HiDPI/FPS;
- capturar frames;
- codificar HEVC/H.264;
- enviar frames;
- responder a keyframe requests;
- expor telemetria de bitrate, FPS e frame age.

Deve ser baseado no código atual do SideScreen.

### InputIngress

Responsabilidades:

- receber eventos do canal de input;
- validar sequência;
- validar session id;
- manter estado de teclas/botões pressionados;
- coalescer mouse move quando necessário;
- nunca coalescer key down/up;
- soltar tudo em disconnect;
- encaminhar para backend ativo.

### InputBackend

Responsabilidades:

- transformar eventos HID-like em input do macOS.

Backends:

```text
CGEventBackend:
  fallback inicial
  simples
  depende de permissões de Accessibility/Input Monitoring

KarabinerVirtualHIDBackend:
  backend profissional prático
  usa driver já existente
  macOS vê teclado/mouse virtual

DriverKitOwnBackend:
  backend final de produto, se justificar
  caro de manter e distribuir
```

## Camadas do AndroidClient

### EndpointResolver

Responsabilidades:

- aceitar host vindo do QR;
- aceitar host manual;
- diferenciar LAN/Tailnet;
- não forçar Wi-Fi em Tailnet;
- diagnosticar DNS/MagicDNS;
- mostrar mensagens claras quando não consegue conectar.

### SessionClient

Responsabilidades:

- abrir conexão;
- autenticar;
- negociar capabilities;
- abrir canais adicionais;
- reconectar;
- comunicar estado à UI.

### VideoClient

Responsabilidades:

- receber frames;
- configurar decoder;
- lidar com H.265/H.264;
- pedir keyframe;
- dropar frames obsoletos;
- renderizar em SurfaceView.

Pode reaproveitar `StreamClient` e `VideoDecoder` gradualmente.

### InputCapture

Responsabilidades:

- receber eventos do teclado/mouse Bluetooth conforme o Android os entrega;
- normalizar para um modelo físico/HID-like;
- lidar com limitações sem root;
- expor múltiplos backends.

Backends:

```text
ActivityKeyboardBackend:
  dispatchKeyEvent/onKeyDown/onKeyUp

PointerCaptureBackend:
  requestPointerCapture/onCapturedPointerEvent/onGenericMotionEvent

AccessibilityAssistBackend:
  opcional
  tenta ampliar captura de teclas
  não é confiável como backend principal

RootEvdevBackend:
  futuro
  lê /dev/input/event*
```

## Protocolo de input: modelo, não Android KeyEvent

O protocolo deve representar intenção física próxima de HID.

Eventos conceituais:

```text
KeyboardKey
  usagePage
  usageId
  physicalScanCode opcional
  location: left/right/numpad/standard
  action: down/up
  modifiersSnapshot
  timestamp
  sequence

TextCommit
  unicodeScalar(s)
  timestamp
  sequence

PointerRelative
  dx
  dy
  timestamp
  sequence

PointerButton
  button
  action: down/up
  timestamp
  sequence

PointerWheel
  deltaX
  deltaY
  highResolution flag
  timestamp
  sequence

PointerAbsolute
  xNormalized
  yNormalized
  source: touch/stylus/mouseAbsolute
  timestamp
  sequence

AllInputsUp
  reason
  timestamp
  sequence
```

## Segurança

Tailscale protege rede, mas não substitui auth da aplicação.

Camadas:

```text
Tailscale:
  quem consegue chegar no IP/hostname

App auth:
  qual tablet pode controlar o Mac

Session auth:
  qual conexão atual está autorizada
```

Evolução recomendada:

```text
MVP:
  token de pareamento atual reaproveitado

Alpha:
  deviceId + chave por dispositivo + HMAC por sessão

Final:
  revogação por dispositivo + rotação + pairing temporário
```

## Diagnóstico como parte da arquitetura

O produto depende de rede real. Diagnóstico não é extra.

Expor na UI:

- endpoint conectado;
- modo: USB/LAN/Tailnet;
- host resolvido;
- RTT;
- frame age;
- FPS real;
- bitrate;
- codec ativo;
- input latency;
- último keyframe;
- número de frames dropados;
- se o Android está usando rota padrão ou VPN;
- aviso se o app estiver excluído do Tailscale split tunneling.

## Arquitetura final recomendada

```text
MacHostAgent
  SessionServer
  VideoService    ← SideScreen reaproveitado
  InputIngress    ← novo
  InputBackends   ← CGEvent primeiro, VirtualHID depois
  Diagnostics

AndroidTerminalClient
  SessionClient
  VideoClient     ← SideScreen reaproveitado
  InputCapture    ← novo
  InputClient     ← novo
  Diagnostics

Tailscale
  underlay de rede
```

