# Plano Técnico - QA de Uso Diário e Evidências

**Status:** Aguardando aprovação  
**Data:** 2026-07-01  
**HTML visual:** [`plano-qa-uso-diario-evidencias-2026-07-01.html`](./plano-qa-uso-diario-evidencias-2026-07-01.html)

> Este Markdown é a fonte da verdade para execução. O HTML é apenas o painel visual de aprovação.

## 1. Entendimento

**Tarefa:** Executar uma rodada objetiva de QA de uso diário, com evidências suficientes para provar estabilidade em USB e Tailnet, sem confundir smoke curto com produto usável.

**Escopo:** Scripts de evidência; Tailnet; USB/ADB reverse; vídeo; canal de input dedicado; lifecycle Android; logs; matriz manual de teclado/mouse; documentação `DAILY_USE_QA.md` e `qa-evidence/*`.

**Premissas:**

- Smoke curto já passou, mas não prova uso diário.
- O tablet real e os periféricos Bluetooth são recursos compartilhados; portanto, o paralelismo precisa separar automação sem hardware de sessões manuais com hardware.
- O alvo mínimo é 30 min por modo relevante: Tailnet e USB.
- Toda falha precisa virar evidência reproduzível, não memória de teste manual.

## 2. Exploração

**Arquivos analisados:**

| Arquivo | Por que importa |
|---------|-----------------|
| `14-DOCUMENTATION-COVERAGE-AND-STATUS.md` | Lista lacunas reais: sessão longa, input QA com hardware, VirtualHID real, revogação ativa, Tailnet longa, permissões e distribuição. |
| `09-TEST-PLAN.md` | Define casos TN, VID, KEY, MOU, LAT, LIFE, SEC e PERM. |
| `04-TAILSCALE-NETWORKING-SPEC.md` | Define expectativas de MagicDNS/IP 100.x e não usar bind Wi-Fi em Tailnet. |
| `05-INPUT-ARCHITECTURE-SPEC.md` | Define fail-safe, pointer capture, input priority e métricas. |
| `11-REMOTE-INPUT-PROTOCOL-V1.md` | Define sequence/timestamp, `AllInputsUp`, ping/pong e coalescing seguro. |
| `12-SESSION-AND-TRANSPORT-SPEC.md` | Define prioridade de canais e reconnect esperado. |
| `13-SECURITY-MODEL.md` | Define que stuck keys e input sem auth são problemas de segurança. |

**Stack identificada:** MacHost Swift; Android Kotlin; Tailscale/MagicDNS; ADB reverse; scripts shell; `qa-evidence`; `open-input-qa`; logs de diagnóstico Mac/Android.

**Comandos de validação do projeto:**

```bash
./scripts/preflight.sh --full
./scripts/collect-qa-evidence.sh --tap-connect
./scripts/collect-qa-evidence.sh --no-reverse --tailnet-host mac-mini-de-gabriel.tailad333c.ts.net --expect-stream --tap-connect
./scripts/open-input-qa.sh
adb devices -l
tailscale status
```

## 3. Impacto Técnico

**Afeta contratos entre módulos?** Não diretamente. Este plano mede comportamento. Correções encontradas podem afetar contratos de input, sessão ou Tailnet e devem virar planos/correções específicos.

| Área | Arquivo/módulo | Mudança necessária | Contrato afetado |
|------|----------------|-------------------|------------------|
| Evidência | `scripts/collect-qa-evidence.sh` | Garantir que sessão longa salve logs de vídeo, input, rota e backend. | Não |
| QA manual | `DAILY_USE_QA.md` | Registrar matriz real, tempo, periféricos, resultado e paths. | Não |
| Tailnet | `NetworkRoute.kt`, `EndpointMode.*`, `PairingURL.*` | Corrigir apenas se MagicDNS/IP 100.x ou split tunneling falhar. | Sim, se alterar parser/rota |
| USB | scripts ADB reverse | Confirmar `P` e `P+1` para vídeo e input. | Não |
| Input | `InputClient.kt`, `InputIngress.swift` | Corrigir stuck key, perda de up/down, latência ou coalescing errado. | Sim |
| Diagnóstico | `DiagLog.kt`, `TailnetDiagnostics.swift` | Melhorar mensagens se a falha real ficar opaca. | Não |

