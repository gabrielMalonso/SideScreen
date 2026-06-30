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
  eventType
  sequence
  androidTimestampNanos
  deviceId
  payloadLength
  payload
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

- medir latência específica do canal de input;
- não misturar com frame latency.

## Compatibilidade com MVP

O MVP pode começar com subconjunto:

```text
KeyboardKey
PointerRelative
PointerButton
PointerWheel
AllInputsUp
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

