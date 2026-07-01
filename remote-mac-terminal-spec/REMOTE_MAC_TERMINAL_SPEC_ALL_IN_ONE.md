# Remote Mac Terminal — Relatório completo / Spec unificada
Este arquivo concatena a documentação principal para leitura linear. Para uso no Codex, prefira manter também os arquivos separados.


---

<!-- FILE: README.md -->

# Remote Mac Terminal for Android Tablet — documentação de arquitetura

Data: 2026-06-30  
Base analisada: `SideScreen-source-macos-android-2026-06-30.zip`  
Objetivo: transformar um tablet Android com teclado e mouse Bluetooth em um terminal remoto para um Mac mini via Tailscale, com experiência o mais próxima possível de um MacBook remoto.

## Como usar esta documentação no Codex

Comece por `00-CODEX-START-HERE.md`. Ele contém o briefing operacional para uma sessão de Codex.

A documentação foi estruturada para permitir evolução incremental: primeiro sem root, depois com backends opcionais de Accessibility e root. A intenção é evitar uma reescrita desnecessária do motor de vídeo do SideScreen e concentrar o projeto em sessão, rede Tailnet e input.

## Índice recomendado de leitura

1. `00-CODEX-START-HERE.md` — instruções para o Codex e limites da primeira fase.
2. `01-PROJECT-BRIEF.md` — contexto, objetivo de produto e critérios de sucesso.
3. `02-SIDESCREEN-DEEP-DIVE.md` — análise do SideScreen existente.
4. `03-TARGET-ARCHITECTURE.md` — arquitetura final recomendada.
5. `04-TAILSCALE-NETWORKING-SPEC.md` — adaptação para Tailnet/MagicDNS/IP 100.x.
6. `05-INPUT-ARCHITECTURE-SPEC.md` — arquitetura profissional do canal de input.
7. `06-ANDROID-LIMITATIONS-AND-ROOT-PLAN.md` — limitações sem root e plano posterior com root.
8. `07-IMPLEMENTATION-ROADMAP.md` — MVP, Alpha, Beta e versão final.
9. `08-CODEX-TASK-BACKLOG.md` — backlog técnico acionável para desenvolvimento.
10. `09-TEST-PLAN.md` — plano de validação funcional, rede, latência e input.
11. `10-RISKS-AND-OPEN-QUESTIONS.md` — riscos arquiteturais e decisões resolvidas/condicionais.
12. `11-REMOTE-INPUT-PROTOCOL-V1.md` — especificação do protocolo de input.
13. `12-SESSION-AND-TRANSPORT-SPEC.md` — sessão, canais e transporte.
14. `13-SECURITY-MODEL.md` — modelo de segurança.
15. `14-DOCUMENTATION-COVERAGE-AND-STATUS.md` — matriz de cobertura, estado atual e definição de documentação 100%.
16. `adr/` — decisões arquiteturais registradas.
17. `appendix/` — referências de código do SideScreen e referências externas.

## Resumo executivo

A conclusão principal é: não transformar o SideScreen inteiro no produto final. O SideScreen deve ser tratado como um motor de vídeo muito bom, mas o produto desejado é outro: um terminal remoto de Mac com input de alta fidelidade e sessão robusta via Tailnet.

A arquitetura recomendada é:

```text
SideScreen video engine
+
novo session/transport layer
+
novo remote HID input system
+
Tailscale como underlay de rede
```

O desenvolvimento deve começar sem root. Isso valida vídeo, Tailscale, sessão, latência real, mouse capture, teclado comum e UX. Root deve ser uma fase posterior, implementada como backend opcional de captura de input, não como premissa do produto.

Para continuar o projeto sem se perder em backlog antigo, leia `14-DOCUMENTATION-COVERAGE-AND-STATUS.md` antes de implementar. Ele separa o que já existe, o que está documentado e o que é futuro intencional.


---

<!-- FILE: 00-CODEX-START-HERE.md -->

# 00 — Codex Start Here

Este documento é o briefing para continuar o projeto em uma máquina local usando Codex.

Antes de editar código, leia também `14-DOCUMENTATION-COVERAGE-AND-STATUS.md`. Ele é a fotografia atual da documentação: o backlog mostra a decomposição das tarefas, mas nem toda tarefa ainda está pendente.

## Missão do projeto

Construir um app que transforme um tablet Android em um terminal remoto para um Mac mini em casa.

O setup-alvo é:

```text
Mac mini em casa
  ↕ Tailscale / Tailnet
Tablet Android fora de casa
  + teclado Bluetooth
  + mouse Bluetooth
```

A experiência desejada não é apenas "remote desktop". A meta é usar o tablet como se fosse um MacBook remoto:

- vídeo vindo de um Virtual Display real do macOS;
- teclado funcionando como teclado de Mac;
- mouse funcionando como mouse de Mac;
- baixa latência;
- uso pela internet via Tailscale, não apenas LAN;
- arquitetura preparada para input profissional e, futuramente, root no Android.

## Estratégia obrigatória da primeira fase

A primeira fase deve ser **sem root**.

Não implementar captura via `/dev/input/event*` no início. Não depender de root para o MVP. Root entra somente depois que o produto sem root provar valor.

A ordem correta é:

```text
1. Tailnet + vídeo existente funcionando
2. input dedicado sem root
3. CGEvent fallback no Mac
4. Virtual HID no Mac
5. Accessibility assist opcional no Android
6. root backend opcional no Android
```

## Decisão principal

Não reescrever o motor de vídeo agora. Reaproveitar o que o SideScreen já faz bem:

- `CGVirtualDisplay` / Virtual Display;
- ScreenCaptureKit;
- fallback CGDisplayStream;
- VideoToolbox;
- HEVC/H.264;
- MediaCodec;
- drop de frames atrasados;
- keyframe request;
- codec negotiation.

Criar arquitetura nova ao redor disso para:

- sessão;
- Tailscale endpoints;
- canais separados;
- input HID-like;
- backends de input no Mac;
- backends de captura no Android.

## O que não fazer no MVP

Não fazer no MVP:

- não implementar root;
- não implementar DriverKit próprio;
- não trocar todo o transporte para QUIC;
- não reescrever ScreenCapture/VideoToolbox/MediaCodec;
- não tentar capturar `Home`, `Power`, `Recents` sem root como requisito obrigatório;
- não enviar input pelo mesmo socket de vídeo;
- não forçar socket Android para Wi-Fi em modo Tailnet;
- não tratar `Android KeyEvent` como protocolo final.

## Primeira meta técnica

MVP mínimo:

```text
MacHost:
  cria Virtual Display
  captura/codifica vídeo como SideScreen
  aceita conexão via MagicDNS ou IP 100.x
  autentica tablet
  envia vídeo
  recebe input em canal dedicado
  injeta input via CGEvent fallback

AndroidClient:
  conecta via Tailscale sem bind forçado em Wi-Fi
  decodifica vídeo com MediaCodec
  captura teclado/mouse sem root dentro da Activity
  usa pointer capture para mouse quando possível
  envia input em protocolo próprio
```

## Invariantes arquiteturais

1. Vídeo e input são subsistemas separados.
2. O input não pode depender do pipeline de vídeo.
3. O input deve ter prioridade maior que o vídeo.
4. Teclas down/up nunca podem ser coalescidas.
5. Mouse move pode ser coalescido, mas botões/wheel não.
6. Ao desconectar, o Mac deve soltar todas as teclas e botões pressionados.
7. O protocolo de input deve ser HID-like, não Android-like.
8. Tailscale é underlay de rede, não substitui autenticação da aplicação.
9. O app Android não deve forçar `TRANSPORT_WIFI` quando conectado a destino Tailnet.
10. Root é backend opcional posterior, não dependência estrutural.

## Caminho de implementação sugerido para Codex

Se a base local já tiver parte destes passos implementada, não refaça. Compare primeiro com `14-DOCUMENTATION-COVERAGE-AND-STATUS.md`, os testes existentes e o código real.

### Passo 1 — preparar refactor mínimo de rede

- Criar conceito de `EndpointMode`: USB, LAN, TailnetManualHost, TailnetMagicDNS.
- No Mac, substituir uso direto de `LANAddressResolver` na geração de QR por um resolver mais genérico.
- No Android, permitir que o QR tenha `mode=tailnet` e host `.ts.net` ou IP `100.x.y.z`.
- Em modo Tailnet, remover `bindSocket` para Wi-Fi.

### Passo 2 — adicionar canal de input separado

- Criar `InputServer` no Mac.
- Criar `InputClient` no Android.
- Usar conexão TCP separada no MVP.
- Usar `TCP_NODELAY`.
- Manter vídeo existente inalterado tanto quanto possível.

### Passo 3 — input sem root

- Android: capturar `dispatchKeyEvent`, `onKeyDown`, `onKeyUp`, `onGenericMotionEvent` e pointer capture.
- Mac: receber eventos e injetar via `CGEvent` como fallback inicial.
- Criar estado de teclas pressionadas e fail-safe de disconnect.

### Passo 4 — Virtual HID no Mac

- Integrar Karabiner VirtualHID como backend principal.
- Manter CGEvent como fallback.
- Não escrever DriverKit próprio na primeira etapa.

### Passo 5 — Accessibility e root como backends adicionais

- Accessibility é modo assistido, não principal.
- Root é modo Pro opcional.
- O design deve permitir adicionar `RootEvdevBackend` sem alterar protocolo de rede.

## Arquivos mais importantes do SideScreen existente

Use estes arquivos como referência antes de alterar a base:

```text
MacHost/Sources/VirtualDisplayManager.swift
MacHost/Sources/ScreenCapture.swift
MacHost/Sources/VideoEncoder.swift
MacHost/Sources/StreamingServer.swift
MacHost/Sources/AppDelegate.swift
MacHost/Sources/LANAddressResolver.swift
MacHost/Sources/PairingURL.swift
MacHost/Sources/WirelessAuth.swift
MacHost/Sources/HandshakeCodec.swift

AndroidClient/app/src/main/java/com/sidescreen/app/StreamClient.kt
AndroidClient/app/src/main/java/com/sidescreen/app/VideoDecoder.kt
AndroidClient/app/src/main/java/com/sidescreen/app/MainActivity.kt
AndroidClient/app/src/main/java/com/sidescreen/app/PairingURL.kt
AndroidClient/app/src/main/java/com/sidescreen/app/AuthHandshake.kt
```

Mais detalhes estão em `appendix/A-SIDESCREEN-CODE-REFERENCE.md`.


---

<!-- FILE: 01-PROJECT-BRIEF.md -->

# 01 — Project Brief

## Contexto

A base analisada é o SideScreen, um projeto macOS + Android que transforma um tablet Android em segundo display para macOS via USB-C ou Wi-Fi/LAN.

O projeto atual já resolve muito bem a parte de vídeo:

- criação de display virtual real no macOS;
- captura via ScreenCaptureKit;
- codificação via VideoToolbox;
- HEVC/H.265 com fallback H.264;
- decodificação Android via MediaCodec;
- streaming de baixa latência;
- suporte a HiDPI;
- touch básico.

O novo objetivo é mais ambicioso: não criar apenas um segundo monitor, mas um terminal remoto para Mac.

## Produto-alvo

O produto-alvo deve permitir:

```text
Mac mini em casa
  → app host rodando localmente
  → conectado à Tailnet

Tablet Android fora de casa
  → app client em fullscreen
  → Tailscale ativo
  → teclado Bluetooth
  → mouse Bluetooth
```

O usuário deve conseguir abrir o tablet, conectar ao Mac mini e trabalhar como se estivesse usando um MacBook remoto.

## Não-objetivos iniciais

A primeira fase não deve tentar resolver tudo.

