# Side Screen Daily Use QA

Checklist prático para validar se o Side Screen está pronto para uso diário real.

## Ambiente

| Item | Como provar |
|---|---|
| Preflight completo | `./scripts/preflight.sh --full` termina sem falhas; warnings viram pendência explícita |
| Pacote de evidências | `./scripts/collect-qa-evidence.sh` cria `qa-evidence/<timestamp>/` com preflight, artefatos, ADB, Tailnet e assinatura |
| Smoke Android USB | `./scripts/android-device-smoke.sh` instala, abre, configura ADB reverse e coleta log |
| Mac app abre sem crash | `open SideScreen.app`, confirmar ícone/menu e janela de settings |
| Screen Recording | Status no Mac fica `Granted`; iniciar stream sem alerta bloqueante |
| Accessibility | Status fica `Granted` ou Virtual HID fica `Ready`; toque e teclado remoto controlam o Mac |
| ADB USB | `adb devices -l` mostra `device`; `adb reverse --list` mostra `tcp:54321 tcp:54321` |
| Tailnet | `./scripts/tailnet-diagnostics.sh` mostra o host do Mac e pelo menos um Android online; QR usa endpoint Tailnet |
| Tailnet no tablet | `./scripts/android-device-smoke.sh --tailnet-host <host-tailnet-do-mac>` consegue pingar ou registra pendência clara |
| Diagnóstico Android | Botão `Copy Diagnostics` copia rota, input, erros recentes e log |
| Diagnóstico Mac | Botão `Copy Diagnostics` copia permissões, ADB, endpoint, input e `/tmp/sidescreen.log` |
| Harness de input | `./scripts/open-input-qa.sh` abre a página que compara acentos, símbolos, emoji, paste longo e atalhos |

## Sessões

| Cenário | Duração mínima | Passa se |
|---|---:|---|
| USB, produtividade | 30 min | `./scripts/collect-qa-evidence.sh --smoke --duration 1800 --expect-stream` observa conexão; sem tela preta, stuck keys ou queda de input |
| USB, baixa latência | 15 min | `./scripts/android-device-smoke.sh --duration 900 --expect-stream` observa conexão; mouse/teclado continuam responsivos |
| Wireless LAN | 30 min | `./scripts/android-device-smoke.sh --duration 1800 --expect-stream` observa conexão; reconecta após pequena queda de Wi-Fi |
| Tailnet | 30 min | `./scripts/tailnet-diagnostics.sh` encontra Android online; `./scripts/collect-qa-evidence.sh --smoke --duration 1800 --expect-stream --tailnet-host <host-tailnet-do-mac>` observa conexão e reachability |
| Sleep/wake do tablet | 5 ciclos | Volta para Reconnect ou reconecta sem estado quebrado |

## Teclado, Texto E Atalhos

Use `./scripts/open-input-qa.sh` no Mac e digite pelo Android nos campos da página. Baixe o relatório JSON e guarde junto do pacote `qa-evidence/`.

| Caso | Texto/ação | Esperado |
|---|---|---|
| Acentos PT-BR | `ação, coração, amanhã, útil, você, João` | Texto chega idêntico |
| Símbolos | `@ # $ % & * / \\ | [] {} ()` | Caracteres chegam sem trocar layout |
| Emoji | `teste 🧪 ✅` | Emoji chega inteiro ou falha sem travar input |
| Enter/Tab/Delete | Enter, Tab, Backspace, Delete | Ações corretas no editor |
| Atalhos Mac | Command+C, Command+V, Command+A, Command+Tab | Funcionam ou limitação aparece claramente |
| Copy/paste longo | Colar 4 KB de texto | Entra sem desconectar |
| Paste grande | Colar texto maior que 4 KB | App rejeita/limita sem derrubar a sessão |

## Reconexão

| Falha simulada | Esperado |
|---|---|
| Desligar Wi-Fi do tablet por 3s | UI mostra tentativa 1/4, volta sozinha se a rede voltar |
| Manter rede fora por >20s | Para em estado Reconnect, sem loop infinito |
| Clicar Disconnect | Nenhuma tentativa automática depois |
| Reset Token no Mac | Android mostra re-pair, sem ficar tentando |
| Mudar Tailnet/LAN/porta | Android pede novo QR |
| Erro wireless | `Copy Diagnostics` contém endpoint, rota, input e últimos erros |

## Permissões Mac

| Permissão | Obrigatória para | Prova prática |
|---|---|---|
| Screen Recording | Captura de vídeo | Iniciar stream sem alerta de permissão |
| Accessibility | Toque/teclado via CGEvent | Tocar no tablet move/clica no Mac |
| Virtual HID helper | Input sem depender de CGEvent | Status `Virtual HID` fica `Ready` ou `Ready via helper` |
| Local Network | Wireless LAN | Tablet alcança o host:porta do QR |

## Distribuição

| Artefato | Verificação |
|---|---|
| Mac `.app` | `codesign --verify --deep --strict --verbose=2 SideScreen.app` |
| Mac `.dmg` | Montar DMG, arrastar para Applications, abrir |
| Mac notarizado | `SIDESCREEN_CODESIGN_IDENTITY` + `SIDESCREEN_NOTARIZE=1 ./scripts/build_mac.sh`; `spctl -a -vv SideScreen.app` aprova |
| Gatekeeper Mac | `./scripts/verify-mac-distribution.sh` não pode reportar rejeição para distribuição |
| Checksums | `./scripts/generate-checksums.sh` gera SHA256 para DMG, APK e AAB |
| Android debug APK | `adb install -r app-debug.apk` |
| Android release APK | Assinar com `SIDESCREEN_RELEASE_*`; instalar em aparelho limpo |
| Android release AAB | `./gradlew bundleRelease` gera `app-release.aab` assinado para Play Store quando `SIDESCREEN_RELEASE_*` está configurado |
| Assinatura Android | `./scripts/verify-android-signing.sh` não pode reportar `CN=Android Debug` para publicação |

## Pendências Que Não Dá Para Fingir

- Notarização Apple exige Apple Developer ID, senha específica de app e Team ID.
- Play Store exige AAB assinado com keystore real, política de privacidade e fluxo de publicação.
- Teste Tailnet só vale com tablet Android online no `tailscale status`.
- Teste de input só vale olhando o texto e os atalhos no Mac real.
