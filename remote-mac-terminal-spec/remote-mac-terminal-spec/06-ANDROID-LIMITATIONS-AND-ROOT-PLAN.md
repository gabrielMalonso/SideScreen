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