Não são objetivos do MVP:

- capturar todas as teclas de sistema do Android;
- usar root;
- usar DriverKit próprio;
- substituir Tailscale por NAT traversal próprio;
- criar concorrente completo de AnyDesk/Parsec/RustDesk;
- implementar clipboard, áudio, multi-monitor e file transfer imediatamente;
- suportar múltiplos clientes simultâneos.

## Princípio de produto

A percepção de qualidade será dominada por input e latência, não apenas por qualidade de imagem.

Uma imagem perfeita com input ruim parece ruim. Uma imagem ligeiramente comprimida com input excelente parece utilizável.

Logo, o projeto deve priorizar:

1. latência de input;
2. estabilidade de sessão;
3. mouse relativo correto;
4. teclado com mapeamento Mac previsível;
5. vídeo sem backlog;
6. recuperação rápida de rede.

## Critérios de sucesso do MVP

O MVP é bem-sucedido se:

- o Android conecta ao Mac via MagicDNS ou IP 100.x do Tailscale;
- vídeo do Virtual Display aparece no tablet fora da LAN;
- o app não força socket para Wi-Fi em modo Tailnet;
- mouse Bluetooth move o cursor do Mac com baixa latência;
- clique esquerdo, clique direito, drag e scroll funcionam;
- teclado Bluetooth envia letras, números, Enter, Escape, Tab e modificadores comuns;
- Command/Option/Control funcionam quando o Android entrega os eventos;
- desconectar não deixa teclas presas no Mac;
- quedas de rede não exigem reiniciar o Mac host;
- o usuário consegue usar Terminal, Finder, navegador e editor de texto com conforto básico.

## Critérios de sucesso da Alpha

A Alpha é bem-sucedida se:

- o input usa protocolo HID-like;
- vídeo e input estão em canais separados;
- o Mac tem backend Virtual HID ou integração Karabiner VirtualHID funcional;
- CGEvent continua disponível como fallback;
- mouse relativo usa pointer capture no Android;
- existe telemetria de RTT, frame age e input latency;
- existe configuração clara para layout de teclado;
- existe reconexão sem deixar estado preso.

## Critérios de sucesso da versão final

A versão final é bem-sucedida se:

- a experiência sem root é boa para uso diário;
- o modo root opcional melhora fidelidade de input sem afetar usuários normais;
- o host Mac tem instalação e permissões compreensíveis;
- o usuário conecta por nome, não por IP;
- o app identifica problemas de Tailnet, relay/DERP e split tunneling;
- o canal de input permanece responsivo mesmo com vídeo pesado;
- logs e diagnóstico permitem depurar problemas de rede e input.

## Direção estratégica

Criar um projeto novo ou um fork fortemente refatorado. A base do SideScreen deve ser aproveitada como motor de vídeo, mas o produto final deve ter arquitetura de terminal remoto.

Recomendação:

```text
Novo projeto/fork estruturado
  ├─ video engine reaproveitado do SideScreen
  ├─ session layer novo
  ├─ transport layer novo
  ├─ input layer novo
  └─ UI/configuração ajustada ao produto remoto
```

## Licença da base

O snapshot analisado contém `LICENSE` MIT. Ao reaproveitar código, preservar o copyright e a licença em cópias substanciais do código.


---

<!-- FILE: 02-SIDESCREEN-DEEP-DIVE.md -->

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


---

<!-- FILE: 03-TARGET-ARCHITECTURE.md -->

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


---

<!-- FILE: 04-TAILSCALE-NETWORKING-SPEC.md -->

# 04 — Tailscale Networking Spec

## Objetivo

Adaptar o projeto para funcionar pela internet usando Tailscale, mantendo a simplicidade do QR/pairing e evitando dependência de LAN.

## Premissas

- Mac mini e tablet Android estão na mesma Tailnet.
- Tailscale está instalado e conectado em ambos.
- O app não precisa implementar NAT traversal próprio.
- O app não deve usar APIs internas do Tailscale como requisito do MVP.
- O usuário pode usar MagicDNS ou IP 100.x manualmente.

## Conceito de endpoint

O projeto atual assume LAN. O novo projeto deve distinguir endpoint de rede.

```text
EndpointMode
  USB
  LAN
  TAILNET_MAGIC_DNS
  TAILNET_IP
  MANUAL
```

### USB

Usa ADB reverse, como SideScreen atual.

```text
Android conecta em 127.0.0.1:porta
Mac configura adb reverse
```

### LAN

Usa IP local.

```text
192.168.x.y
10.x.y.z
172.16-31.x.y
```

Pode continuar usando `LANAddressResolver`, mas somente para modo LAN.

### Tailnet MagicDNS

Preferido para uso real:

```text
mac-mini.<tailnet>.ts.net:porta
```

Também aceitar short name se o Android resolver corretamente, mas o QR deve preferir FQDN para reduzir ambiguidade.

### Tailnet IP

Fallback confiável:

```text
100.x.y.z:porta
```

IP 100.x é bom para diagnóstico e quando MagicDNS falha.

## QR de pareamento

Formato atual:

```text
sidescreen://host:port?t=TOKEN&name=Mac
```

Formato proposto para MVP:

```text
sidescreen://host:port?t=TOKEN&name=MacMini&mode=tailnet
```

Exemplos:

```text
sidescreen://mac-mini.tailnet-name.ts.net:54321?t=...&name=MacMini&mode=tailnet
sidescreen://100.101.102.103:54321?t=...&name=MacMini&mode=tailnet
sidescreen://192.168.1.50:54321?t=...&name=MacMini&mode=lan
```

O parser Android deve aceitar ausência de `mode` para compatibilidade com QR antigo. Se `mode` estiver ausente, tratar como `lan`/legacy.

## Mac: substituir LANAddressResolver como fonte única

Hoje a UI usa `LANAddressResolver.primaryIPv4()` para exibir listening address e gerar QR.

Novo modelo:

```text
EndpointAdvertiser
  currentMode
  configuredTailnetHost
  configuredTailnetIp
  lanAddressResolver
  buildPairingUrl()
```

### MVP simplificado

No MVP, não tentar descobrir MagicDNS automaticamente. Permitir o usuário informar:

- Tailnet hostname;
- ou IP 100.x do Mac;
- ou usar LAN automático.

Isso evita depender de CLI Tailscale e permissões adicionais.

### Pós-MVP

Opcionalmente, no Mac:

- detectar se `tailscale` CLI existe;
- usar `tailscale ip -4` para sugerir IP;
- permitir copiar hostname configurado;
- nunca tornar isso requisito.

## Android: remover bind Wi-Fi em modo Tailnet

Problema atual:

```text
StreamClient.connectWireless(...)
  procura Network com TRANSPORT_WIFI
  chama wifiNetwork.bindSocket(sock)
```

Esse comportamento deve ser preservado apenas como workaround de LAN, não em Tailnet.

Regra:

```text
if endpointMode == TAILNET_MAGIC_DNS or TAILNET_IP:
  não chamar bindSocket
  usar roteamento padrão do Android
else if endpointMode == LAN and workaroundEnabled:
  pode bindar Wi-Fi opcionalmente
```

Estado implementado:

- `StreamClient` e `InputClient` compartilham `NetworkRoute`.
- Tailnet/manual usam rota padrão do Android, permitindo VPN/Tailscale.
- LAN tenta localizar uma rede Wi-Fi com `NetworkCallback` filtrado por `TRANSPORT_WIFI` e `NET_CAPABILITY_INTERNET`.
- Se Wi-Fi não for encontrado, LAN cai para rota padrão e registra diagnóstico.
- O código não depende mais de `ConnectivityManager.allNetworks`.
- Android Wireless Diagnostics mostra transportes da rota ativa, validação de rede e aviso quando Tailnet está sem transporte VPN.
- Mac Settings valida host Tailnet no card de QR: diferencia IP 100.64.0.0/10, MagicDNS `.ts.net`, host manual e URL/porta digitada por engano.

## Split tunneling no Android

Tailscale Android suporta split tunneling por app. Se o usuário excluir o app cliente da Tailnet, MagicDNS/IP 100.x podem falhar.

A UI deve orientar:

```text
Se conexão Tailnet falhar:
  1. verificar se Tailscale está conectado
  2. verificar se este app não está excluído no split tunneling
  3. testar IP 100.x em vez de MagicDNS
  4. testar MagicDNS em vez de IP
```

## Direct vs relay

Tailscale pode usar conexão direta, peer relay ou DERP. Isso afeta latência e throughput.

O app não precisa controlar isso no MVP, mas deve medir:

- RTT;
- jitter aparente;
- bitrate sustentado;
- frame age;
- input latency.

Se a conexão cair em DERP, o app deve continuar funcionando, mas pode precisar reduzir bitrate/resolução/FPS.

## Porta e firewall

MVP:

- manter porta principal configurável do SideScreen;
- input channel pode usar `port + 1` inicialmente;
- documentar que ambos precisam estar acessíveis na Tailnet.

Alpha:

- migrar para single-port multi-channel se necessário.

Final:

- idealmente uma porta única;
- canais multiplexados por sessão;
- controle claro de permissões no firewall do macOS.

## Segurança

Tailscale reduz superfície de exposição, mas o app Mac ainda aceita controle remoto.

Exigências:

- não aceitar conexões sem auth fora de loopback;
- manter allowlist de dispositivos pareados;
- permitir revogar todos os dispositivos;
- permitir revogar um dispositivo;
- não logar tokens em texto claro;
- não exibir token inteiro na UI/log;
- usar token temporário de QR no futuro.

## Fluxo de conexão MVP via Tailnet

```text
MacHost:
  usuário seleciona modo Tailnet
  usuário informa host MagicDNS ou IP 100.x
  Mac gera QR com mode=tailnet
  Mac inicia listener

Android:
  usuário escaneia QR
  parser lê host/port/token/mode
  StreamClient cria Socket normal
  não faz bind Wi-Fi
  conecta host:port
  envia handshake atual
  recebe OK
  inicia vídeo
  inicia input channel separado
```

## Mensagens de erro sugeridas

| Situação | Mensagem |
|---|---|
| DNS `.ts.net` falhou | "Não consegui resolver o nome Tailnet. Teste usando o IP 100.x do Mac." |
| Timeout em IP 100.x | "Mac inacessível pela Tailnet. Verifique se Tailscale está ativo nos dois dispositivos." |
| Token rejeitado | "Pareamento rejeitado. Escaneie novamente o QR no Mac." |
| App excluído no split tunneling | "Verifique no Tailscale Android se este app não está excluído da Tailnet." |
| RTT alto | "Conexão Tailnet com alta latência. Reduza resolução/FPS ou verifique se está usando relay." |

## Critérios de aceite

- QR com `mode=tailnet` é aceito pelo Android.
- Host `.ts.net` é aceito e persistido.
- IP 100.x é aceito e persistido.
- Em Tailnet, `bindSocket` não é chamado.
- LAN antiga continua funcionando.
- USB antigo continua funcionando.
- Falhas de Tailnet têm mensagens específicas, não genéricas.


---

<!-- FILE: 05-INPUT-ARCHITECTURE-SPEC.md -->

# 05 — Input Architecture Spec

## Problema central

O vídeo já está bem resolvido pelo SideScreen. O problema maior é input.

O Android pode consumir eventos antes que cheguem ao app. Exemplos críticos:

- Home;
- Power;
- Recents/Overview;
- alguns atalhos com Meta/Super;
- atalhos interceptados por launcher/OEM;
- eventos globais de sistema.

Sem root, não há garantia de captura total. A arquitetura deve aceitar essa realidade e ainda entregar a melhor experiência possível.

## Princípio principal

Não usar `Android KeyEvent` como protocolo final.

