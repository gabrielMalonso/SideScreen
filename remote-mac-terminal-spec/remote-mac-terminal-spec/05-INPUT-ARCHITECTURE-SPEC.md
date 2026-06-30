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

### 3. TouchBackend

Fase: manter como opcional.

Captura touch da tela do tablet e envia como touch/absolute pointer. Não deve ser misturado com mouse relativo.

Eventos:

```text
PointerAbsolute
TouchGesture
```

### 4. AccessibilityAssistBackend

Fase: pós-MVP.

Accessibility pode pedir para filtrar eventos de tecla, mas não deve ser backend principal.

Uso recomendado:

- modo opcional "captura assistida";
- tentar obter eventos adicionais de teclado;
- não prometer captura de Home/Power/Recents;
- explicar claramente ao usuário por que a permissão é sensível.

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
- considerar direção natural configurável.

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

