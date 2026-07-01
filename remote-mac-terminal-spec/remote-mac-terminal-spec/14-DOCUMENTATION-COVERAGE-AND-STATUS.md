# 14 — Documentation Coverage and Status

Data: 2026-07-01

Este documento fecha a documentação da spec. "100%" aqui significa cobertura documental completa do produto atual: o que existe, onde está descrito, como validar, o que ainda é futuro e qual arquivo usar para implementar sem chute.

Não significa que o produto final está 100% pronto. Significa que a documentação não deixa buraco conceitual relevante para continuar o desenvolvimento.

## Mapa de cobertura

| Área | Status da documentação | Fonte principal | Evidência no código/projeto |
| --- | --- | --- | --- |
| Objetivo de produto | Completo | `01-PROJECT-BRIEF.md` | README principal e fluxo Mac/Android existentes |
| Arquitetura macro | Completo | `03-TARGET-ARCHITECTURE.md` | `MacHost/Sources/*`, `AndroidClient/app/src/main/java/com/sidescreen/app/*` |
| Reuso do vídeo SideScreen | Completo | `02-SIDESCREEN-DEEP-DIVE.md`, ADR-0002 | `VirtualDisplayManager.swift`, `ScreenCapture.swift`, `VideoEncoder.swift`, `VideoDecoder.kt` |
| Tailnet/LAN/manual | Completo | `04-TAILSCALE-NETWORKING-SPEC.md` | `EndpointMode.swift`, `EndpointMode.kt`, `EndpointAdvertiser.swift`, `NetworkRoute.kt` |
| Pareamento e sessão | Completo | `12-SESSION-AND-TRANSPORT-SPEC.md`, `13-SECURITY-MODEL.md` | `WirelessAuth.swift`, `AuthHandshake.kt`, `RemoteSessionStore.swift` |
| Canal dedicado de input | Completo | `05-INPUT-ARCHITECTURE-SPEC.md`, `11-REMOTE-INPUT-PROTOCOL-V1.md` | `InputServer.swift`, `InputClient.kt` |
| Protocolo de input v1 | Completo | `11-REMOTE-INPUT-PROTOCOL-V1.md` | `RemoteInputProtocol.swift`, `RemoteInputProtocol.kt` |
| Fail-safe de input | Completo | `05-INPUT-ARCHITECTURE-SPEC.md`, `13-SECURITY-MODEL.md` | `InputIngress.swift`, `CGEventInputBackend.swift`, `KarabinerVirtualHIDBackend.swift` |
| CGEvent fallback | Completo | `05-INPUT-ARCHITECTURE-SPEC.md`, ADR-0006 | `CGEventInputBackend.swift` |
| Virtual HID | Completo | `05-INPUT-ARCHITECTURE-SPEC.md`, ADR-0006 | `KarabinerVirtualHIDBackend.swift`, `VirtualHIDHelperInstaller.swift`, `VirtualHIDHelperSources/main.swift` |
| Android sem root | Completo | `06-ANDROID-LIMITATIONS-AND-ROOT-PLAN.md` | `InputClient.kt`, `RemoteInputBridge.kt`, `SideScreenAccessibilityService.kt` |
| Accessibility assist | Completo | `06-ANDROID-LIMITATIONS-AND-ROOT-PLAN.md` | `SideScreenAccessibilityService.kt`, `RemoteInputBridge.kt` |
| Diagnóstico operacional | Completo | `07-IMPLEMENTATION-ROADMAP.md`, `09-TEST-PLAN.md` | `DiagLog.kt`, `TailnetDiagnostics.swift`, `scripts/collect-qa-evidence.sh` |
| Testes automatizados | Completo | `09-TEST-PLAN.md` | `MacHost/Tests/SideScreenTests/*`, `AndroidClient/app/src/test/*` |
| QA manual diário | Completo | `09-TEST-PLAN.md` | `../../DAILY_USE_QA.md`, `../../qa-evidence/*` |
| Riscos e decisões | Completo | `10-RISKS-AND-OPEN-QUESTIONS.md`, `adr/*` | ADRs 0001-0006 |
| Estrutura sugerida | Completo | `appendix/C-SUGGESTED-PROJECT-STRUCTURE.md` | Estrutura atual já segue boa parte da divisão sugerida |