`KeyEvent` é um evento pós-framework do Android. Ele já passou por tradução, filtragem, layout e consumo parcial pelo sistema. O protocolo remoto deve representar algo mais próximo de hardware/HID.

Direção correta:

```text
Android capture backend
  ↓
modelo físico/HID-like interno
  ↓
canal de input dedicado
  ↓
Mac InputIngress
  ↓
Virtual HID backend
  ↓
macOS vê teclado/mouse virtual
```

## Backends de captura no Android

### 1. ActivityKeyboardBackend

Fase: MVP.

Captura eventos entregues à Activity:

```text
dispatchKeyEvent
onKeyDown
onKeyUp
```

Responsável por:

- identificar action down/up;
- capturar keyCode;
- capturar scanCode quando disponível;
- capturar metaState;
- distinguir left/right quando Android fornece;
- mapear para usage HID quando possível;
- gerar evento `KeyboardKey`.

Limitações:

- não recebe teclas que o Android consome;
- comportamento varia por fabricante;
- pode perder alguns eventos com Meta/Super;
- depende da Activity estar focada.

Estado implementado:

- `RemoteKeyboardCapture` concentra a captura de `KeyEvent`, filtragem de duplicatas do Accessibility Assist, diagnóstico e envio para `InputClient`;
- `MainActivity` só delega `dispatchKeyEvent`.

### 2. PointerCaptureBackend

Fase: MVP/Alpha.

Captura mouse Bluetooth.

Usar:

```text
requestPointerCapture()
onCapturedPointerEvent(MotionEvent)
onGenericMotionEvent(MotionEvent)
```

Responsável por:

- movimento relativo `dx/dy`;
- botões;
- wheel vertical;
- wheel horizontal quando disponível;
- high-resolution wheel quando possível;
- entrada/saída de pointer capture;
- fallback se pointer capture falhar.

Este backend é essencial para o app parecer terminal, não tablet touch.

Estado implementado:

- `RemoteMouseCapture` concentra movimento relativo, botões, wheel, pointer tuning, coalescing via `InputClient` e release-all em cancelamento;
- `MainActivity` só delega eventos de pointer capture/generic motion.

### 3. TouchBackend

Fase: manter como opcional.

Captura touch da tela do tablet e envia como touch/absolute pointer. Não deve ser misturado com mouse relativo.

Eventos:

```text
PointerAbsolute
TouchGesture
```

### 4. AccessibilityAssistBackend

Fase: Alpha sem root.

Accessibility pode pedir para filtrar eventos de tecla, mas não deve ser backend principal.

Uso recomendado:

- modo opcional "captura assistida";
- tentar obter eventos adicionais de teclado;
- não prometer captura de Home/Power/Recents;
- explicar claramente ao usuário por que a permissão é sensível.
- não ler conteúdo de tela;
- evitar duplicar eventos que também chegam via Activity.

Implementação atual:

- `SideScreenAccessibilityService` solicita `flagRequestFilterKeyEvents`;
- encaminha `KeyEvent` para o mesmo `InputClient` quando há sessão de input ativa;
- marca eventos com `FLAG_FROM_ACCESSIBILITY`;
- consome eventos encaminhados para evitar efeito local;
- a Activity ignora duplicatas recentes enviadas pelo serviço.

## Diagnóstico de captura sem root

O Android deve mostrar diagnóstico honesto sobre input:

- `captured`: eventos entregues pelo Android que foram convertidos e enviados ao Mac;
- `unsupported`: eventos entregues pelo Android, mas sem mapeamento HID/remote conhecido;
- `assist`: eventos enviados pelo Accessibility Assist;
- `dup`: eventos da Activity ignorados porque o Accessibility Assist já os encaminhou;
- `last`: último evento observado com fonte, ação, keyCode, scanCode e repeat.
- `TextCommit`: registrar apenas tamanho/metadata, nunca o texto digitado.

Isso não mede teclas que o Android nunca entrega ao app, como Home/Power/Recents em muitos dispositivos. Essas continuam documentadas como limitação sem root.

### 5. RootEvdevBackend

Fase: Beta/Pro.

Com root, ler eventos crus de `/dev/input/event*`.

Responsabilidades futuras:

- descobrir dispositivos teclado/mouse;
- ler evdev;
- mapear Linux input codes para HID usages;
- opcionalmente usar grab/exclusive mode;
- enviar eventos antes do Android consumi-los;
- resolver a maioria das limitações de Meta/Home/atalhos.

Não implementar antes do produto sem root estar bom.

## Modelo interno de input no Android

Criar modelo único antes de serializar.

```text
RemoteInputEvent
  sequence: UInt64
  timestampMonotonicNanos: UInt64
  deviceId: UInt32
  source: keyboard | mouse | touch | stylus | accessibility | root
  payload: KeyboardKey | TextCommit | PointerRelative | PointerButton | PointerWheel | PointerAbsolute | AllInputsUp
```

## KeyboardKey

Campos:

```text
KeyboardKey
  usagePage: UInt16
  usageId: UInt16
  scanCode: UInt32 optional
  androidKeyCode: UInt32 optional
  location: standard | left | right | numpad
  action: down | up
  repeatCount: UInt16
  modifiersSnapshot: UInt32
```

### Regras

- Down e up devem sempre preservar ordem.
- Não coalescer teclado.
- Se houver repeat, enviar repeat explicitamente ou como down com repeatCount.
- Se o backend detectar cancelamento, enviar up/fail-safe.
- Manter mapa de pressed keys no Android e no Mac.

### Modifier mapping

Estado implementado:

- Android Settings permite configurar `Meta/Super` como Command, Option, Control ou Off.
- O padrão é Command para preservar comportamento de Mac remoto.
- A escolha altera o `usageId` HID antes do envio, sem mudar o protocolo.
- `Off` transforma Meta/Super em unsupported quando o Android entrega a tecla ao app.

## TextCommit

Nem todo texto é melhor representado como tecla física. IME, dead keys e composição podem exigir evento de texto.

Campos:

```text
TextCommit
  utf8Text
```

Uso:

- fallback para texto composto;
- opcional no MVP;
- não substituir hotkeys físicas.

Regra: atalhos precisam de `KeyboardKey`, não `TextCommit`.

Estado implementado:

- `RemoteSurfaceView` expõe `InputConnection.commitText()` para IME/dead keys;
- `ACTION_MULTIPLE` também é convertido como fallback legado;
- Android serializa texto UTF-8 com comprimento validado;
- Mac valida o payload e injeta texto Unicode;
- diagnóstico registra somente tamanho do texto, não conteúdo.

## PointerRelative

Campos:

```text
PointerRelative
  dx: Int32 ou Float
  dy: Int32 ou Float
  accelerationApplied: Bool
```

Regras:

- usar movimento relativo quando origem for mouse;
- coalescer apenas movimentos consecutivos sem botões/wheel entre eles;
- não transformar mouse em touch absoluto.

Estado implementado:

- Android Settings expõe sensibilidade de pointer de `0.25x` a `3.0x`;
- a sensibilidade é aplicada antes de serializar `PointerRelative`;
- Android coalesce `PointerRelative` por uma janela curta e força flush antes de teclado, botões, wheel, ping e `AllInputsUp`;
- valores persistidos fora da faixa são normalizados.

## PointerButton

Campos:

```text
PointerButton
  button: left | right | middle | back | forward | extraN
  action: down | up
```

Regras:

- não coalescer;
- manter estado de botões;
- soltar tudo em disconnect.

## PointerWheel

Campos:

```text
PointerWheel
  deltaX
  deltaY
  unit: line | pixel | highResolution
```

Regras:

- preservar horizontal scroll quando disponível;
- direção natural deve ser configurável.

Estado implementado:

- Android Settings expõe sensibilidade de scroll de `0.25x` a `3.0x`;
- Android Settings expõe toggle de natural scroll;
- a configuração é aplicada antes de serializar `PointerWheel`;
- horizontal e vertical scroll usam a mesma direção e sensibilidade.

## PointerAbsolute

Campos:

```text
PointerAbsolute
  xNormalized: Float
  yNormalized: Float
  source: touch | stylus | absoluteMouse
  action: down | move | up | cancel
  pointerId
  pointerCount
```

Usado para touch/stylus, não para mouse Bluetooth comum.

## Input channel

O canal de input deve ser separado do vídeo.

MVP:

```text
TCP socket separado
TCP_NODELAY=true
mensagens pequenas
sem compressão
```

Alpha:

```text
single-port multi-channel ou QUIC streams
prioridade alta para input
```

## Mac InputIngress

Responsabilidades:

```text
InputIngress
  recebe mensagem
  valida sessão
  valida sequence
  atualiza pressedState
  detecta perda/duplicidade
  aplica coalescing permitido
  chama backend ativo
  registra latência
```

### Estado obrigatório

```text
pressedKeys: Set<KeyIdentity>
pressedButtons: Set<ButtonIdentity>
lastSequence: UInt64
lastEventTimestamp
activeDeviceId
```

### Fail-safe obrigatório

Em qualquer uma destas situações:

- disconnect;
- timeout de input;
- session invalidada;
- app Android vai para background;
- pointer capture perdido;
- erro de protocolo;

O Mac deve executar:

```text
releaseAllKeys()
releaseAllButtons()
cancelDragIfAny()
resetModifiers()
```

## Mac input backends

### CGEventBackend

Fase: MVP.

Prós:

- simples;
- já há uso no SideScreen para mouse/touch;
- suficiente para validar pipeline.

Contras:

- evento sintético;
- permissões sensíveis;
- pode falhar em contextos protegidos;
- não é dispositivo real;
- pode divergir de input físico em apps específicos.

Uso: fallback e MVP.

### KarabinerVirtualHIDBackend

Fase: Alpha.

Prós:

- cria teclado/mouse virtual reconhecido como hardware;
- muito mais próximo da experiência nativa;
- evita escrever DriverKit próprio no início;
- projeto maduro e usado em produção por Karabiner.

Contras:

- exige instalação/ativação de driver/system extension;
- UX de permissão no macOS é chata;
- dependência externa.

Uso recomendado: backend principal prático.

### DriverKitOwnBackend

Fase: final, somente se necessário.

Prós:

- controle total;
- arquitetura limpa para produto próprio;
- sem dependência Karabiner.

Contras:

- precisa de entitlements;
- distribuição/notarização mais complexa;
- maior custo de manutenção;
- mais risco por versão de macOS.

Uso recomendado: somente se o projeto virar produto sério ou se Karabiner não atender.

### CoreHID/HIDVirtualDevice

Fase: investigação.

Apple documenta virtual HID em APIs modernas. Avaliar compatibilidade, requisitos de entitlement, versão mínima e distribuição antes de decidir. Não assumir como solução do MVP.

## Mapeamento inicial de teclado

Modo padrão "Mac keyboard em teclado PC/Android":

| Origem Android | Destino macOS |
|---|---|
| Ctrl left/right | Control left/right |
| Alt left/right | Option left/right |
| Meta/Super left/right, se entregue | Command left/right |
| Escape | Escape |
| Tab | Tab |
| Enter | Return |
| Backspace | Delete backward |
| Forward delete | Delete forward |
| Arrow keys | Arrows |
| F1-F12 | F1-F12 |

Adicionar preferência futura:

```text
Modifier Mapping
  Meta → Command
  Ctrl → Control
  Alt → Option
  CapsLock → CapsLock/Escape/Control opcional
```

## Observações sobre layouts

Não tentar resolver todos os layouts no MVP.

MVP:

- mapear teclas comuns;
- suportar US como baseline;
- permitir texto via Android quando necessário;
- documentar limitações ABNT2.

Alpha:

