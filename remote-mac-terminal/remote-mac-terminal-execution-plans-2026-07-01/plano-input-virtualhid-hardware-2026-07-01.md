# Plano Técnico - Input Real, VirtualHID e Fallback CGEvent

**Status:** Aguardando aprovação  
**Data:** 2026-07-01  
**HTML visual:** [`plano-input-virtualhid-hardware-2026-07-01.html`](./plano-input-virtualhid-hardware-2026-07-01.html)

> Este Markdown é a fonte da verdade para execução. O HTML é apenas o painel visual de aprovação.

## 1. Entendimento

**Tarefa:** Validar e endurecer a experiência de input real: teclado/mouse Bluetooth no Android, canal Remote Input Protocol v1, InputIngress no Mac, backend VirtualHID como principal prático e CGEvent como fallback explícito.

**Escopo:** `InputClient.kt`; `RemoteInputBridge.kt`; `RemoteKeyboardCapture`; `RemoteMouseCapture`; `SideScreenAccessibilityService.kt`; `RemoteInputProtocol.kt/.swift`; `InputServer.swift`; `InputIngress.swift`; `CGEventInputBackend.swift`; `KarabinerVirtualHIDBackend.swift`; helper/installer VirtualHID; diagnóstico de backend ativo.

**Premissas:**

- O protocolo v1 já existe e não deve ser redesenhado nesta rodada.
- Teclas de sistema Android sem root não são bug se o Android não as entrega.
- VirtualHID é o backend desejado para experiência próxima de hardware; CGEvent continua fallback.
- O foco é provar comportamento em apps reais do macOS, não apenas em teste unitário.

## 2. Exploração

**Arquivos analisados:**

| Arquivo | Por que importa |
|---------|-----------------|
| `05-INPUT-ARCHITECTURE-SPEC.md` | Define backends Android, InputIngress, fail-safe, VirtualHID e regras de mapeamento. |
| `11-REMOTE-INPUT-PROTOCOL-V1.md` | Define eventos, sequence, timestamp, `AllInputsUp`, ping/pong e observabilidade. |
| `06-ANDROID-LIMITATIONS-AND-ROOT-PLAN.md` | Define limites sem root e escopo do futuro root. |
| `09-TEST-PLAN.md` | Define KEY, MOU e LAT, incluindo stuck key, pointer capture, botões, drag e scroll. |
| `13-SECURITY-MODEL.md` | Define stuck keys como requisito de segurança. |
| `14-DOCUMENTATION-COVERAGE-AND-STATUS.md` | Marca VirtualHID implementado, mas ainda pendente de smoke real em máquina real. |

**Stack identificada:** Android `KeyEvent`, `MotionEvent`, pointer capture, Accessibility Assist; protocolo binário HID-like; Mac `InputServer`, `InputIngress`, CGEvent, Karabiner VirtualHID/helper; diagnósticos de latência e backend.

**Comandos de validação do projeto:**

```bash
swift test
. scripts/android-env.sh && ./gradlew testDebugUnitTest
./scripts/open-input-qa.sh
./scripts/collect-qa-evidence.sh --tap-connect
./scripts/collect-qa-evidence.sh --no-reverse --tailnet-host mac-mini-de-gabriel.tailad333c.ts.net --expect-stream --tap-connect
```

## 3. Impacto Técnico

**Afeta contratos entre módulos?** Sim, qualquer alteração em input pode afetar protocolo, sessão, backends e segurança. Correções devem ser pequenas, com testes.