**Ordem recomendada:** automação baseline → sessões longas → matriz input → lifecycle/falhas → pacote de evidência final.

## 4. Testes

### Testes existentes relevantes

| Arquivo | O que cobre | Relevância |
|---------|-------------|------------|
| `09-TEST-PLAN.md` | TN-001/TN-002/TN-003, VID-001/2/3, KEY/MOU/LAT/LIFE/SEC/PERM. | Fonte da matriz de QA. |
| `scripts/collect-qa-evidence.sh` | Coleta smoke, preflight, Tailnet e artefatos. | Deve produzir evidência auditável. |
| `scripts/android-device-smoke.sh` | Instala/abre app e toca Connect/Reconnect via ADB. | Reduz setup manual. |
| `scripts/open-input-qa.sh` | Harness de input manual. | Prova teclado/mouse reais. |

### Testes que devem ser ajustados

| Arquivo | Motivo | Ação |
|---------|--------|------|
| `scripts/collect-qa-evidence.sh` | Sessão longa precisa diferenciar “conectou” de “ficou usável”. | Adicionar duração/heartbeat/latência se ainda não houver. |
| `DAILY_USE_QA.md` | Precisa ser checklist de aprovação, não diário solto. | Padronizar campos: ambiente, periféricos, duração, evidência, falhas. |
| `scripts/open-input-qa.sh` | Precisa registrar backend ativo e layout. | Garantir JSON com backend, modo, teclado, mouse, layout e observações. |

### Novos testes necessários

| Módulo | Arquivo | O que testar | Tipo | Justificativa |
|--------|---------|--------------|------|---------------|
| Tailnet | `qa-evidence/*` | 30 min via MagicDNS com stream e input `P/P+1`. | e2e/manual | Smoke curto não valida uso diário. |
| Tailnet | `qa-evidence/*` | 30 min via IP 100.x, se MagicDNS falhar ou como fallback. | e2e/manual | Fallback precisa ser real. |
| USB | `qa-evidence/*` | 30 min com ADB reverse para vídeo e input. | e2e/manual | USB é baseline local. |
| Vídeo/input | `qa-evidence/*` | Carga alta: mover janelas, digitar e mover mouse. | e2e/manual | Vídeo deve degradar antes do input. |
| Lifecycle | `qa-evidence/*` | Perder foco segurando tecla/botão; alternar rede. | e2e/manual | Stuck key é falha de segurança. |
| Diagnóstico | `qa-evidence/*` | Forçar timeout, token rejeitado, MagicDNS falho. | manual | Mensagem precisa orientar ação, não só dizer “failed”. |

### Edge cases

- Queda de Tailnet segurando modificador.
- Hotspot/celular alternando rota durante sessão.
- `InputPing` continua, mas vídeo trava.
- Vídeo volta e input não volta, ou o inverso.
- ADB reverse configurado só para `P` e esquecido em `P+1`.
- Mouse capture perdido durante drag.
- Teclado ABNT2 com dead keys/acento.
- MagicDNS resolve, mas porta do Mac está bloqueada.

### O que não precisa de teste novo

- Todos os codecs possíveis. Basta HEVC/H.264 nos caminhos usados pelo tablet de referência.
- Root Android. Fora desta rodada.
- QUIC. Sem métrica de gargalo, é engenharia decorativa.
- DriverKit próprio. VirtualHID/helper é o alvo prático.

## 5. I18N

**Novas strings necessárias?** Possivelmente, só para diagnóstico mais claro.