- tabela de mapping por layout;
- separar tecla física de caractere;
- lidar com dead keys;
- testar ABNT2.

## Priorização de input

Input deve ter prioridade de processamento maior do que vídeo.

No Android:

- thread/coroutine dedicada;
- evitar alocação por evento sempre que possível;
- não bloquear em operações de vídeo.

No Mac:

- queue dedicada;
- evitar DispatchQueue main para input crítico;
- só tocar main thread quando necessário para UI.

## Métricas de input

Registrar:

- tempo do evento no Android;
- chegada no Mac;
- despacho ao backend;
- sequência;
- eventos dropados;
- coalescing de mouse;
- releaseAll por fail-safe;
- teclas atualmente pressionadas.

## Critérios de aceite do input MVP

- letras/números funcionam em TextEdit/Terminal;
- Enter/Escape/Tab funcionam;
- setas funcionam;
- Ctrl/Alt/Meta funcionam quando Android entrega;
- mouse relativo funciona com pointer capture;
- clique esquerdo/direito funcionam;
- drag funciona;
- scroll vertical funciona;
- disconnect não deixa tecla ou botão preso;
- input continua responsivo com vídeo em resolução alta.


---

<!-- FILE: 06-ANDROID-LIMITATIONS-AND-ROOT-PLAN.md -->

# 06 — Android Limitations and Root Plan

## Posição recomendada

Começar sem root é a abordagem correta.

Root deve ser fase posterior. O produto sem root valida a maior parte da arquitetura: vídeo, Tailscale, sessão, input básico, mouse, latência e UX. Se isso não funcionar bem, root não salvará o projeto; apenas adicionará complexidade.

## Limitações sem root

Sem root, o app Android opera depois da pilha de input do sistema. O app recebe apenas o que o Android decide entregar à Activity ou ao serviço autorizado.

### Limitações duras

| Tecla/comportamento | Sem root | Observação |
|---|---:|---|
| Home | Não confiável / normalmente impossível | Tecla de sistema. |
| Power | Não | Tecla de sistema. |
| Recents/Overview | Não confiável | Consumida pelo sistema/launcher. |
| Todos os atalhos Meta/Super | Não | Varia por Android/OEM/launcher. |
| Capturar input global em background | Não | Activity precisa estar focada, salvo casos de Accessibility. |
| Ler reports HID crus do Bluetooth | Não | Android entrega evento já processado. |
| Impedir Android de reagir a atalhos globais | Não | App comum não controla framework. |

### Limitações variáveis

| Área | Variação |
|---|---|
| Tecla Meta/Super | Pode chegar em alguns tablets e não em outros. |
| Teclas de função | Podem ser remapeadas por fabricante. |
| Layout ABNT2 | Pode depender do key layout Android. |
| Mouse extra buttons | Varia por device/OEM. |
| Pointer capture | Disponível em Android moderno, mas comportamento pode variar. |

## O que dá para fazer bem sem root

Sem root, ainda é possível entregar experiência útil:

- mouse relativo;
- cliques;
- drag;
- scroll;
- teclado alfanumérico;
- Enter/Escape/Tab/setas;
- modificadores comuns quando entregues;
- fullscreen immersive;
- sessão Tailnet;
- vídeo de alta qualidade;
- atalho parcial de Mac.

Isso basta para validar uso real em:

- Terminal;
- Finder;
- navegador;
- editor de texto;
- IDEs;
- apps de produtividade.

## Accessibility Assist

Accessibility pode ajudar, mas não substitui root nem garante captura total.

Uso recomendado:

```text
Modo Normal:
  Activity + pointer capture

Modo Assistido:
  AccessibilityService tenta filtrar eventos adicionais

Modo Pro Root:
  evdev cru
```

Não colocar Accessibility no caminho obrigatório porque:

- é permissão sensível;
- assusta usuário;
- pode afetar confiança;
- nem toda tecla passa;
- comportamento varia por OEM.

Estado implementado sem root:

- o app registra um `AccessibilityService` opcional;
- a permissão abre pelo painel Wireless do Android;
- o serviço solicita apenas filtro de teclas e não recupera conteúdo de janelas;
- eventos enviados por Accessibility usam flag própria no protocolo;
- a Activity evita mandar duplicatas quando o serviço já encaminhou a mesma tecla;
- se o usuário não habilitar Accessibility, o modo normal continua funcionando.

## Root muda o cenário

Com root, é possível mirar abaixo do framework Android:

```text
/dev/input/event*
  ↓
evdev raw events
  ↓
RemoteInputProtocol
  ↓
Mac Virtual HID
```

Isso pode permitir:

- capturar teclas antes do Android consumir;
- observar scancodes e keycodes de kernel;
- distinguir dispositivos;
- obter eventos mais próximos do hardware;
- resolver melhor Meta/Home/atalhos;
- implementar modo terminal mais fiel.

## Riscos do root

| Risco | Impacto |
|---|---|
| Instalação difícil | Usuário comum não usa. |
| Variação por fabricante | Implementação precisa ser robusta. |
| Segurança | App lendo input com root é sensível. |
| Atualizações de Android | Podem quebrar comportamento. |
| Distribuição | Não combina com Play Store tradicional. |
| Exclusive grab | Pode quebrar navegação local se mal implementado. |

## Plano de root posterior

### Pré-requisito

Só iniciar root depois que a Alpha sem root for utilizável.

Critérios para iniciar root:

- Tailnet funciona;
- vídeo estável;
- input channel separado;
- CGEvent fallback funcional;
- VirtualHID no Mac funcional ou em progresso;
- métricas de input implementadas;
- fail-safe de teclas implementado.

### Etapa Root 1 — discovery

- listar `/dev/input/event*`;
- identificar teclados e mouses;
- coletar capabilities;
- criar tela de diagnóstico;
- não interferir no input ainda.

### Etapa Root 2 — leitura passiva

- ler eventos crus;
- logar key down/up, mouse move, buttons, wheel;
- comparar com eventos recebidos pela Activity;
- mapear perdas do Android.

### Etapa Root 3 — envio remoto

- transformar evdev em `RemoteInputEvent`;
- enviar pelo mesmo protocolo de input;
- manter backend Activity como fallback.

### Etapa Root 4 — exclusive/grab opcional

- avaliar se faz sentido impedir o Android de consumir eventos locais;
- implementar modo claramente identificado;
- criar mecanismo de escape local;
- garantir que não prenda o usuário fora do tablet.

## Mecanismo de escape obrigatório no modo root

Se usar exclusive grab, precisa haver escape físico confiável.

Exemplos:

- toque com 4 dedos por 2 segundos;
- botão flutuante protegido;
- combinação específica não encaminhada ao Mac;
- timeout de segurança;
- desconectar mouse/teclado desativa grab.

Sem escape, não implementar grab.

## Recomendação final

A arquitetura deve nascer preparada para root, mas o produto deve nascer sem root.

```text
Agora:
  InputCaptureBackend abstraction
  ActivityKeyboardBackend
  PointerCaptureBackend

Depois:
  AccessibilityAssistBackend

Por último:
  RootEvdevBackend
```


---

<!-- FILE: 07-IMPLEMENTATION-ROADMAP.md -->

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


---

<!-- FILE: 08-CODEX-TASK-BACKLOG.md -->

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


---

<!-- FILE: 09-TEST-PLAN.md -->

# 09 — Test Plan

## Objetivo

Validar que o projeto entrega uma experiência de terminal remoto, não apenas vídeo remoto.

## Ambientes de teste

### Mac

Testar em pelo menos:

- Mac mini Apple Silicon;
- macOS alvo principal;
- um macOS imediatamente anterior se possível;
- monitor físico conectado e headless/semi-headless se aplicável.

### Android

Testar em pelo menos:

- tablet Android moderno;
- teclado Bluetooth comum;
- mouse Bluetooth comum;
- Tailscale Android atualizado;
- Wi-Fi fora da LAN do Mac;
- rede celular/hotspot se possível.

## Matriz de rede

| Caso | Esperado |
|---|---|
| USB existente | Continua funcionando. |
| LAN Wi-Fi | Continua funcionando. |
| Tailnet MagicDNS | Conecta sem bind Wi-Fi. |
| Tailnet IP 100.x | Conecta sem bind Wi-Fi. |
| MagicDNS falha | Mensagem clara e fallback para IP. |
| Tailscale desligado no Android | Erro claro. |
| Tailscale desligado no Mac | Timeout claro. |
| App excluído do split tunneling | Erro orienta verificar Tailscale Android. |
| Rede com alta latência | Vídeo reduzível, input ainda priorizado. |

## Testes de conexão Tailnet

### TN-001 — Conectar via MagicDNS

Passos:

1. Ativar Tailscale no Mac e Android.
2. Configurar MagicDNS host no Mac.
3. Gerar QR Tailnet.
4. Escanear no Android.
5. Conectar.

Aceite:

- Android conecta ao host `.ts.net`.
- Logs mostram modo Tailnet.
- Logs mostram que não houve `bindSocket` Wi-Fi.
- Vídeo aparece.
- Input channel conecta.

### TN-002 — Conectar via IP 100.x

Passos:

1. Configurar IP 100.x do Mac.
2. Gerar QR Tailnet.
3. Conectar pelo Android.

Aceite:

- Conexão funciona.
- Host persistido corretamente.
- Mensagem de UI mostra IP Tailnet.

### TN-003 — LAN não regrediu

Passos:

1. Colocar Android e Mac na mesma rede.
2. Usar QR LAN.
3. Conectar.

Aceite:

- Funcionamento igual ao SideScreen original.
- Workaround de bind Wi-Fi, se ainda existir, só é aplicado em modo LAN.

## Testes de vídeo

### VID-001 — Primeiro frame

Aceite:

- Primeiro frame aparece em tempo aceitável.
- Decoder recebe display config correto.
- Keyframe inicial é solicitado/entregue.

### VID-002 — Recovery por keyframe

Passos:

1. Conectar.
2. Forçar perda/restart do decoder ou alternar resolução.
3. Observar recuperação.

Aceite:

- Android pede keyframe.
- Mac responde.
- Vídeo volta sem reiniciar app.

### VID-003 — Carga alta

Passos:

1. Usar resolução alta.
2. Mover janelas rapidamente.
3. Observar latência.

Aceite:

- Frames atrasados são dropados.
- Input continua responsivo.
- Não há crescimento indefinido de fila.

## Testes de teclado sem root

### KEY-001 — Teclas comuns

Testar em TextEdit/Terminal:

- letras A-Z;
- números;
- espaço;
- Enter;
- Escape;
- Tab;
- Backspace;
- setas.

Aceite:

- Down/up corretos.
- Nenhuma tecla presa.

### KEY-002 — Modificadores

Testar:

- Shift + letra;
- Control + C em Terminal;
- Option + tecla, quando possível;
- Meta/Super como Command, quando Android entregar.
- Meta/Super com mapeamento Command, Option, Control e Off.

Aceite:

- Modificadores pressionam e soltam corretamente.
- Meta/Super segue o mapeamento escolhido no Android Settings.
- Se Meta chegar mas não for mapeado, o contador `unsupported` aumenta.
- Se Meta não chegar ao app, a UI mantém a limitação sem root visível em diagnóstico.

### KEY-003 — Stuck key fail-safe

Passos:

1. Pressionar e manter Shift/Command.
2. Desligar Wi-Fi/Tailscale ou matar app Android.
3. Observar Mac.

Aceite:

- Mac solta modificador automaticamente.
- Logs indicam release-all por disconnect.

### KEY-004 — Teclas de sistema Android

Testar:

- Home;
- Power;
- Recents;
- Meta/Super.

Aceite:

- App não promete sucesso.
- Diagnóstico registra eventos que chegaram como `captured` ou `unsupported`.
- Teclas que o Android não entrega continuam tratadas como limitação sem root, não como falha do protocolo.
- Falha não quebra sessão.

## Testes de mouse

### MOU-001 — Pointer capture

Passos:

1. Conectar mouse Bluetooth ao tablet.
2. Entrar no app remoto.
3. Ativar pointer capture.

Aceite:

- Mouse move o cursor do Mac de forma relativa.
- Cursor não fica limitado à borda do tablet.
- Há mecanismo de escape do capture.
- Sensibilidade de pointer no Android Settings altera o movimento enviado.

### MOU-002 — Botões

Testar:

- clique esquerdo;
- clique direito;
- clique do meio se houver;
- botão voltar/avançar se houver.

Aceite:

- Botões down/up preservados.
- Disconnect durante clique solta botão.

### MOU-003 — Drag

Passos:

1. Pressionar botão esquerdo.
2. Arrastar janela/seleção.
3. Soltar.

Aceite:

- Drag não falha.
- Nenhum mouse down fica preso.

### MOU-004 — Scroll

Testar:

- scroll vertical;
- scroll horizontal se mouse suportar;
- sensibilidade de scroll;
- direção natural configurável.

Aceite:

- Scroll funciona em navegador/Finder.
- Eventos não geram backlog.
- Natural scroll inverte vertical e horizontal de forma consistente.

## Testes de input sob carga

### LAT-001 — Input com vídeo pesado

Passos:

1. Rodar vídeo em resolução alta/FPS alto.
2. Digitar rapidamente no Terminal.
3. Mover mouse continuamente.

Aceite:

- Input não fica visivelmente atrás do vídeo.
- Teclado não perde key up.
- Mouse move continua suave.

### LAT-002 — Medição de input latency

Aceite:

- Android timestampa evento.
- Mac registra chegada.
- Mac registra dispatch ao backend.
- UI/log exibe último RTT, média e p95 do canal de input.

### LAT-003 — AllInputsUp com motivo

Passos:

1. Conectar input.
2. Perder pointer capture.
3. Sair do app.
4. Desconectar a sessão.

Aceite:

- Android envia `AllInputsUp` com motivo específico.
- Mac aceita payload legado vazio, mas registra o motivo quando presente.

## Testes de perfis e diagnóstico

### PROF-001 — Perfis de streaming no Mac

Passos:

1. Abrir Settings no Mac.
2. Selecionar Productivity, Low latency e Low bandwidth.
3. Observar resolução, FPS, bitrate e qualidade aplicados.
4. Alterar manualmente bitrate, qualidade, resolução, HiDPI ou FPS.

Aceite:

- Productivity aplica valores estáveis para texto e uso geral.
- Low latency aplica FPS alto e qualidade ultralow.
- Low bandwidth reduz resolução/FPS/bitrate para Tailnet ruim ou relay.
- Qualquer ajuste manual muda o perfil para Manual.
- Se o servidor estiver rodando, mudanças de resolução/FPS/HiDPI reiniciam o pipeline uma vez, de forma coalescida.

### DIAG-001 — Diagnóstico Android mostra últimos erros

Passos:

1. Gerar uma falha de conexão, token rejeitado ou timeout.
2. Abrir a aba Wireless.
3. Ler o card Connection Diagnostics.

Aceite:

- Card mostra endpoint, rota, estado do input e últimos erros relevantes.
- Em Tailnet, rota mostra transporte ativo e avisa se VPN/Tailscale não está ativo para o app.
- Erros comuns como failed, rejected, timeout e unreachable aparecem resumidos.
- Sem erro recente, a UI mostra `Recent errors: none`.

## Testes de lifecycle Android

### LIFE-001 — App perde foco

Passos:

1. Conectar.
2. Pressionar tecla/modificador.
3. Sair do app ou abrir recents.

Aceite:

- Android envia AllInputsUp se possível.
- Mac solta estado se canal cair.

### LIFE-002 — Tailscale alterna rede

Passos:

1. Conectar em Wi-Fi.
2. Trocar para hotspot/celular ou rede diferente.

Aceite:

- Sessão detecta queda.
- Reconexão não deixa estado preso.
- Mensagem é clara.

## Testes de segurança

### SEC-001 — Token inválido

Aceite:

- Mac rejeita.
- Android mostra re-pair.
- Nenhum vídeo/input começa.

### SEC-002 — Canal de input sem sessão

Aceite:

- Mac rejeita input channel não autenticado.
- Não há injeção de input sem auth.

### SEC-003 — Revogação futura

Aceite Alpha/Beta:

- Revogar device impede reconexão.
- QR novo reautoriza.

## Testes de permissões no Mac

### PERM-001 — Screen Recording ausente

Aceite:

- Host não inicia capture.
- UI pede permissão corretamente.

### PERM-002 — Accessibility/Input Monitoring ausente

Aceite:

- Vídeo pode funcionar.
- Input mostra erro específico.
- UI orienta o usuário.

### PERM-003 — VirtualHID indisponível

Aceite Alpha:

- Fallback para CGEvent.
- UI mostra backend ativo.


---

<!-- FILE: 10-RISKS-AND-OPEN-QUESTIONS.md -->

# 10 — Risks and Resolved Questions

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


---

<!-- FILE: 11-REMOTE-INPUT-PROTOCOL-V1.md -->

# 11 — Remote Input Protocol v1

Este documento especifica o protocolo conceitual de input para o projeto. Ele não exige que o MVP implemente todos os campos imediatamente, mas define a direção para evitar que o app fique preso a `Android KeyEvent`.

## Objetivos

O protocolo deve:

- ser independente do Android;
- representar input físico/HID-like;
- servir tanto para backend sem root quanto para backend root futuro;
- funcionar com CGEvent fallback e Virtual HID no Mac;
- preservar ordem de teclado/botões;
- permitir coalescing seguro de mouse move;
- permitir diagnóstico de latência;
- suportar versionamento.

## Não-objetivos

O protocolo v1 não precisa:

- resolver todos os layouts de teclado;
- transportar áudio;
- transportar clipboard;
- multiplexar vídeo;
- substituir autenticação/sessão.

## Camadas

```text
Transport frame
  ↓
RemoteInputEnvelope
  ↓
Event payload
```

O transport frame pertence ao canal de rede. O envelope pertence ao protocolo de input.

## Convenções

- Inteiros little-endian, para consistência com o protocolo atual do SideScreen.
- Timestamps monotônicos em nanossegundos no Android.
- Sequence number por canal de input, crescente.
- Versão explícita no handshake do canal de input.
- Mensagens pequenas, sem compressão.

## Handshake do canal de input

Antes de enviar eventos, o Android deve abrir o canal e declarar capabilities.

Campos conceituais:

```text
InputChannelHello
  magic: "RMIP"
  versionMajor: 1
  versionMinor: 0
  sessionId
  deviceId
  capabilitiesBitmap
  preferredKeyboardLayout
  pointerCapabilities
```

Capabilities iniciais:

```text
CAP_KEYBOARD_ACTIVITY
CAP_POINTER_CAPTURE
CAP_GENERIC_MOTION
CAP_TOUCH_ABSOLUTE
CAP_ACCESSIBILITY_ASSIST
CAP_ROOT_EVDEV
CAP_TEXT_COMMIT
CAP_HID_USAGE_MAPPING
```

Resposta do Mac:

```text
InputChannelAccept
  magic: "RMIA"
  acceptedVersionMajor
  acceptedVersionMinor
  backendActive: cgevent | virtualhid | none
  serverCapabilitiesBitmap
```

Se sessão inválida:

```text
InputChannelReject
  reason
```

## Envelope de evento

Todos os eventos devem carregar metadados comuns:

```text
RemoteInputEnvelope
  eventType: UInt8
  sequence: UInt64
  androidTimestampNanos: UInt64
  payloadLength: UInt16
  payload
```

O header binário tem 19 bytes:

```text
1 eventType
8 sequence
8 androidTimestampNanos
2 payloadLength
```

### eventType

```text
0x01 KeyboardKey
0x02 TextCommit
0x10 PointerRelative
0x11 PointerButton
0x12 PointerWheel
0x13 PointerAbsolute
0x20 AllInputsUp
0x30 InputPing
0x31 InputPong
0x7F ProtocolError
```

## KeyboardKey

Payload conceitual:

```text
KeyboardKey
  action: down | up
  usagePage
  usageId
  scanCode
  androidKeyCode
  location
  repeatCount
  modifiersSnapshot
  flags
```

### action

```text
0 down
1 up
```

### location

```text
0 standard
1 left
2 right
3 numpad
```

### flags

```text
FLAG_FROM_ACTIVITY
FLAG_FROM_ACCESSIBILITY
FLAG_FROM_ROOT
FLAG_SYNTHETIC_RELEASE
FLAG_CANCELED
```

### Regras

- O Mac deve tratar `usagePage + usageId + location` como identidade primária quando disponível.
- `androidKeyCode` é metadata/fallback, não identidade principal final.
- Teclado não pode ser coalescido.
- Se o Mac receber down repetido sem up, deve tratar como repeat ou estado duplicado, não duplicar pressed state.
- Se o Mac receber up de tecla não pressionada, deve logar e ignorar com segurança.

## TextCommit

Payload conceitual:

```text
TextCommit
  utf8ByteLength
  utf8Text
```

Uso:

- texto composto;
- caracteres que não mapeiam bem para tecla física;
- fallback para IME.

Não usar para hotkeys.

## PointerRelative

Payload conceitual:

```text
PointerRelative
  dx
  dy
  unit
  flags
```

### unit

```text
0 pixelLike
1 deviceUnit
2 highResolutionDeviceUnit
```

### flags

```text
FLAG_FROM_POINTER_CAPTURE
FLAG_FROM_GENERIC_MOTION
FLAG_ACCELERATION_ALREADY_APPLIED
```

### Regras

- Pode ser coalescido com outros `PointerRelative` consecutivos.
- Não pode atravessar `PointerButton`, `PointerWheel`, `KeyboardKey` ou `AllInputsUp`.
- Se pointer capture for perdido, Android deve enviar `AllInputsUp` ou evento de estado equivalente.

## PointerButton

Payload conceitual:

```text
PointerButton
  action: down | up
  button
  flags
```

### button

```text
0 left
1 right
2 middle
3 back
4 forward
5 extra1
6 extra2
```

### Regras

- Não coalescer.
- Mac mantém pressedButtons.
- Disconnect deve soltar botões.

## PointerWheel

Payload conceitual:

```text
PointerWheel
  deltaX
  deltaY
  unit
  flags
```

### unit

```text
0 line
1 pixel
2 highResolution
```

### Regras

- Pode ser acumulado em janelas muito pequenas apenas se não houver botão/teclado entre eventos.
- Preservar horizontal scroll.
- Direção natural deve ser preferência, não hard-coded.

## PointerAbsolute

Payload conceitual:

```text
PointerAbsolute
  action: down | move | up | cancel
  pointerId
  pointerCount
  xNormalized
  yNormalized
  pressure optional
  source
```

### source

```text
0 touch
1 stylus
2 absoluteMouse
```

### Regras

- Usar para touch/stylus.
- Não usar para mouse Bluetooth relativo.
- Touch e mouse devem ser modos separados.

## AllInputsUp

Payload conceitual:

```text
AllInputsUp
  reason
```

### reason

```text
0 explicitUserAction
1 androidLifecyclePause
2 pointerCaptureLost
3 inputBackendSwitch
4 networkDisconnect
5 protocolError
6 watchdogTimeout
```

### Regras

- Mac deve soltar todas as teclas e botões pressionados.
- Deve cancelar drag.
- Deve resetar modificadores.
- Deve registrar métrica.

