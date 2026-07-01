# Side Screen Daily Use QA

Checklist prático para provar uso diário real. Smoke curto é sinal de vida, não aprovação.

## Rodada de Evidências

| Item | Como provar |
|---|---|
| Pacote auditável | `./scripts/collect-qa-evidence.sh ...` cria `qa-evidence/<timestamp>/` com `README.md`, `manifest.txt`, `manifest.json` e `qa-observation-summary.txt` |
| Duração | `manifest.txt` e `manifest.json` mostram duração solicitada e tempo total da rodada |
| Portas `P/P+1` | Manifesto mostra vídeo em `P` e input em `P+1`; `adb-reverse-list*.txt` ou logs Android confirmam o par |
| Stream observado | `android-device-smoke.txt` e `qa-observation-summary.txt` mostram frame flow ou frames recebidos |
| Input observado | `android-device-smoke.txt` mostra `Input channel observed on P+1` ou diagnóstico equivalente |
| Backend ativo | `qa-observation-summary.txt`, diagnóstico Android ou `/tmp/sidescreen.log` mostram `CGEvent` ou `Virtual HID` quando disponível |
| Tailnet | `tailscale-status.txt` e `tailnet-diagnostics.txt` registram host, rota e tablet online |
| Input QA | `input-qa-checklist.*` e `sidescreen-input-qa-*.json` ficam dentro da mesma pasta de evidência |

## Ambiente

| Item | Como provar |
|---|---|
| Preflight completo | `./scripts/preflight.sh --full` termina sem falhas; warnings viram pendência explícita |
| Mac app abre sem crash | `open SideScreen.app`, confirmar ícone/menu e janela de settings |
| Screen Recording | Status no Mac fica `Granted`; iniciar stream sem alerta bloqueante |
| Accessibility ou Virtual HID | Status fica `Granted`, `Ready` ou `Ready via helper`; input remoto controla o Mac |
| ADB USB | `adb devices -l` mostra `device` |
| ADB reverse USB | `adb reverse --list` mostra `tcp:54321 tcp:54321` e `tcp:54322 tcp:54322` |
| Diagnóstico Android | `Copy Diagnostics` inclui rota, input, backend ativo, erros recentes e log |
| Diagnóstico Mac | `Copy Diagnostics` inclui permissões, endpoint, backend, input e `/tmp/sidescreen.log` |

## Sessões Longas

| Cenário | Duração mínima | Comando | Passa se |
|---|---:|---|---|
| USB diário | 30 min | `./scripts/collect-qa-evidence.sh --duration 1800 --expect-stream --tap-connect` | Vídeo e input `P/P+1` observados; sem tela preta, stuck key ou queda de input |
| Tailnet diário | 30 min | `./scripts/collect-qa-evidence.sh --duration 1800 --expect-stream --tap-connect --no-reverse --tailnet-host <host-tailnet-do-mac>` | MagicDNS/IP Tailnet conecta, stream flui, input chega em `P+1` e backend aparece quando disponível |
| Tailnet fallback IP 100.x | 30 min se MagicDNS falhar | `./scripts/collect-qa-evidence.sh --duration 1800 --expect-stream --tap-connect --no-reverse --tailnet-host <ip-100.x-do-mac>` | Fallback funciona ou a falha fica diagnosticada |
| USB baixa latência | 15 min | `./scripts/android-device-smoke.sh --duration 900 --expect-stream --tap-connect` | Mouse/teclado continuam responsivos sob uso leve |
| Sleep/wake do tablet | 5 ciclos | Manual com logs anexados | Volta para Reconnect ou reconecta sem estado quebrado |

## Input QA: CGEvent vs Virtual HID

Rode uma rodada por backend quando Virtual HID estiver disponível. O relatório não deve salvar texto digitado; ele salva comprimentos, índice de mismatch, atalhos vistos, checklist e metadados.

| Backend | Comando base |
|---|---|
| CGEvent | `./scripts/open-input-qa.sh --backend CGEvent --transport USB --layout ABNT2 --evidence-dir qa-evidence/<rodada>` |
| Virtual HID | `./scripts/open-input-qa.sh --backend VirtualHID --transport USB --layout ABNT2 --evidence-dir qa-evidence/<rodada>` |
| Tailnet + backend real | `./scripts/open-input-qa.sh --backend <CGEvent|VirtualHID> --transport Tailnet --layout ABNT2 --evidence-dir qa-evidence/<rodada>` |

## Teclado, Texto e Atalhos

Use `./scripts/open-input-qa.sh`, digite pelo Android nos campos da página e baixe o relatório JSON para a pasta da rodada.

| Caso | Esperado |
|---|---|
| Acentos PT-BR | `ação, coração, amanhã, útil, você, João` chega idêntico |
| Símbolos | `@ # $ % & * / \\ | [] {} ()` não troca layout |
| Emoji | `teste 🧪 ✅` chega inteiro ou falha sem travar input |
| Enter/Tab/Delete | Enter, Tab, Backspace e Delete agem corretamente |
| Modificadores | Shift, Control, Option/Alt e Command/Meta chegam ou limitação fica clara |
| Atalhos Mac | Command+C, Command+V, Command+A e Command+Tab funcionam ou limitação é registrada |
| Paste longo | 4 KB entra sem desconectar |
| Paste grande demais | Rejeita/limita sem derrubar sessão |

## Mouse

| Caso | Esperado |
|---|---|
| Movimento relativo | Cursor move sem backlog visível |
| Botões | Esquerdo, direito e meio pressionam e soltam |
| Drag | Arrastar inicia, move e solta sem botão preso |
| Scroll vertical | Rola em navegador/editor |
| Scroll horizontal | Rola quando o hardware suportar |
| Perda de pointer capture | Android envia `AllInputsUp`; Mac solta botões e teclas |

## Reconexão e Segurança

| Falha simulada | Esperado |
|---|---|
| Desligar Wi-Fi do tablet por 3s | UI mostra tentativa de reconexão e volta sozinha se a rede voltar |
| Manter rede fora por mais de 20s | Para em estado Reconnect, sem loop infinito |
| Clicar Disconnect | Nenhuma tentativa automática depois |
| Reset Token no Mac | Android mostra re-pair, sem continuar tentando |
| Revogar tablet durante stream | Stream/input caem e reconexão exige novo pareamento |
| Mudar Tailnet/LAN/porta | Android pede novo QR |
| Perder foco segurando tecla/botão | `AllInputsUp` aparece nos logs; nada fica preso |

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

- Teste de 30 min exige tablet real e Mac app rodando; não aprove isso por extrapolação.
- Teste Tailnet só vale com tablet Android online no `tailscale status`.
- Teste de input só vale com teclado/mouse reais e relatório JSON anexado.
- Virtual HID só conta como aprovado quando o diagnóstico mostra backend ativo em apps reais.
- Notarização Apple exige Apple Developer ID, senha específica de app e Team ID.
- Play Store exige AAB assinado com keystore real, política de privacidade e fluxo de publicação.
