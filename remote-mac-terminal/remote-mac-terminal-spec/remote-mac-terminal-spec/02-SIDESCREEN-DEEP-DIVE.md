# 02 — SideScreen Deep Dive

## Visão geral

O SideScreen atual é um sistema de segundo display para macOS com cliente Android.

Arquitetura observada:

```text
MacHost
  ├─ cria Virtual Display
  ├─ captura frames do display
  ├─ codifica HEVC/H.264
  ├─ envia frames via TCP
  ├─ recebe touch
  └─ injeta eventos sintéticos no macOS

AndroidClient
  ├─ conecta via USB/ADB ou Wi-Fi/LAN
  ├─ autentica via token no modo wireless
  ├─ recebe frames
  ├─ decodifica com MediaCodec
  ├─ renderiza em SurfaceView
  └─ envia touch normalizado
```

## Pipeline de vídeo existente

```text
CGVirtualDisplay
  ↓
ScreenCaptureKit / CGDisplayStream fallback
  ↓
CVPixelBuffer
  ↓
VideoToolbox VTCompressionSession
  ↓
HEVC/H.265 ou H.264 Annex-B
  ↓
TCP
  ↓
Android MediaCodec
  ↓
SurfaceView
```

Este pipeline deve ser reaproveitado.

## Virtual Display

Arquivos principais:

```text
MacHost/Sources/CGVirtualDisplayBridge.h
MacHost/Sources/VirtualDisplayManager.swift
```

O projeto usa uma ponte Objective-C para APIs privadas `CGVirtualDisplayDescriptor`, `CGVirtualDisplayMode`, `CGVirtualDisplaySettings` e `CGVirtualDisplay`.

`VirtualDisplayManager.createDisplay(...)`:

- destrói display anterior;
- calcula resolução física 2x em HiDPI;
- configura PPI para macOS reconhecer retina;
- define vendor/product/serial;
- cria modos de display;
- instancia `CGVirtualDisplay`;
- aplica settings;
- expõe `displayID`.

Decisão: manter esta camada, mas encapsular melhor. Ela é o diferencial do projeto.

Risco: por usar API privada, pode quebrar em futuras versões do macOS. Para uso pessoal ou projeto open-source experimental, é aceitável. Para produto comercial, isso exigiria estratégia separada.

## Captura

Arquivo principal:

```text
MacHost/Sources/ScreenCapture.swift
```

Pontos importantes:

- usa `SCStream` e `SCStreamConfiguration`;
- desativa áudio;
- mostra cursor;
- define `minimumFrameInterval` conforme FPS;
- usa `queueDepth = 4`;
- tem fallback para `CGDisplayStream`;
- possui frame monitor e restart/fallback;
- possui backpressure antes de enfileirar encode.

O backpressure atual é especialmente importante:

```text
se encode queue já tem 2+ frames pendentes:
  descartar frame novo
```

Isso evita que o vídeo acumule latência. Para remote display, descartar frame antigo é melhor do que mostrar tudo atrasado.

Decisão: manter esse comportamento.

## Codificação

Arquivo principal:

```text
MacHost/Sources/VideoEncoder.swift
```

O encoder usa `VTCompressionSession` com:

- hardware acceleration;
- HEVC ou H.264;
- `kVTCompressionPropertyKey_RealTime = true`;
- profile Main;
- bitrate médio configurável;
- expected frame rate;
- GOP curto, keyframe por segundo;
- sem B-frames;
- `MaxFrameDelayCount = 0`;
- qualidade ajustável;
- output Annex-B com parameter sets em keyframes.

Decisão: reaproveitar. Não trocar o encoder no MVP.

## Transporte atual

Arquivo principal:

```text
MacHost/Sources/StreamingServer.swift
AndroidClient/.../StreamClient.kt
```

O transporte usa TCP com protocolo próprio.

Tipos atuais de mensagem:

```text
0  legacy video frame
1  display config
2  touch event
4  ping
5  pong
6  video frame with metadata
7  keyframe request
8  client supports frame metadata
9  client AVC-only
10 codec selected
```

Problema: vídeo, touch, ping, negotiation e keyframe request compartilham a mesma conexão. Em LAN/USB isso é aceitável; via internet, input pode ficar atrás de frames grandes.

Decisão: manter transporte de vídeo inicialmente, mas criar input channel separado.

## Pareamento atual

Arquivos principais:

```text
MacHost/Sources/WirelessAuth.swift
MacHost/Sources/PairingURL.swift
MacHost/Sources/HandshakeCodec.swift
AndroidClient/.../AuthHandshake.kt
AndroidClient/.../PairingURL.kt
```

Modelo atual:

```text
Mac gera token de 32 bytes
  ↓
Mac monta URL sidescreen://host:port?t=token&name=...
  ↓
Android lê QR
  ↓
Android conecta no host:port
  ↓
Android envia [magic 4][token 32][name_len 1][name]
  ↓
Mac responde [magic 4][status 1]
```

Pontos bons:

- simples;
- local;
- token aleatório;
- validação constant-time no Mac;
- QR já resolve onboarding.

Limitações:

- token é bearer token persistente;
- QR carrega IP LAN;
- não diferencia dispositivo e sessão;
- não tem rotação/nonce/HMAC por sessão;
- não tem revogação por deviceId real.

Decisão: reaproveitar para MVP, evoluir para pairing por dispositivo na Alpha.

## Input atual

Input atual é basicamente touch.

Android:

- `MainActivity.handleTouch(...)` normaliza coordenadas;
- suporta até dois dedos;
- usa `InputPredictor` para movimento de um dedo;
- envia mensagem tipo `2` pelo mesmo socket do vídeo.

Mac:

- `StreamingServer` chama `onTouchEvent`;
- `AppDelegate.handleTouch(...)` interpreta gestos;
- injeta mouse, clique, scroll e zoom com `CGEvent` em `.cghidEventTap`.

Problema: isso é uma arquitetura de touchscreen remoto, não de teclado/mouse remoto.

Decisão: touch pode continuar existindo como modo opcional, mas teclado/mouse devem ter subsistema próprio.

## Problema específico de Tailscale

No Android, `StreamClient.connectWireless(...)` força o socket para uma rede Wi-Fi encontrada via `ConnectivityManager` e `NetworkCapabilities.TRANSPORT_WIFI`, depois chama `wifiNetwork.bindSocket(sock)`.

Isso foi criado para resolver casos onde LAN local não roteava corretamente. Para Tailnet, é um problema: Tailscale aparece como VPN e o Android deve poder rotear pelo VPN. Forçar Wi-Fi pode impedir o tráfego Tailnet.

Decisão para Tailnet: não chamar `bindSocket` em modo Tailnet.

## O que reaproveitar

Reaproveitar:

- `VirtualDisplayManager`;
- `ScreenCapture`;
- `VideoEncoder`;
- `VideoDecoder`;
- frame metadata;
- keyframe request;
- codec negotiation;
- HiDPI handling;
- QR/pairing como ponto de partida;
- métricas básicas de FPS/bitrate/latência.

## O que descartar/refatorar

Refatorar ou descartar:

- `LANAddressResolver` como fonte única de host;
- bind Wi-Fi obrigatório no Android;
- canal único de vídeo/input;
- `MainActivity` monolítica;
- `AppDelegate` monolítico;
- touch como input primário;
- autenticação por token global persistente como solução final.

## Conclusão

O SideScreen é forte onde o novo projeto precisa de vídeo. Ele é fraco onde o novo projeto precisa de terminal remoto: sessão, Tailnet e input.

A melhor estratégia é preservar o motor de vídeo e construir ao redor dele uma arquitetura nova de produto remoto.