## Estado implementado

| Marco | Estado | Notas práticas |
| --- | --- | --- |
| Tailnet endpoint support | Implementado | QR e parser têm modo de endpoint; Tailnet não deve prender socket em Wi-Fi. |
| Input channel separado | Implementado | Input usa porta dedicada no MVP e `TCP_NODELAY`. |
| Remote Input Protocol v1 | Implementado | Envelope com tipo, sequência, timestamp e payload; inclui ping/pong de latência. |
| Teclado sem root | Implementado | Activity/Accessibility enviam eventos mapeados para HID usage quando Android entrega a tecla. |
| Mouse sem root | Implementado | Movimento relativo, botões e wheel; pointer capture é o caminho preferido. |
| `TextCommit` | Implementado | Cobre IME/dead keys sem logar texto digitado; commits grandes são divididos em chunks seguros. |
| `AllInputsUp` com motivo | Implementado | Usado em disconnect, lifecycle, perda de pointer capture e troca de backend. |
| CGEvent backend | Implementado | Fallback inicial e caminho de compatibilidade. |
| Virtual HID | Implementado | Suporta Karabiner VirtualHID direto quando possível e helper privilegiado do SideScreen. |
| Device registry/revogação | Implementado | Existe store de dispositivos pareados/revogados no Mac. |
| Diagnóstico Mac/Android | Implementado | Diagnósticos cobrem endpoint, rota, input, permissões, logs e erros recentes. |
| Evidence collection | Implementado | Scripts coletam preflight, artefatos, Tailnet, assinatura, testes e smoke Android; smoke pode tocar Connect/Reconnect via ADB. |
| Root backend | Futuro intencional | A spec cobre plano e limites; não deve virar requisito do MVP. |
| QUIC/single-port final | Futuro condicional | Só entra se medições reais mostrarem que TCP multi-channel é gargalo. |

## Execução verificada em 2026-07-01