| Chave/área | Texto base | Módulo | Arquivo | Ação |
|------------|------------|--------|---------|------|
| qa.tailnet.vpn_inactive | “Tailscale/VPN não parece ativo para este app.” | Android | UI Wireless/diagnóstico | Criar se ausente |
| qa.input.capture_lost | “Captura de mouse perdida; soltando teclas e botões por segurança.” | Android/Mac | Diagnóstico input | Criar se ausente |
| qa.usb.input_reverse_missing | “ADB reverse do canal de input não está configurado.” | Scripts/Mac UI | Diagnóstico USB | Criar se ausente |
| qa.magicdns_fallback | “MagicDNS falhou; teste com o IP 100.x do Mac.” | Android/Mac | UI de conexão | Confirmar/ajustar |

**Arquivos a atualizar:**

- `AndroidClient/app/src/main/res/values/strings.xml`, se existir.
- UI/Settings Android.
- UI/Settings Mac.
- `DAILY_USE_QA.md`, se o texto do diagnóstico mudar.

**Strings hardcoded a evitar:**

- `failed`, `timeout`, `unreachable` sem contexto humano.
- Mensagens que prometem capturar Home/Power/Recents sem root.
- Mensagens que escondem se o backend é CGEvent ou VirtualHID.

## 6. Riscos e Mitigação

| # | Risco | Probabilidade | Impacto | Mitigação |
|---|-------|---------------|---------|-----------|
| 1 | QA longa parecer “travada” porque depende de hardware único. | Alta | Baixa eficiência. | Rodar preflight/testes/documentação em paralelo enquanto a sessão longa usa o tablet. |
| 2 | Falha manual não ser reproduzível. | Média | Correção vira chute. | Toda falha precisa de horário, log, modo, backend, rede e passo de reprodução. |
| 3 | Falso positivo: vídeo aparece, mas input channel não está ativo. | Média | Aprovação errada. | Aceite exige vídeo + input `P/P+1` + backend ativo + input real. |
| 4 | Input sob carga parecer subjetivo. | Alta | Discussão inútil. | Registrar RTT/p95 do input e frame age quando disponível. |
| 5 | QA de acentos/layout virar buraco sem fim. | Média | Escopo explode. | US baseline + ABNT2 documentado; corrigir só bloqueadores diários. |
| 6 | Tailscale em DERP/relay mascarar problema de app. | Média | Diagnóstico confuso. | Registrar `tailscale status`, RTT e rota. |

## 7. Plano de Implementação

### Wave 1: Preparação de ambiente e evidência

- [ ] Passo 1.1: Confirmar tablet, teclado, mouse, Mac e Tailnet ativos -> Verificação: `adb devices -l` e `tailscale status` salvos.
- [ ] Passo 1.2: Rodar `./scripts/preflight.sh --full` -> Verificação: resultado anexado ao pacote de QA.
- [ ] Passo 1.3: Rodar smoke curto com `--tap-connect` -> Verificação: app instala/abre/conecta ou falha com log.
- [ ] Passo 1.4: Criar pasta de rodada em `qa-evidence/` -> Verificação: naming padrão e README da rodada.

### Wave 2: Sessões longas, com paralelismo controlado

- [ ] Passo 2.1: Rodar Tailnet 30 min via MagicDNS -> Verificação: stream, input channel, RTT/p95 e logs preservados.
- [ ] Passo 2.2: Em paralelo ao Passo 2.1, revisar logs de preflight e preparar matriz de input -> Verificação: lista de casos pronta antes da sessão manual.
- [ ] Passo 2.3: Rodar USB 30 min com ADB reverse `P` e `P+1` -> Verificação: não regressão do caminho USB.
- [ ] Passo 2.4: Se MagicDNS falhar, rodar Tailnet 30 min via IP 100.x -> Verificação: fallback comprovado.

### Wave 3: Input real com hardware Bluetooth

- [ ] Passo 3.1: Rodar `./scripts/open-input-qa.sh` -> Verificação: JSON inicial criado.
- [ ] Passo 3.2: Testar teclado comum: A-Z, números, Enter, Escape, Tab, Backspace, setas -> Verificação: down/up corretos, sem stuck key.
- [ ] Passo 3.3: Testar modificadores: Shift, Ctrl, Alt/Option, Meta/Super quando entregue -> Verificação: mapeamento e limitações registradas.
- [ ] Passo 3.4: Testar texto composto/dead keys/acento -> Verificação: `TextCommit` funciona ou limitação documentada.
- [ ] Passo 3.5: Testar mouse: movimento relativo, botões, drag, scroll vertical/horizontal -> Verificação: sem backlog e sem botão preso.
- [ ] Passo 3.6: Testar perda de foco e perda de pointer capture -> Verificação: `AllInputsUp` com motivo e release-all no Mac.

