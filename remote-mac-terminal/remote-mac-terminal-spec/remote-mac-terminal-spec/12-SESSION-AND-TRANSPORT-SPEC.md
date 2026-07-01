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