| Área | Resultado | Evidência prática |
| --- | --- | --- |
| Auditoria paralela | Concluída | Subauditorias de Mac/input, Android/input, rede/Tailscale e testes/QA confirmaram que o backlog antigo não é retrato fiel do pendente. |
| Mac input lifecycle | Melhorado | `InputServer.dropActiveConnection(reason:)` encerra a sessão ativa de input quando o stream de vídeo desconecta, mantendo o listener pronto para reconexão. |
| Android pointer capture | Melhorado | `onResume` tenta recapturar pointer capture quando stream e input ainda estão ativos. |
| Android `TextCommit` | Melhorado | `InputClient.sendTextCommit` divide texto grande por bytes UTF-8 e preserva codepoints, evitando crash por payload maior que 4094 bytes. |
| Logs de input | Melhorado | Android deixou de registrar prefixo do token de input no diagnóstico. |
| QR Tailnet | Melhorado | Modo Tailnet sem host não gera mais QR para `0.0.0.0`; a UI mostra que falta MagicDNS ou IP 100.x. |
| Smoke Android | Melhorado | `scripts/android-device-smoke.sh` e `scripts/collect-qa-evidence.sh` aceitam `--tap-connect`; a validação de stream usa um arquivo combinado para evitar falso negativo. |
| Testes Mac | Passou | `swift test`: 81 testes, 0 falhas. |
| Testes Android | Passou | `. scripts/android-env.sh && ./gradlew testDebugUnitTest`: sucesso com JDK 17. |
| Preflight completo | Passou com warnings esperados | `./scripts/preflight.sh --full`: 18 passes, 5 warnings, 0 falhas. Warnings: worktree suja, release Android debug-signed, Gatekeeper/notarização ausentes e credenciais de distribuição não configuradas. |
| Tablet conectado | Detectado | `adb devices -l`: `SM_X610` serial `RX2XC0094TX`; `tailscale status` mostra `tab-s9-fe-de-gabriel` online. |
| Pacote de evidência curto | Passou | `qa-evidence/20260701-105422-19579`: instala/abre app no tablet, configura ADB reverse, toca Connect/Reconnect via ADB e coleta diagnóstico. Não exige stream. |
| Stream Tailnet real no `SM_X610` | Passou | `qa-evidence/20260701-110355-67670`: `--no-reverse --tailnet-host mac-mini-de-gabriel.tailad333c.ts.net --expect-stream --tap-connect`; vídeo HEVC 1920x1200, frames recebidos e canal de input em `54322` conectado via Tailnet. |
| Revogação/reset ativos | Melhorado | `Revoke` e `Reset Token` agora passam pelo `AppDelegate`, revogam sessão, derrubam stream/input ativos e limpam estado atual. Ainda precisa QA manual revogando o tablet durante stream. |
| Fail-safe de input | Melhorado | `InputIngress` solta teclas/botões em gap de sequência com estado pressionado e contabiliza `AllInputsUp` no diagnóstico. Touch legado solta drag em disconnect/stop. |
| USB com input separado | Melhorado | Scripts e indicador Mac agora configuram/verificam ADB reverse para `P` e `P+1` (`54321` e `54322`), não só vídeo. |
| Permissões macOS em rebuild | Melhorado | `scripts/build_mac.sh` auto-detecta `Developer ID Application`/`Apple Development` e evita assinatura ad-hoc quando possível; isso estabiliza o requisito TCC. É normal precisar conceder Screen Recording/Accessibility uma vez para a nova identidade. |
| Testes Mac atualizados | Passou | `swift test`: 83 testes, 0 falhas. |
| Testes Android atualizados | Passou | `. scripts/android-env.sh && ./gradlew testDebugUnitTest`: sucesso com helper de porta de input. |
| Preflight completo atualizado | Passou com warnings esperados | `./scripts/preflight.sh --full`: 19 passes, 4 warnings, 0 falhas. Warnings: worktree suja, Android release debug-signed, app/DMG ainda sem notarização e credenciais Android release ausentes. |
| InputServer contra conexão inválida | Melhorado | Nova conexão de input só substitui a ativa depois de hello/auth aceito; conexão inválida em `P+1` não derruba o input atual. |
| InputServer contra callbacks antigos | Melhorado | Callbacks atrasados de conexão cancelada são ignorados quando não pertencem mais à sessão ativa. |
| Virtual HID em fim de sessão | Melhorado | `InputIngress.endSession` agora propaga `endSession(reason:)` ao backend downstream, permitindo reset real do Karabiner VirtualHID/helper. |
| Logs de token no Mac | Melhorado | Log de autenticação de input removeu o prefixo do token; mantém apenas dispositivo e sessão curta para diagnóstico. |
| USB/loopback de input | Melhorado | `InputClient` não tenta `bindSocket` em Wi-Fi quando o host é `127.0.0.1`/`localhost`; USB mantém rota loopback para `P/P+1`. |
| Contrato de portas `P/P+1` | Melhorado | Mac, Android e scripts rejeitam/capam porta de vídeo acima de `65534`, evitando vídeo e input na mesma porta. |
| UX Android conectada | Melhorado | Stats e barra de input ficam desligados por padrão; telemetria continua disponível no diálogo de settings. |
| Accessibility em background | Melhorado | `onPause` envia `AllInputsUp` e desconecta o bridge de Accessibility; `onResume` reanexa se a sessão de input continuar ativa. |
| Smoke Android mais rigoroso | Melhorado | `--expect-stream` agora exige stream/frame flow e canal de input observado em `P+1`. |
| Testes Mac atuais | Passou | `swift test`: 87 testes, 0 falhas. |
| Testes Android atuais | Passou | `. scripts/android-env.sh && ./gradlew testDebugUnitTest` e `./gradlew assembleDebug`: sucesso. |
| Stream Tailnet curto pós-correções no `SM_X610` | Passou | `qa-evidence/20260701-113541-41224`: `--duration 60 --expect-stream --tap-connect --no-reverse --tailnet-host mac-mini-de-gabriel.tailad333c.ts.net`; vídeo HEVC 1920x1200, 1140+ frames, input em `54322`, 0 falhas. |
| Preflight completo pós-correções | Passou com warnings esperados | `qa-evidence/20260701-113541-41224/preflight.txt`: 19 passes, 4 warnings, 0 falhas. Warnings: worktree suja, Android release debug-signed, app/DMG não notarizados e credenciais Android release ausentes. |

## Lacunas reais para uso diário

