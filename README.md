# Remote Mac

Remote desktop pessoal para acessar e controlar um Mac a partir de um Android, com USB para uso local e Tailnet/LAN para acesso remoto.

O projeto nasceu como um fork do SideScreen, mas a direção atual é outra: **capturar uma tela real existente do Mac e controlar o computador remotamente**, no espírito do Chrome Remote Desktop/Google Remote Desktop. Não há mais modo de monitor extra no app.

## Direção

| Foco | Decisão |
|---|---|
| Produto | Remote desktop para Mac |
| Rede | USB, LAN e Tailscale/Tailnet |
| Vídeo | ScreenCaptureKit/CGDisplayStream capturando displays reais |
| Input | Virtual HID quando disponível, CGEvent como fallback |
| Fora do escopo | Criar Virtual Display, Sidecar caseiro, segundo monitor |

## Estrutura

| Pasta | Papel |
|---|---|
| `MacHost/` | App de menu bar do macOS, captura de tela, streaming, pairing e input |
| `AndroidClient/` | Cliente Android, decoder, UI de sessão, pairing QR e input remoto |
| `scripts/` | Build, instalação local, QA, Tailnet e release |
| `qa/` | Harness prático para validar texto, atalhos e input |

## Fluxo de uso

### USB

1. Instale `adb`: `brew install android-platform-tools`
2. Rode o app Mac.
3. Abra o app Android e toque em `Connect`.

O Mac configura `adb reverse` para o vídeo e para o canal de input.

### Wireless/Tailnet

1. Abra o app Mac.
2. Selecione `Wireless` e escolha LAN ou Tailnet.
3. Escaneie o QR no Android.
4. Use a lista salva de Macs para reconectar depois.

## Desenvolvimento

```bash
./scripts/install.sh
./scripts/preflight.sh --full
```

Validações úteis:

```bash
cd MacHost && swift test
cd AndroidClient && ./gradlew testDebugUnitTest
./scripts/tailnet-diagnostics.sh
./scripts/open-input-qa.sh
```

## Notas

O bundle id, namespace Android, target Swift e variáveis `SIDESCREEN_*` ainda preservam nomes internos do fork para não quebrar permissões, signing e instalação. A superfície do produto agora é Remote Mac.
