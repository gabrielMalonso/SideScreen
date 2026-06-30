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

Aceite:

- Modificadores pressionam e soltam corretamente.
- Se Meta não chegar, app registra limitação em diagnóstico.

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
- Diagnóstico registra quais eventos chegaram ou não.
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
- direção natural configurável no futuro.

Aceite:

- Scroll funciona em navegador/Finder.
- Eventos não geram backlog.

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
- UI/log exibe percentis ou médias básicas.

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