| Área | Arquivo/módulo | Mudança necessária | Contrato afetado |
|------|----------------|-------------------|------------------|
| Protocolo | `RemoteInputProtocol.kt`, `RemoteInputProtocol.swift` | Não alterar framing v1 salvo bug comprovado. | Sim |
| Android teclado | `RemoteKeyboardCapture`, `RemoteInputBridge.kt`, `SideScreenAccessibilityService.kt` | Validar duplicatas Activity/Accessibility, mapeamento e diagnóstico. | Sim |
| Android mouse | `RemoteMouseCapture`, `InputClient.kt` | Validar coalescing, pointer capture, flush antes de botões/teclado/wheel. | Sim |
| Mac ingress | `InputIngress.swift` | Validar pressed state, sequence, watchdog, release-all e latência. | Sim |
| CGEvent | `CGEventInputBackend.swift` | Garantir fallback previsível quando VirtualHID indisponível. | Não |
| VirtualHID | `KarabinerVirtualHIDBackend.swift`, helper/installer | Validar teclado/mouse como dispositivo real e permissões. | Sim |
| Diagnóstico | UI Mac/Android, `DiagLog.kt` | Mostrar backend ativo, fallback e motivos de release-all. | Não |

**Ordem recomendada:** protocolo/estado verde → input hardware com CGEvent → VirtualHID real → fallback/permissões → regressão sob carga.

## 4. Testes

### Testes existentes relevantes

| Arquivo | O que cobre | Relevância |
|---------|-------------|------------|
| `MacHost/Tests/SideScreenTests/*RemoteInput*` | Framing, parsing, sequence e eventos no Mac. | Protege protocolo. |
| `MacHost/Tests/SideScreenTests/*InputIngress*` | Pressed state, release-all e coalescing. | Protege contra stuck keys. |
| `AndroidClient/app/src/test/*RemoteInput*` | Serialização Android e cliente de input. | Protege compatibilidade com Mac. |
| `09-TEST-PLAN.md` | KEY-001 a KEY-004, MOU-001 a MOU-004, LAT-001 a LAT-003. | Matriz manual. |
| `scripts/open-input-qa.sh` | QA real de input. | Gate de hardware. |

### Testes que devem ser ajustados

| Arquivo | Motivo | Ação |
|---------|--------|------|
| `scripts/open-input-qa.sh` | Precisa separar resultado CGEvent vs VirtualHID. | Incluir backend ativo, fallback, permissões e app testado. |
| Testes de `InputIngress` | Revogação/gap de sequência com tecla pressionada precisa ser protegido. | Adicionar caso se ainda não existir. |
| Testes Android de `TextCommit` | Texto grande/dead keys não pode quebrar payload. | Garantir chunk por UTF-8/codepoint. |
| Testes de mouse | Coalescing não pode atravessar botão/wheel/teclado. | Adicionar caso se ausente. |

### Novos testes necessários

| Módulo | Arquivo | O que testar | Tipo | Justificativa |
|--------|---------|--------------|------|---------------|
| VirtualHID | `qa-evidence/*` | Digitação no Terminal/TextEdit com backend VirtualHID ativo. | manual/e2e | Prova input real em app comum. |
| VirtualHID | `qa-evidence/*` | Atalhos Finder/navegador/editor: Command+C/V/W/Tab quando Meta chegar. | manual/e2e | Prova experiência Mac-like. |
| Fallback | `qa-evidence/*` | VirtualHID indisponível cai para CGEvent com UI clara. | manual/e2e | Evita falha silenciosa. |
| Mouse | `scripts/open-input-qa.sh` | Drag durante queda de conexão/pointer capture lost. | manual/e2e | Evita botão preso. |
| Input latency | logs/diagnóstico | RTT último/média/p95 do canal de input sob vídeo pesado. | manual/e2e | Input deve vencer vídeo. |
| Accessibility | `SideScreenAccessibilityService.kt` + harness | Duplicatas Activity/Accessibility não geram down/up duplo. | integration/manual | Modo assistido pode duplicar evento. |

### Edge cases

- Meta/Super entregue por alguns tablets, engolido por outros.
- `KeyDown` duplicado sem `KeyUp` intermediário.
- `KeyUp` sem `KeyDown`.
- `PointerRelative` acumulado antes de um botão; flush precisa ocorrer antes do botão.
- Perda de pointer capture no meio de drag.
- `TextCommit` com emoji/acentos/dead keys e payload grande.
- VirtualHID instalado, mas sem permissão ativa.
- CGEvent permitido para mouse, mas não para teclado por falta de Accessibility/Input Monitoring.

