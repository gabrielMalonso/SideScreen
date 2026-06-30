# 00 — Codex Start Here

Este documento é o briefing para continuar o projeto em uma máquina local usando Codex.

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

