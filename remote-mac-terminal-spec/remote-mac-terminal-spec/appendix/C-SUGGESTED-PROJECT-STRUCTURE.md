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