### Wave 4: Falhas controladas e diagnóstico

- [ ] Passo 4.1: Desligar Tailscale/alternar rede segurando modificador -> Verificação: Mac solta input e logs mostram razão.
- [ ] Passo 4.2: Forçar MagicDNS inválido -> Verificação: UI sugere IP 100.x.
- [ ] Passo 4.3: Testar app excluído do split tunneling, se o ambiente permitir -> Verificação: diagnóstico aponta VPN/Tailscale.
- [ ] Passo 4.4: Testar token inválido/re-pair -> Verificação: nenhum input/vídeo começa sem auth.

### Wave 5: Fechamento da evidência

- [ ] Passo 5.1: Consolidar pacotes de evidência -> Verificação: cada critério tem path de prova.
- [ ] Passo 5.2: Classificar falhas por severidade -> Verificação: `BLOCKER/HIGH/MEDIUM/LOW` com reprodução.
- [ ] Passo 5.3: Atualizar `DAILY_USE_QA.md` -> Verificação: aprovado/reprovado sem ambiguidade.

## 8. Checklist de Validação

- [ ] Build dos módulos alterados: não aplicável se nenhuma correção for feita; se houver correção, rodar `swift test` e/ou `. scripts/android-env.sh && ./gradlew testDebugUnitTest`.
- [ ] Testes relevantes: `./scripts/preflight.sh --full`, `./scripts/collect-qa-evidence.sh ...`, `./scripts/open-input-qa.sh`.
- [ ] Lint/typecheck relevantes: conforme ferramentas existentes no projeto.
- [ ] Confirmar que testes novos passam.
- [ ] Confirmar que testes afetados foram atualizados.
- [ ] Confirmar que I18N foi atualizado, quando aplicável.
- [ ] Confirmar critérios de aceite do HTML visual.
- [ ] Confirmar que cada falha tem evidência e reprodução.
- [ ] Confirmar que “teclas Android impossíveis sem root” foram classificadas como limitação, não bug.

## 9. Revisão Crítica

**Resultado do advogado do diabo:** gaps abaixo.

| Severidade | Gap encontrado | Evidência | Ajuste aplicado |
|------------|----------------|-----------|-----------------|
| CRÍTICO | Smoke curto pode dar falsa sensação de pronto. | Specs listam sessão longa como lacuna real. | Exigir 30 min Tailnet e 30 min USB. |
| ALTO | Input real depende de hardware e OEM; unit test não basta. | Specs destacam teclado/mouse Bluetooth e limitações Android. | Harness manual com JSON vira gate. |
| ALTO | Falhas subjetivas de latência podem gerar discussão sem fim. | Input exige métricas de RTT/p95 e frame age. | Plano exige logs/telemetria no pacote. |
| MÉDIO | QA pode misturar problema de rede Tailscale com problema do app. | Split tunneling/DERP/MagicDNS são riscos explícitos. | Registrar rota, `tailscale status`, endpoint e modo. |

## 10. Critérios de Aprovação Humana

Estes são os itens que devem aparecer resumidos no HTML:

- Sessão Tailnet de 30 min aprovada com vídeo e input dedicado.
- Sessão USB de 30 min aprovada com vídeo e input dedicado.
- Matriz de teclado Bluetooth aprovada ou limitações sem root documentadas.
- Matriz de mouse Bluetooth aprovada: movimento relativo, botões, drag e scroll.
- Perda de foco/rede/pointer capture não deixa tecla ou botão preso.
- Pacote `qa-evidence` contém logs suficientes para revisar a aprovação.

## Status

Nada deve ser implementado até aprovação explícita.