### O que não precisa de teste novo

- Home/Power/Recents sem root como requisito de sucesso.
- Root evdev. Só discovery futuro.
- DriverKit próprio. Não entra nesta rodada.
- Protocolo v2. O v1 basta para hardening atual.

## 5. I18N

**Novas strings necessárias?** Sim, se diagnóstico atual não mostrar estado de backend/permissão.

| Chave/área | Texto base | Módulo | Arquivo | Ação |
|------------|------------|--------|---------|------|
| input.backend.virtualhid | “Backend de input ativo: Virtual HID.” | Mac | Settings/diagnóstico | Criar/ajustar |
| input.backend.cgevent | “Backend de input ativo: CGEvent fallback.” | Mac | Settings/diagnóstico | Criar/ajustar |
| input.virtualhid_unavailable | “Virtual HID indisponível; usando fallback CGEvent.” | Mac | Settings/diagnóstico | Criar/ajustar |
| input.permission_missing | “Permissão de input ausente. Vídeo pode funcionar, mas teclado/mouse remoto não.” | Mac | Settings/onboarding | Criar/ajustar |
| input.android_system_key_limit | “Esta tecla pode ser consumida pelo Android sem root.” | Android | Diagnóstico input | Criar/ajustar |

**Arquivos a atualizar:**

- UI/Settings Mac.
- UI/diagnóstico Android.
- `AndroidClient/app/src/main/res/values/strings.xml`, se existir.
- Documentação de limitações se as mensagens mudarem.

**Strings hardcoded a evitar:**

- “VirtualHID failed” sem orientar permissão/fallback.
- “Key unsupported” sem separar “Android não entregou” de “mapeamento ausente”.
- Qualquer log de texto digitado.

## 6. Riscos e Mitigação

| # | Risco | Probabilidade | Impacto | Mitigação |
|---|-------|---------------|---------|-----------|
| 1 | VirtualHID funcionar em teste isolado e falhar em app real. | Média | Experiência não fica Mac-like. | Testar Terminal, Finder, navegador e editor. |
| 2 | CGEvent mascarar falha do VirtualHID. | Média | Aprovação errada. | Diagnóstico deve mostrar backend ativo. |
| 3 | Accessibility duplicar eventos da Activity. | Média | Teclas repetidas ou presas. | Deduplicação e testes com flag de origem. |
| 4 | Coalescing de mouse atravessar botão/wheel. | Baixa/Média | Drag/scroll quebrado. | Testes específicos de flush antes de eventos críticos. |
| 5 | Layout ABNT2 virar escopo infinito. | Alta | Atraso. | Baseline US + casos ABNT2 essenciais; documentar limites. |
| 6 | Permissões macOS confundirem usuário. | Alta | Input parece quebrado. | Onboarding/diagnóstico com backend e permissão exatos. |

## 7. Plano de Implementação

### Wave 1: Sanidade de protocolo e estado

- [ ] Passo 1.1: Rodar testes Mac de protocolo/InputIngress -> Verificação: framing, sequence, release-all e coalescing verdes.
- [ ] Passo 1.2: Rodar testes Android de `RemoteInputProtocol`/`InputClient` -> Verificação: serialização compatível com Mac.
- [ ] Passo 1.3: Revisar se `AllInputsUp` tem motivo em lifecycle/pointer lost/disconnect -> Verificação: logs registram motivo.
- [ ] Passo 1.4: Confirmar que logs não exibem texto digitado/token -> Verificação: amostra de log sem conteúdo sensível.

### Wave 2: QA real com CGEvent fallback

