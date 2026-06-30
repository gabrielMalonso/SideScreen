# Appendix A — SideScreen Code Reference

Base: `SideScreen-source-macos-android-2026-06-30.zip`.

Este apêndice lista os pontos relevantes do código existente para orientar o Codex. Line numbers referem-se ao snapshot analisado.

## Estrutura geral

```text
MacHost/Sources/
  AppDelegate.swift
  VirtualDisplayManager.swift
  CGVirtualDisplayBridge.h
  ScreenCapture.swift
  VideoEncoder.swift
  StreamingServer.swift
  WirelessAuth.swift
  PairingURL.swift
  HandshakeCodec.swift
  LANAddressResolver.swift
  SettingsWindow.swift

AndroidClient/app/src/main/java/com/sidescreen/app/
  MainActivity.kt
  StreamClient.kt
  VideoDecoder.kt
  AuthHandshake.kt
  PairingURL.kt
  WirelessTabController.kt
  InputPredictor.kt
```

## Mac — Virtual Display

### `MacHost/Sources/CGVirtualDisplayBridge.h`

Declara ponte para API privada:

- `CGVirtualDisplayDescriptor`;
- `CGVirtualDisplayMode`;
- `CGVirtualDisplaySettings`;
- `CGVirtualDisplay`.

Trecho relevante: arquivo inteiro, linhas 1–67.

### `MacHost/Sources/VirtualDisplayManager.swift`

Funções relevantes:

- classe: linha 6;
- `createDisplay(...)`: linhas 26–102;
- `cloneMainDisplay()`: linhas 105–125;
- `enableMirrorMode()`: linhas 128–160;
- `disableMirrorMode()`: linhas 163+;
- `destroyDisplay()`: linha 284+.

Pontos de atenção:

- HiDPI duplica resolução física;
- PPI alto usado para macOS reconhecer Retina;
- `vendorID = 0xEEEE`;
- productID depende de resolução;
- `displayID` exposto para captura.

## Mac — Capture

### `MacHost/Sources/ScreenCapture.swift`

Funções relevantes:

- `ScreenCapture`: linha 24;
- `requestKeyframe`: linha 74;
- `requestKeyframeOrReplayCachedFrame`: linha 86;
- `encodeSize(for:)`: linha 128;
- `setupForVirtualDisplay(...)`: linha 156;
- `setupStream()`: linha 223;
- `configureFrameHandler(...)`: linhas 268–315;
- `startStreaming(...)`: linhas 319–345+;
- `attemptFallbackCapture()`: linha 464;
- `setCodec(...)`: linha 557;
- `stopStreaming()`: linha 578;
- `StreamOutput`: linhas 611–618.

Pontos de atenção:

- `SCStreamConfiguration` configura FPS, cursor, queueDepth e sem áudio;
- backpressure descarta frames se há 2+ encodes pendentes;
- encoder chama `server.sendFrame`;
- fallback de captura existe e deve ser preservado.

## Mac — Encoder

### `MacHost/Sources/VideoEncoder.swift`

Funções relevantes:

- classe: linha 6;
- `updateSettings(...)`: linha 32;
- `setupCompressionSession()`: linhas 45–128;
- `requestKeyframe()`: linha 133;
- `encode(...)`: linha 137;
- output callback e montagem Annex-B: linhas 218–272.

Configuração relevante:

- hardware encoder enabled;
- HEVC ou H.264;
- real-time;
- bitrate médio;
- expected frame rate;
- keyframe interval 1s;
- no frame reordering;
- max frame delay zero;
- output inclui parameter sets em keyframes.

## Mac — Streaming server

### `MacHost/Sources/StreamingServer.swift`

Tipos de mensagem atuais: linhas 3–19.

```text
0 legacyVideoFrame
1 displayConfig
2 touchEvent
4 ping
5 pong
6 videoFrameWithMetadata
7 keyframeRequest
8 clientSupportsFrameMetadata
9 clientAvcOnly
10 codecSelected
```

Funções relevantes:

- classe: linha 36;
- `start()`: linha 89+;
- `handleConnection(...)`: linha 120;
- `onConnectionReady(...)`: linha 156;
- auth wireless: linha 207+;
- `processInputBuffer(...)`: linha 340+;
- `sendFrame(...)`: linha 443+.

Pontos de atenção:

- usa `NWListener` e `NWConnection`;
- configura TCP `noDelay`;
- suporta um cliente ativo;
- input touch e controle compartilham socket com vídeo;
- para o novo projeto, input deve sair deste canal.

## Mac — App lifecycle e input atual

### `MacHost/Sources/AppDelegate.swift`

Funções relevantes:

- `startServer()`: linhas 430–575+;
- cria virtual display: linhas 436–446;
- pula ADB em wireless: linhas 459–467;
- configura `StreamingServer`: linhas 492–505;
- define display size e codec negotiation: linhas 506–537;
- keyframe request: linhas 538–540;
- callback de touch: linhas 557–559;
- injeção de eventos: linhas 883–960+.