Implementação sem-root atual:

- Android envia `reason` em lifecycle pause, perda de pointer capture, ação explícita e disconnect.
- Mac aceita payload legado vazio como `explicitUserAction`, mas registra motivo quando recebido.

## Ping/Pong de input

Separado do ping de vídeo/sessão.

```text
InputPing
  clientTimestampNanos

InputPong
  clientTimestampNanos
  serverTimestampNanos
```

Uso:

- manter o canal de input vivo;
- impedir que o watchdog do Mac solte teclas/botões durante um hold legítimo;
- medir latência específica do canal de input;
- não misturar com frame latency.

Implementação sem-root atual:

- Android envia `InputPing` a cada 2s enquanto o canal de input está aceito.
- Mac trata `InputPing` como sinal de vida e rearma o watchdog.
- Mac responde `InputPong` com timestamp do cliente e timestamp do servidor.
- Android calcula e mostra RTT específico do canal de input com último valor, média e p95.

## Compatibilidade com MVP

O MVP pode começar com subconjunto:

```text
KeyboardKey
PointerRelative
PointerButton
PointerWheel
AllInputsUp
InputPing
```

Campos opcionais podem ser zero/default.

Não adiar sequence/timestamp: eles são baratos e importantes.

## Mapeamento Android → protocolo

### Activity backend

```text
KeyEvent.action      → KeyboardKey.action
KeyEvent.scanCode    → scanCode
KeyEvent.keyCode     → androidKeyCode
KeyEvent.metaState   → modifiersSnapshot
KeyEvent.repeatCount → repeatCount
```

`usageId` pode vir de tabela inicial de mapping.

### Pointer capture backend

```text
MotionEvent relative axes → PointerRelative
MotionEvent button state  → PointerButton diff
MotionEvent scroll axes   → PointerWheel
```

## Mapeamento protocolo → Mac

### CGEventBackend

```text
KeyboardKey   → CGEvent keyboard event
PointerRelative → CGEvent mouse move relative/absolute via accumulated cursor position
PointerButton → CGEvent mouse down/up
PointerWheel  → CGEvent scrollWheel
AllInputsUp   → synthesize key/button releases
```

### VirtualHIDBackend

```text
KeyboardKey   → HID keyboard report
PointerRelative → HID mouse report dx/dy
PointerButton → HID mouse button report
PointerWheel  → HID wheel report
AllInputsUp   → zeroed keyboard/mouse reports
```

## Erros de protocolo

Mac deve rejeitar:

- versão incompatível;
- payload length inválido;
- event type desconhecido sem capability;
- sequence muito fora de ordem;
- canal sem sessão válida.

Em erro fatal:

1. enviar `ProtocolError` se possível;
2. chamar release-all;
3. fechar canal de input;
4. manter vídeo vivo se a sessão geral continuar válida.

## Observabilidade mínima

Logar em modo debug:

- first input event;
- lost sequence;
- duplicate sequence;
- release-all;
- backend ativo;
- pointer capture lost;
- key up sem key down;
- key down duplicado;
- latência média/p95 do input.


---

<!-- FILE: 12-SESSION-AND-TRANSPORT-SPEC.md -->

# 12 — Session and Transport Spec

## Objetivo

Definir como o projeto deve evoluir de conexão SideScreen legacy para sessões remotas com múltiplos canais.

## Estado atual do SideScreen

O SideScreen atual tem um `StreamingServer` TCP que carrega:

- auth wireless;
- display config;
- vídeo;
- touch;
- ping/pong;
- keyframe request;
- codec negotiation.

Isso é suficiente para segundo display em LAN/USB, mas não ideal para terminal remoto pela internet.

## Objetivo final

Separar sessão e canais:

```text
Session
  ├─ Control channel
  ├─ Video channel
  ├─ Input channel
  └─ Telemetry channel opcional
```

## Estratégia de migração

### Fase 1 — compatibilidade

Manter `StreamingServer` existente para vídeo/control legacy e adicionar `InputServer` separado.

```text
port P:
  StreamingServer legacy

port P+1:
  InputServer MVP
```

Vantagem: menor risco.

Desvantagem: duas portas.

### Fase 2 — single-port multi-channel

Um listener aceita múltiplas conexões. Cada conexão começa com preamble que indica canal.

```text
port P:
  connection A → control
  connection B → video
  connection C → input
```

Vantagem: uma porta, arquitetura limpa.

Desvantagem: refactor maior.

### Fase 3 — QUIC opcional

Migrar para QUIC só se medições mostrarem necessidade.

Possíveis ganhos:

- streams independentes;
- menor head-of-line entre streams;
- reconexão melhor;
- suporte natural a datagrams em versões futuras.

Custos:

- dependência extra;
- maior complexidade;
- integração Swift/Kotlin mais trabalhosa;
- debug mais difícil.

## Sessão

### Conceitos

```text
Pairing:
  ato de autorizar um tablet

Device:
  tablet autorizado persistentemente

Session:
  conexão atual autenticada

Channel:
  fluxo específico dentro de uma sessão
```

## Pairing MVP

Reaproveitar token atual:

```text
QR contém token de 32 bytes
Android envia token no handshake
Mac valida
```

Limitação conhecida: token é bearer token persistente.

## Pairing Alpha

Evoluir para:

```text
QR contém pairingSecret temporário
Android gera deviceId e deviceKey
Mac registra deviceId/deviceKey
sessões futuras usam challenge-response
```

## Session handshake Alpha

Fluxo conceitual:

```text
Android → Mac: ClientHello
  protocolVersion
  deviceId
  nonceClient
  capabilities

Mac → Android: ServerChallenge
  nonceServer
  sessionId
  acceptedCapabilities

Android → Mac: ClientAuth
  HMAC(deviceKey, nonceClient|nonceServer|sessionId|capabilities)

Mac → Android: SessionAccept
  sessionId
  channelPolicy
```

## Channel authorization

Cada canal deve provar que pertence à sessão:

```text
ChannelHello
  sessionId
  channelType
  channelNonce
  authTag
```

Canal inválido deve ser rejeitado antes de processar payload.

## Channel types

```text
CONTROL
VIDEO
INPUT
TELEMETRY
```

### CONTROL

- lifecycle;
- display config;
- codec negotiation;
- session keepalive;
- reconnect;
- errors.

### VIDEO

- frames;
- frame metadata;
- keyframe request;
- codec selected;
- bitrate hints.

### INPUT

- input protocol v1;
- input ping/pong;
- all-inputs-up.

### TELEMETRY

Opcional:

- logs compactos;
- FPS;
- frame age;
- input latency;
- route diagnostics.

## Ordem de prioridade

```text
INPUT > CONTROL > VIDEO > TELEMETRY
```

Se houver pressão de CPU/rede, vídeo deve degradar antes do input.

## Backpressure

### Vídeo

- drop de frames permitido;
- priorizar frame recente;
- keyframe recovery;
- não acumular fila.

### Input

- não dropar key/button up/down;
- mouse move pode ser coalescido;
- telemetry pode ser dropada.

## Reconnect

MVP:

- reconectar tudo de forma simples;
- soltar input em disconnect;
- pedir keyframe ao voltar.

Alpha:

- session resume;
- novo video channel pode reassociar à sessão;
- input channel sempre começa com estado limpo.

## Timeouts sugeridos

Valores iniciais, ajustar com medição:

```text
TCP connect timeout: 5s
Input heartbeat: 2s
Input idle watchdog: 5s para release-all se canal morrer sem close
Control heartbeat: 5s
Video keyframe freshness: manter lógica atual como base
```

## Erros

Erros devem ser específicos:

```text
AUTH_INVALID_TOKEN
AUTH_DEVICE_REVOKED
SESSION_EXPIRED
CHANNEL_UNAUTHORIZED
TAILNET_DNS_FAILED
TAILNET_CONNECT_TIMEOUT
INPUT_PROTOCOL_ERROR
VIDEO_DECODER_NEEDS_KEYFRAME
```

## Compatibilidade com protocolo atual

Durante a migração:

- manter mensagens legacy do SideScreen para vídeo;
- adicionar modo/protocolo novo apenas quando cliente e servidor anunciarem capability;
- evitar quebrar APK/host antigo durante desenvolvimento local se possível.

## Critérios de aceite da Fase 1

- vídeo legacy continua funcionando;
- input channel separado conecta e desconecta sem travar vídeo;
- input channel é autenticado de alguma forma mínima;
- disconnect do input não deixa teclas presas;
- disconnect do vídeo não deixa input em estado indefinido;
- logs identificam channel e session.


---

<!-- FILE: 13-SECURITY-MODEL.md -->

# 13 — Security Model

## Objetivo

O app permite controlar um Mac remotamente. Isso é sensível. Mesmo usando Tailscale, o app precisa de autenticação própria, revogação e boas práticas de sessão.

## Modelo de ameaça

### Ativos protegidos

- controle de teclado/mouse do Mac;
- conteúdo do display remoto;
- tokens/chaves de pareamento;
- identidade do tablet;
- sessão ativa;
- logs que podem conter dados sensíveis.

### Atores

```text
Usuário legítimo
  possui Mac e tablet na Tailnet

Dispositivo não autorizado na Tailnet
  consegue alcançar IP/porta, mas não deve controlar Mac

Pessoa com QR antigo
  pode ter capturado token bearer legacy

App Android comprometido
  pode tentar enviar input malicioso

Rede não confiável fora da Tailnet
  mitigada em grande parte pelo Tailscale
```

## Camadas

```text
Tailscale
  restringe quem alcança o endpoint de rede

Application authentication
  restringe quem pode iniciar sessão no app

Session authorization
  restringe quais canais pertencem a uma sessão válida

Input safety
  impede estado preso e comportamento inseguro
```

## MVP

MVP pode reaproveitar token atual de 32 bytes, com cuidados:

- não logar token;
- não mostrar token completo na UI;
- QR deve poder ser resetado;
- conexões non-loopback sem token devem ser rejeitadas;
- input channel deve exigir token/sessão, não aceitar input anônimo.
- Android não deve incluir pairing token/device secret em backup automático do sistema.

## Alpha

Introduzir device registry:

```text
DeviceRecord
  deviceId
  displayName
  public identifier
  sharedSecret ou publicKey
  createdAt
  lastSeenAt
  revoked
```

Fluxo:

1. QR cria pairing temporário.
2. Android gera deviceId e segredo/chave.
3. Mac registra dispositivo.
4. Sessões futuras usam challenge-response.
5. Usuário pode revogar dispositivo.

## Session security

Sessão deve ter:

- sessionId aleatório;
- nonce do cliente;
- nonce do servidor;
- auth tag;
- expiração;
- channel authorization.

## Channel security

Cada canal deve provar sessão válida.

MVP mínimo:

- input channel só abre após vídeo/control autenticado;
- ou input channel repete token legacy;
- ou input channel recebe session token temporário do control channel.

Recomendação MVP:

```text
Após auth wireless OK no canal principal:
  Mac gera sessionToken temporário
  Android usa sessionToken para abrir InputServer
```

Se isso for muito grande, repetir token legacy no input channel é aceitável apenas no MVP inicial.

## Revogação

Exigências Alpha:

- revogar um dispositivo;
- resetar todos os dispositivos;
- expirar pairing QR;
- invalidar sessões ativas de dispositivo revogado.

## Logs

Não logar:

- tokens;
- auth tags completos;
- texto digitado;
- conteúdo de clipboard futuro;
- screenshots.

Logar com segurança:

- device name;
- últimos 4 caracteres de deviceId;
- endpoint mode;
- erro de auth sem segredo;
- latência;
- codec;
- input event type, não caractere.

## Permissões macOS