- [ ] Passo 2.1: Forçar/selecionar CGEvent backend -> Verificação: UI/log mostra CGEvent ativo.
- [ ] Passo 2.2: Testar teclado comum e modificadores -> Verificação: sem stuck key, limitações sem root documentadas.
- [ ] Passo 2.3: Testar mouse relativo, botões, drag e scroll -> Verificação: sem botão preso e sem backlog.
- [ ] Passo 2.4: Rodar input sob vídeo pesado -> Verificação: input não fica visivelmente atrás; RTT/p95 coletado.

### Wave 3: QA real com VirtualHID

- [ ] Passo 3.1: Instalar/ativar helper/Karabiner VirtualHID conforme caminho atual do projeto -> Verificação: backend VirtualHID aparece ativo.
- [ ] Passo 3.2: Testar Terminal/TextEdit -> Verificação: digitação e modificadores corretos.
- [ ] Passo 3.3: Testar Finder/navegador/editor -> Verificação: atalhos comuns e mouse funcionam.
- [ ] Passo 3.4: Desativar/quebrar VirtualHID controladamente -> Verificação: fallback CGEvent claro, sem crash.
- [ ] Passo 3.5: Registrar diferenças CGEvent vs VirtualHID -> Verificação: tabela de comportamento por app.

### Wave 4: Correções cirúrgicas

- [ ] Passo 4.1: Corrigir apenas falhas que bloqueiam input diário, segurança ou diagnóstico -> Verificação: teste específico para cada correção.
- [ ] Passo 4.2: Reexecutar matriz mínima afetada -> Verificação: não regressão no backend alternativo.
- [ ] Passo 4.3: Atualizar docs de limitação sem root/layout -> Verificação: usuário não recebe promessa falsa.

## 8. Checklist de Validação

- [ ] Build dos módulos alterados: `swift test` e `. scripts/android-env.sh && ./gradlew testDebugUnitTest`
- [ ] Testes relevantes: `./scripts/open-input-qa.sh`
- [ ] Lint/typecheck relevantes: conforme ferramentas existentes.
- [ ] Confirmar que testes novos passam.
- [ ] Confirmar que testes afetados foram atualizados.
- [ ] Confirmar que I18N foi atualizado, quando aplicável.
- [ ] Confirmar critérios de aceite do HTML visual.
- [ ] Confirmar backend ativo visível no diagnóstico.
- [ ] Confirmar que VirtualHID e CGEvent fallback têm evidência separada.
- [ ] Confirmar que nenhuma falha deixa tecla/botão preso.

## 9. Revisão Crítica

**Resultado do advogado do diabo:** gaps abaixo.

| Severidade | Gap encontrado | Evidência | Ajuste aplicado |
|------------|----------------|-----------|-----------------|
| CRÍTICO | VirtualHID pode estar “implementado” e ainda não ser confiável em uso real. | Status aponta smoke real como lacuna. | Plano exige testes em apps reais. |
| ALTO | CGEvent fallback pode esconder que VirtualHID não está ativo. | Dois backends coexistem. | Diagnóstico de backend ativo é critério de aceite. |
| ALTO | Sem root, algumas teclas nunca chegam. | Specs de limitações Android. | Critério separa limitação Android de bug do protocolo. |
| MÉDIO | Layout/acentos podem inflar escopo. | Specs recomendam baseline US e documentar ABNT2. | Corrigir bloqueadores; documentar o resto. |

## 10. Critérios de Aprovação Humana

Estes são os itens que devem aparecer resumidos no HTML:

- VirtualHID funciona em Terminal, Finder, navegador e editor com backend ativo visível.
- CGEvent fallback funciona e aparece claramente quando VirtualHID não está disponível.
- Teclado Bluetooth passa no essencial sem stuck keys.
- Mouse Bluetooth passa em movimento relativo, botões, drag e scroll.
- `AllInputsUp` funciona em perda de foco, pointer capture lost, disconnect e erro de backend.
- Limitações sem root são diagnosticadas sem prometer captura impossível.

## Status

Nada deve ser implementado até aprovação explícita.