Input atual:

- `moveCursor`: 883–887;
- `performClick`: 889–898;
- `performDoubleClick`: 900–909;
- `performRightClick`: 911–918;
- `injectMouseDown`: 920–925;
- `injectMouseDragged`: 927–931;
- `injectMouseUp`: 933–937;
- `injectScrollEvent`: 939–950;
- `injectZoomEvent`: 952+.

Pontos de atenção:

- usa `CGEvent(...).post(tap: .cghidEventTap)`;
- serve como base para `CGEventBackend`;
- não deve continuar dentro de `AppDelegate` no produto final.

## Mac — LAN/pairing/auth

### `MacHost/Sources/LANAddressResolver.swift`

Função principal: `primaryIPv4()`, linhas 4–51.

Comportamento:

- usa `getifaddrs`;
- filtra loopback/link-local;
- prefere `en0`;
- depois interfaces `en*`;
- retorna primeiro candidato.

Ponto de atenção:

- correto para LAN;
- incorreto como fonte única para Tailnet;
- substituir por `EndpointResolver`/`EndpointAdvertiser`.

### `MacHost/Sources/WirelessAuth.swift`

Funções relevantes:

- token 32 bytes: linhas 7–12;
- persistência em UserDefaults: linhas 14–20;
- loadOrCreate: linhas 22–29;
- reset: linhas 31–35;
- validação constant-time: linhas 37–44.

### `MacHost/Sources/PairingURL.swift`

Função principal: `build(host:port:token:name:)`, linhas 3–17.

Formato atual:

```text
sidescreen://host:port?t=token&name=name
```

Adicionar `mode=tailnet|lan|usb` no novo projeto.

### `MacHost/Sources/HandshakeCodec.swift`

Formato atual:

```text
request:  [SSWA][token 32][name_len 1][name]
response: [SSWR][status 1]
```

Funções relevantes:

- magic/status: linhas 9–24;
- parse request: linhas 27–40;
- encode response: linhas 42–44.

## Android — StreamClient

### `AndroidClient/.../StreamClient.kt`

Funções relevantes:

- classe: linha 21;
- `connect()`: linhas 118–146;
- `connectWireless(...)`: linhas 160–205+;
- bind Wi-Fi problemático: linhas 166–185;
- `sendTouch(...)`: linhas 357–388;
- `requestKeyframe(...)`: linha 401+;
- `receiveVideoFrame(...)`: linha 471+;
- keyframe freshness: linha 518+.

Ponto crítico:

Em `connectWireless`, o socket é explicitamente ligado à rede Wi-Fi:

```text
NetworkCapabilities.TRANSPORT_WIFI
wifiNetwork.bindSocket(sock)
```

Isso deve ser desativado para Tailnet.

## Android — Decoder

### `AndroidClient/.../VideoDecoder.kt`

Funções relevantes:

- classe: linha 16;
- `setupDecoder()`: linhas 80–207;
- `findBestDecoder(...)`: linha 214+;
- decode/drop/keyframe handling: linhas 295+;
- `handleOutputBuffer(...)`: linhas 419–475.

Pontos de atenção:

- usa `MediaCodec.Callback`;
- thread de decoder com prioridade display;
- tenta configuração low-latency;
- fallback para basic/minimal format;
- dropa output stale com latência alta;
- pede keyframe em erros.

## Android — MainActivity

### `AndroidClient/.../MainActivity.kt`

Funções relevantes:

- classe: linha 42;
- `onCreate`: linha 70;
- fullscreen/performance: linhas 210–278;
- surface setup: linha 278;
- UI/settings: linhas 320+;
- `initializeDecoder`: linha 783;
- callbacks stream client: linha 831;
- `connectWireless(...)`: linhas 944–972;
- `connect(...)`: linhas 974–1035+;
- `disconnect`: linha 1136;
- `handleTouch(...)`: linhas 1182–1232.

Pontos de atenção:

- Activity é monolítica;
- touch é normalizado e enviado pelo `StreamClient`;
- não há subsistema de teclado/mouse profissional;
- deve ser refatorada em módulos.

## Android — Pairing/auth

### `AndroidClient/.../AuthHandshake.kt`

Formato:

```text
request: [SSWA][token 32][name_len 1][name]
response: [SSWR][status]
```

Funções relevantes:

- magic: linhas 3–5;
- response status: linhas 7–17;
- `encodeRequest`: linhas 23–31;
- `parseResponse`: linhas 36–40.

### `AndroidClient/.../PairingURL.kt`

Função principal: `parse(url)`, linhas 9–29.

Comportamento:

- exige scheme `sidescreen`;
- lê host;
- lê port;
- lê token `t` em base64url;
- exige token de 32 bytes;
- lê `name`.

Novo projeto:

- aceitar parâmetro `mode`;
- preservar compatibilidade com QR antigo.