| Lacuna | Por que importa | Próximo passo pequeno |
| --- | --- | --- |
| Sessão longa no tablet `SM_X610` | O produto quer ser diário, não apenas compilar. | Rodar USB e Tailnet por 30 min com `--expect-stream --tap-connect`, guardando evidência em `qa-evidence/`. |
| Input QA com hardware real | Unit test não prova teclado/mouse Bluetooth, acentos, drag e scroll no corpo. | Usar `./scripts/open-input-qa.sh`, salvar o JSON do harness junto da evidência. |
| Virtual HID real | Código e framing passam, mas helper/Karabiner precisam smoke em máquina real. | Instalar/ativar helper e testar Terminal, Finder, navegador e editor. |
| Revogação durante sessão ativa | O código agora derruba a sessão ativa, mas segurança boa não vive só de unit test. | Revogar tablet durante stream e confirmar queda/rejeição do input em `qa-evidence/`. |
| Sessão Tailnet longa com `P/P+1` | O smoke de 60s provou vídeo e input em portas separadas; uso diário ainda precisa tempo. | Rodar Tailnet por 30 min com `--expect-stream --tap-connect --no-reverse --tailnet-host mac-mini-de-gabriel.tailad333c.ts.net`. |
| Permissões macOS após assinatura estável | Developer ID estabiliza TCC, mas a nova identidade precisa autorização humana uma vez. | Abrir o app assinado, conceder Screen Recording/Accessibility e confirmar que rebuilds seguintes não pedem de novo. |
| Distribuição | Builds locais agora usam Developer ID quando disponível, mas release público ainda exige notarização e Android release signing real. | Configurar notarização/staple e keystore Android release. |

## Fluxo atual

```text
Android tablet
  captura Activity / pointer capture / Accessibility assist
  gera Remote Input Protocol v1
  envia input por canal dedicado
        |
        v
MacHost InputServer
  valida token/sessão/dispositivo
  passa por InputIngress
  coalesce mouse move
  rastreia teclas/botões pressionados
  solta tudo em falha
        |
        v
Input backend
  Virtual HID quando pronto
  CGEvent como fallback
```

## O que ainda é futuro, sem fingimento

| Item | Por que não bloqueia 100% da documentação | Próximo passo correto |
| --- | --- | --- |
| Root no Android | Está documentado como backend opcional posterior, com riscos e escape. | Fazer discovery passivo antes de qualquer envio remoto. |
| DriverKit próprio | Existe alternativa prática com Karabiner/SideScreen helper. | Só justificar se instalação/controle exigirem. |
| QUIC | TCP com canais separados já cobre o desenho atual. | Medir latência/queda em rede real antes de trocar transporte. |
| ABNT2 perfeito | Layout depende de teclado, Android e mapeamento físico. | Ampliar testes reais e tabela de key mapping. |
| Installer polido | Arquitetura e permissões estão documentadas. | Transformar onboarding/installer em tarefa de produto. |
| Áudio/clipboard/multimonitor/file drop | São extras, não fazem parte do terminal remoto mínimo. | Tratar cada um como epic separado depois da base estável. |

## Regra de leitura para próximas sessões

Use esta ordem:

1. `README.md`
2. `00-CODEX-START-HERE.md`
3. `14-DOCUMENTATION-COVERAGE-AND-STATUS.md`
4. `07-IMPLEMENTATION-ROADMAP.md`
5. `08-CODEX-TASK-BACKLOG.md`
6. O documento específico da área que será alterada

Se houver conflito entre um backlog antigo e este documento, este documento vence para status atual. O backlog continua útil como decomposição de trabalho, não como retrato fiel do que ainda falta.

## Critério de "documentação 100%"

A documentação está 100% quando uma pessoa consegue responder, sem ler o código inteiro:

- o que o produto quer ser;
- quais decisões arquiteturais já foram tomadas;
- quais partes do SideScreen são reaproveitadas;
- como Tailnet, LAN e manual diferem;
- como o input sai do Android e entra no Mac;
- como a sessão protege o canal de input;
- quais backends existem no Mac;
- o que acontece quando uma conexão cai;
- o que é limitação real do Android sem root;
- quais testes e evidências validam o sistema;
- quais itens são futuro deliberado, não buraco esquecido.

Com este arquivo, essa lista está coberta.