O host pode exigir:

- Screen Recording;
- Accessibility;
- Input Monitoring;
- Driver/system extension se VirtualHID.

UI deve explicar cada uma.

## Segurança do modo root Android futuro

Root backend é sensível porque pode ler todos os eventos de teclado/mouse do tablet.

Regras:

- root deve ser opt-in;
- mostrar aviso claro;
- não ativar automaticamente;
- permitir desligar;
- logs não devem gravar texto digitado;
- exclusive grab exige mecanismo de escape.

## Fail-safe de input como requisito de segurança

Stuck keys podem causar ações destrutivas no Mac.

Requisito:

```text
Qualquer falha de sessão/canal deve soltar todos os inputs.
```

Isso é requisito de segurança, não apenas UX.

## Hardening futuro

- usar chaves assimétricas por device;
- pinning de device identity;
- encrypted app-level payload opcional apesar de Tailscale;
- logs estruturados com redaction;
- modo read-only video sem input;
- prompt no Mac para aceitar novo device;
- rate limit de tentativas de auth.


---

<!-- FILE: 14-DOCUMENTATION-COVERAGE-AND-STATUS.md -->

# 14 — Documentation Coverage and Status

Data: 2026-07-01

Este documento fecha a documentação da spec. "100%" aqui significa cobertura documental completa do produto atual: o que existe, onde está descrito, como validar, o que ainda é futuro e qual arquivo usar para implementar sem chute.

Não significa que o produto final está 100% pronto. Significa que a documentação não deixa buraco conceitual relevante para continuar o desenvolvimento.

## Mapa de cobertura

| Área | Status da documentação | Fonte principal | Evidência no código/projeto |
| --- | --- | --- | --- |
| Objetivo de produto | Completo | `01-PROJECT-BRIEF.md` | README principal e fluxo Mac/Android existentes |
| Arquitetura macro | Completo | `03-TARGET-ARCHITECTURE.md` | `MacHost/Sources/*`, `AndroidClient/app/src/main/java/com/sidescreen/app/*` |
| Reuso do vídeo SideScreen | Completo | `02-SIDESCREEN-DEEP-DIVE.md`, ADR-0002 | `VirtualDisplayManager.swift`, `ScreenCapture.swift`, `VideoEncoder.swift`, `VideoDecoder.kt` |
| Tailnet/LAN/manual | Completo | `04-TAILSCALE-NETWORKING-SPEC.md` | `EndpointMode.swift`, `EndpointMode.kt`, `EndpointAdvertiser.swift`, `NetworkRoute.kt` |
| Pareamento e sessão | Completo | `12-SESSION-AND-TRANSPORT-SPEC.md`, `13-SECURITY-MODEL.md` | `WirelessAuth.swift`, `AuthHandshake.kt`, `RemoteSessionStore.swift` |
| Canal dedicado de input | Completo | `05-INPUT-ARCHITECTURE-SPEC.md`, `11-REMOTE-INPUT-PROTOCOL-V1.md` | `InputServer.swift`, `InputClient.kt` |
| Protocolo de input v1 | Completo | `11-REMOTE-INPUT-PROTOCOL-V1.md` | `RemoteInputProtocol.swift`, `RemoteInputProtocol.kt` |
| Fail-safe de input | Completo | `05-INPUT-ARCHITECTURE-SPEC.md`, `13-SECURITY-MODEL.md` | `InputIngress.swift`, `CGEventInputBackend.swift`, `KarabinerVirtualHIDBackend.swift` |
| CGEvent fallback | Completo | `05-INPUT-ARCHITECTURE-SPEC.md`, ADR-0006 | `CGEventInputBackend.swift` |
| Virtual HID | Completo | `05-INPUT-ARCHITECTURE-SPEC.md`, ADR-0006 | `KarabinerVirtualHIDBackend.swift`, `VirtualHIDHelperInstaller.swift`, `VirtualHIDHelperSources/main.swift` |
| Android sem root | Completo | `06-ANDROID-LIMITATIONS-AND-ROOT-PLAN.md` | `InputClient.kt`, `RemoteInputBridge.kt`, `SideScreenAccessibilityService.kt` |
| Accessibility assist | Completo | `06-ANDROID-LIMITATIONS-AND-ROOT-PLAN.md` | `SideScreenAccessibilityService.kt`, `RemoteInputBridge.kt` |
| Diagnóstico operacional | Completo | `07-IMPLEMENTATION-ROADMAP.md`, `09-TEST-PLAN.md` | `DiagLog.kt`, `TailnetDiagnostics.swift`, `scripts/collect-qa-evidence.sh` |
| Testes automatizados | Completo | `09-TEST-PLAN.md` | `MacHost/Tests/SideScreenTests/*`, `AndroidClient/app/src/test/*` |
| QA manual diário | Completo | `09-TEST-PLAN.md` | `../../DAILY_USE_QA.md`, `../../qa-evidence/*` |
| Riscos e decisões | Completo | `10-RISKS-AND-OPEN-QUESTIONS.md`, `adr/*` | ADRs 0001-0006 |
| Estrutura sugerida | Completo | `appendix/C-SUGGESTED-PROJECT-STRUCTURE.md` | Estrutura atual já segue boa parte da divisão sugerida |

## Estado implementado

| Marco | Estado | Notas práticas |
| --- | --- | --- |
| Tailnet endpoint support | Implementado | QR e parser têm modo de endpoint; Tailnet não deve prender socket em Wi-Fi. |
| Input channel separado | Implementado | Input usa porta dedicada no MVP e `TCP_NODELAY`. |
| Remote Input Protocol v1 | Implementado | Envelope com tipo, sequência, timestamp e payload; inclui ping/pong de latência. |
| Teclado sem root | Implementado | Activity/Accessibility enviam eventos mapeados para HID usage quando Android entrega a tecla. |
| Mouse sem root | Implementado | Movimento relativo, botões e wheel; pointer capture é o caminho preferido. |
| `TextCommit` | Implementado | Cobre IME/dead keys sem logar texto digitado. |
| `AllInputsUp` com motivo | Implementado | Usado em disconnect, lifecycle, perda de pointer capture e troca de backend. |
| CGEvent backend | Implementado | Fallback inicial e caminho de compatibilidade. |
| Virtual HID | Implementado | Suporta Karabiner VirtualHID direto quando possível e helper privilegiado do SideScreen. |
| Device registry/revogação | Implementado | Existe store de dispositivos pareados/revogados no Mac. |
| Diagnóstico Mac/Android | Implementado | Diagnósticos cobrem endpoint, rota, input, permissões, logs e erros recentes. |
| Evidence collection | Implementado | Scripts coletam preflight, artefatos, Tailnet, assinatura, testes e smoke Android. |
| Root backend | Futuro intencional | A spec cobre plano e limites; não deve virar requisito do MVP. |
| QUIC/single-port final | Futuro condicional | Só entra se medições reais mostrarem que TCP multi-channel é gargalo. |

## Fluxo atual

```text
Android tablet
  captura Activity / pointer capture / Accessibility assist
  gera Remote Input Protocol v1
  envia input por canal dedicado
        |
        v
MacHost InputServer
  valida token/sessão/dispositivo
  passa por InputIngress
  coalesce mouse move
  rastreia teclas/botões pressionados
  solta tudo em falha
        |
        v
Input backend
  Virtual HID quando pronto
  CGEvent como fallback
```

## O que ainda é futuro, sem fingimento

| Item | Por que não bloqueia 100% da documentação | Próximo passo correto |
| --- | --- | --- |
| Root no Android | Está documentado como backend opcional posterior, com riscos e escape. | Fazer discovery passivo antes de qualquer envio remoto. |
| DriverKit próprio | Existe alternativa prática com Karabiner/SideScreen helper. | Só justificar se instalação/controle exigirem. |
| QUIC | TCP com canais separados já cobre o desenho atual. | Medir latência/queda em rede real antes de trocar transporte. |
| ABNT2 perfeito | Layout depende de teclado, Android e mapeamento físico. | Ampliar testes reais e tabela de key mapping. |
| Installer polido | Arquitetura e permissões estão documentadas. | Transformar onboarding/installer em tarefa de produto. |
| Áudio/clipboard/multimonitor/file drop | São extras, não fazem parte do terminal remoto mínimo. | Tratar cada um como epic separado depois da base estável. |

## Regra de leitura para próximas sessões

Use esta ordem:

1. `README.md`
2. `00-CODEX-START-HERE.md`
3. `14-DOCUMENTATION-COVERAGE-AND-STATUS.md`
4. `07-IMPLEMENTATION-ROADMAP.md`
5. `08-CODEX-TASK-BACKLOG.md`
6. O documento específico da área que será alterada

Se houver conflito entre um backlog antigo e este documento, este documento vence para status atual. O backlog continua útil como decomposição de trabalho, não como retrato fiel do que ainda falta.

## Critério de "documentação 100%"

A documentação está 100% quando uma pessoa consegue responder, sem ler o código inteiro:

- o que o produto quer ser;
- quais decisões arquiteturais já foram tomadas;
- quais partes do SideScreen são reaproveitadas;
- como Tailnet, LAN e manual diferem;
- como o input sai do Android e entra no Mac;
- como a sessão protege o canal de input;
- quais backends existem no Mac;
- o que acontece quando uma conexão cai;
- o que é limitação real do Android sem root;
- quais testes e evidências validam o sistema;
- quais itens são futuro deliberado, não buraco esquecido.

Com este arquivo, essa lista está coberta.


---

<!-- FILE: adr/ADR-0001-start-without-root.md -->

# ADR-0001 — Começar sem root

## Status

Aceita.

## Contexto

O objetivo final é chegar o mais próximo possível de um terminal remoto real para Mac. Root no Android permitiria capturar input em camada muito mais baixa, mas aumenta drasticamente complexidade, risco, segurança e dificuldade de distribuição.

## Decisão

A primeira implementação será sem root.

O app deve ser desenhado com abstração de backends de input para permitir root futuramente, mas nenhuma funcionalidade crítica do MVP dependerá de root.

## Consequências

### Positivas

- Desenvolvimento inicial mais rápido.
- Menos risco operacional.
- Valida vídeo, Tailnet, sessão e input básico.
- Mantém caminho para distribuição normal.
- Evita misturar problema de produto com problema de root.

### Negativas

- Algumas teclas de sistema não serão capturáveis.
- Meta/Super/Home podem continuar problemáticos.
- Experiência não será 100% terminal na primeira fase.

## Implicação arquitetural

Criar:

```text
InputCaptureBackend
  ActivityKeyboardBackend
  PointerCaptureBackend
  AccessibilityAssistBackend futuro
  RootEvdevBackend futuro
```


---

<!-- FILE: adr/ADR-0002-reuse-sidescreen-video-engine.md -->

# ADR-0002 — Reaproveitar motor de vídeo do SideScreen

## Status

Aceita.

## Contexto

O SideScreen já implementa Virtual Display, ScreenCaptureKit, VideoToolbox, HEVC/H.264 e MediaCodec com baixa latência.

O problema principal do novo projeto é input e sessão, não vídeo.

## Decisão

Reaproveitar o motor de vídeo do SideScreen e refatorar ao redor dele, em vez de reescrever vídeo do zero.

## Consequências

### Positivas

- Economiza meses de trabalho.
- Mantém pipeline validado.
- Preserva funcionalidades difíceis: HiDPI, codec negotiation, keyframe recovery, fallback de captura.

### Negativas

- Carrega alguma dívida técnica.
- `AppDelegate`/`MainActivity` atuais são monolíticos.
- `CGVirtualDisplay` usa API privada.

## Implicação arquitetural

Extrair ou encapsular:

```text
VirtualDisplayService
CaptureService
EncodeService
VideoTransport
MediaCodecRenderer
```


---

<!-- FILE: adr/ADR-0003-tailscale-as-network-underlay.md -->

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


---

<!-- FILE: adr/ADR-0004-separate-input-from-video.md -->

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


---

<!-- FILE: adr/ADR-0005-use-hid-like-input-protocol.md -->

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


---

<!-- FILE: adr/ADR-0006-cgevent-first-virtualhid-second.md -->

# ADR-0006 — CGEvent primeiro, Virtual HID depois

## Status

Aceita.

## Contexto

Virtual HID é tecnicamente superior para experiência de Mac nativo, mas exige driver/system extension e mais atrito. CGEvent já é usado no SideScreen para mouse/touch e permite validar a arquitetura de input rapidamente.

## Decisão

Usar CGEvent como backend inicial/MVP. Integrar Karabiner VirtualHID na Alpha. Considerar DriverKit próprio apenas no futuro.

## Consequências

### Positivas

- MVP mais rápido.
- Menos dependências no início.
- Valida protocolo e canal antes do driver.

### Negativas

- CGEvent não é input físico real.
- Alguns apps/contextos podem se comportar diferente.
- Permissões ainda são necessárias.

## Implicação arquitetural

Criar abstração:

```text
InputBackend
  CGEventBackend
  KarabinerVirtualHIDBackend
  DriverKitOwnBackend futuro
```


---

<!-- FILE: appendix/A-SIDESCREEN-CODE-REFERENCE.md -->

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


---

<!-- FILE: appendix/B-EXTERNAL-REFERENCES.md -->

# Appendix B — External References

Referências úteis para continuar o projeto. Todas foram consultadas/revisadas em 2026-06-30.

## Tailscale

### MagicDNS

URL: https://tailscale.com/docs/features/magicdns

Relevância:

- MagicDNS registra nomes DNS para dispositivos na Tailnet;
- deve ser a forma preferida de UX para conectar ao Mac mini.

### DNS in Tailscale

URL: https://tailscale.com/docs/reference/dns-in-tailscale

Relevância:

- explica como MagicDNS atribui nomes a dispositivos;
- confirma que MagicDNS é opcional, mas útil.

### Tailscale IP addresses

URL: https://tailscale.com/docs/concepts/tailscale-ip-addresses

Relevância:

- dispositivos recebem IPs 100.x.y.z;
- IP 100.x é bom como fallback/manual.

### IP and DNS addresses

URL: https://tailscale.com/docs/concepts/ip-and-dns-addresses

Relevância:

- descreve atribuição de IPs 100.x;
- útil para documentação de setup.

### Connect to devices

URL: https://tailscale.com/docs/how-to/connect-to-devices

Relevância:

- recomenda conectar por nome/MagicDNS ou IP Tailscale + porta.

### Connection types / DERP

URL: https://tailscale.com/docs/reference/connection-types

Relevância:

- Tailscale pode usar conexão direta ou relayed;
- direct connection não é garantida;
- relay pode afetar latência.

### DERP servers

URL: https://tailscale.com/docs/reference/derp-servers

Relevância:

- DERP ajuda NAT traversal e funciona como fallback;
- importante para diagnóstico de latência.

### Android app split tunneling

URL: https://tailscale.com/docs/features/client/android-app-split-tunneling

Relevância:

- no Android, app pode ser incluído/excluído da Tailnet;
- se o cliente for excluído, MagicDNS/IP 100.x podem falhar.

### Tailscale CLI

URL: https://tailscale.com/docs/reference/tailscale-cli

Relevância:

- no Mac pode ajudar a descobrir IP 100.x;
- não deve ser requisito do MVP.

## Android input

### Pointer capture / movement

URL: https://developer.android.com/develop/ui/views/touch-and-input/gestures/movement

Relevância:

- documenta `requestPointerCapture` e `onCapturedPointerEvent`;
- base para mouse relativo no tablet.

### View API — onCapturedPointerEvent

URL: https://developer.android.com/reference/android/view/View

Relevância:

- referência de API para eventos capturados.

### AccessibilityServiceInfo

URL: https://developer.android.com/reference/android/accessibilityservice/AccessibilityServiceInfo

Relevância:

- base para avaliar `FLAG_REQUEST_FILTER_KEY_EVENTS`;
- Accessibility pode ajudar, mas não deve ser backend principal.

### Android KeyEvent

URL: https://developer.android.com/reference/android/view/KeyEvent

Relevância:

- explica action down/up/repeat/metaState;
- usar como input source sem root, mas não como protocolo final.

### AOSP input overview

URL: https://source.android.com/docs/core/interaction/input

Relevância:

- descreve pipeline input driver/evdev/EventHub/InputReader/InputDispatcher;
- justifica por que `KeyEvent` é pós-framework.

### AOSP getevent

URL: https://source.android.com/docs/core/interaction/input/getevent

Relevância:

- útil para root backend futuro;
- mostra eventos crus do kernel.

### Android KeyEvent source

URL: https://android.googlesource.com/platform/frameworks/base/+/master/core/java/android/view/KeyEvent.java

Relevância:

- útil para entender teclas de sistema e comportamento de códigos.

## macOS input

### CGEvent

URL: https://developer.apple.com/documentation/coregraphics/cgevent

Relevância:

- base para fallback de injeção sintética.

### CGEvent.post(tap:)

URL: https://developer.apple.com/documentation/coregraphics/cgevent/post%28tap%3A%29

Relevância:

- usado pelo SideScreen para postar eventos em `.cghidEventTap`.

### AXIsProcessTrustedWithOptions

URL: https://developer.apple.com/documentation/applicationservices/1460720-axisprocesstrustedwithoptions

Relevância:

- permissões de Accessibility necessárias para automação/input sintético.

### HIDDriverKit

URL: https://developer.apple.com/documentation/hiddriverkit

Relevância:

- framework oficial para drivers HID via DriverKit;
- opção final, não MVP.

### Creating virtual devices / CoreHID

URL: https://developer.apple.com/documentation/corehid/creatingvirtualdevices

Relevância:

- Apple documenta conceito de dispositivo HID virtual;
- investigar compatibilidade e entitlements antes de escolher.

### HIDVirtualDevice

URL: https://developer.apple.com/documentation/corehid/hidvirtualdevice

Relevância:

- possível alternativa moderna para virtual HID;
- precisa investigação prática.

### DriverKit virtual HID entitlement

URL: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.hid.virtual.device

Relevância:

- virtual HID exige entitlement; impacta distribuição.

## Karabiner VirtualHID

### Karabiner-DriverKit-VirtualHIDDevice

URL: https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice

Relevância:

- implementa teclado e mouse virtuais usando DriverKit;
- reconhecido pelo macOS como hardware físico;
- melhor backend prático para Alpha.

### Releases

URL: https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases

Relevância:

- acompanhar versões e mudanças de compatibilidade.


---

<!-- FILE: appendix/C-SUGGESTED-PROJECT-STRUCTURE.md -->

# Appendix C — Suggested Project Structure

Esta estrutura é sugestiva. O objetivo é separar responsabilidades sem exigir reescrita completa imediata.

## MacHost sugerido

```text
MacHost/Sources/
  App/
    AppDelegate.swift
    SettingsWindow.swift
    AppSettings.swift

  Session/
    SessionServer.swift
    SessionState.swift
    DeviceRegistry.swift
    PairingService.swift
    AuthProtocol.swift

  Network/
    EndpointMode.swift
    EndpointAdvertiser.swift
    LANAddressResolver.swift
    TailnetEndpoint.swift
    TransportChannel.swift

  Video/
    VirtualDisplayService.swift
    VirtualDisplayManager.swift
    ScreenCapture.swift
    VideoEncoder.swift
    VideoTransport.swift
    CodecNegotiation.swift

  Input/
    InputServer.swift
    RemoteInputProtocol.swift
    InputIngress.swift
    InputState.swift
    InputBackend.swift
    CGEventBackend.swift
    KarabinerVirtualHIDBackend.swift

  Diagnostics/
    DiagnosticsStore.swift
    NetworkDiagnostics.swift
    InputDiagnostics.swift
```

## AndroidClient sugerido

```text
AndroidClient/app/src/main/java/com/sidescreen/app/
  app/
    MainActivity.kt
    RemoteSessionViewModel.kt

  session/
    SessionClient.kt
    PairingUrl.kt
    AuthHandshake.kt
    PairedHostStorage.kt

  network/
    EndpointMode.kt
    EndpointResolver.kt
    TailnetDiagnostics.kt

  video/
    StreamClient.kt
    VideoDecoder.kt
    CodecCapabilities.kt
    VideoStats.kt

  input/
    InputClient.kt
    RemoteInputProtocol.kt
    InputCaptureManager.kt
    ActivityKeyboardBackend.kt
    PointerCaptureBackend.kt
    AccessibilityAssistBackend.kt
    RootEvdevBackend.kt
    KeyMapping.kt
    PointerMapping.kt

  diagnostics/
    DiagLog.kt
    DiagnosticsState.kt
```

## Refactor incremental

Não tentar mover todos os arquivos de uma vez.

Sequência segura:

1. Criar novos modelos (`EndpointMode`) ao lado dos arquivos existentes.
2. Atualizar QR/parser sem mover UI.
3. Condicionar bind Wi-Fi.
4. Criar input channel novo sem tocar no vídeo.
5. Só depois extrair partes de `MainActivity` e `AppDelegate`.


---

<!-- FILE: CODEX_PROMPT.md -->

# Prompt sugerido para iniciar uma sessão no Codex

Use este prompt como mensagem inicial para o Codex na sua máquina, com o repositório aberto localmente.

---

Estou trabalhando em um fork/novo projeto baseado no SideScreen para transformar um tablet Android em um terminal remoto para um Mac mini via Tailscale.

Leia primeiro toda a documentação em `remote-mac-terminal-spec/`, começando por:

1. `00-CODEX-START-HERE.md`
2. `14-DOCUMENTATION-COVERAGE-AND-STATUS.md`
3. `02-SIDESCREEN-DEEP-DIVE.md`
4. `03-TARGET-ARCHITECTURE.md`
5. `04-TAILSCALE-NETWORKING-SPEC.md`
6. `05-INPUT-ARCHITECTURE-SPEC.md`
7. `08-CODEX-TASK-BACKLOG.md`

Depois, inspecione o código atual do repositório. Não implemente nada antes de confirmar que entendeu:

- como o SideScreen cria o Virtual Display;
- como captura/codifica vídeo;
- como o Android decodifica vídeo;
- como o pareamento wireless funciona;
- onde o Android força `bindSocket` para Wi-Fi;
- se ainda existe fluxo legado enviando touch pelo mesmo socket do vídeo;
- onde o Mac injeta input via `CGEvent`.
- quais tarefas do backlog já foram implementadas.

Objetivo da primeira fase:

- não usar root;
- não reescrever vídeo;
- adaptar conexão para Tailscale/MagicDNS/IP 100.x;
- remover bind forçado em Wi-Fi em modo Tailnet;
- criar canal de input separado;
- capturar teclado/mouse sem root;
- injetar no Mac via CGEvent como fallback inicial;
- manter arquitetura preparada para VirtualHID e root posteriormente.

Restrições:

- não misturar input no socket de vídeo;
- não implementar DriverKit próprio no MVP;
- não implementar root no MVP;
- não tratar `Android KeyEvent` como protocolo final;
- não quebrar USB/LAN existentes;
- preservar licença MIT da base.

Comece propondo um plano de mudanças pequeno para a próxima lacuna real, não para uma tarefa que o código já resolveu. Antes de editar, liste os arquivos que pretende tocar e os riscos de regressão.

---

