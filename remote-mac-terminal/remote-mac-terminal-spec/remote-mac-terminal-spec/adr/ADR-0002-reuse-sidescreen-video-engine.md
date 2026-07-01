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

