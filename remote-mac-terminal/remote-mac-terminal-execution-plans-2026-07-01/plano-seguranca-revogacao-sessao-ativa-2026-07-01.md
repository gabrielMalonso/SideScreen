# Plano Técnico - Segurança, Revogação e Sessão Ativa

**Status:** Aguardando aprovação  
**Data:** 2026-07-01  
**HTML visual:** [`plano-seguranca-revogacao-sessao-ativa-2026-07-01.html`](./plano-seguranca-revogacao-sessao-ativa-2026-07-01.html)

> Este Markdown é a fonte da verdade para execução. O HTML é apenas o painel visual de aprovação.

## 1. Entendimento

**Tarefa:** Validar que o controle remoto do Mac é seguro em sessão real: revogação, reset de token, rejeição de input sem sessão, logs sem segredo e fail-safe de todos os inputs pressionados.

**Escopo:** `WirelessAuth.swift`; `AuthHandshake.kt`; `RemoteSessionStore.swift`; `InputServer.swift`; `InputIngress.swift`; `AppDelegate`; UI de revogação/reset; logs Mac/Android; scripts de evidência.

**Premissas:**

- Tailscale reduz exposição de rede, mas não substitui autenticação da aplicação.
- Revogação/reset já existem segundo o status, mas ainda precisam QA manual durante stream ativo.
- Input sem sessão válida deve ser rejeitado antes de qualquer payload ser processado.
- Stuck key é problema de segurança, não só UX.

## 2. Exploração

**Arquivos analisados:**

| Arquivo | Por que importa |
|---------|-----------------|
| `13-SECURITY-MODEL.md` | Define modelo de ameaça, tokens, revogação, logs seguros, permissões e fail-safe. |
| `12-SESSION-AND-TRANSPORT-SPEC.md` | Define sessão, channel authorization e erros de auth/canal. |
| `11-REMOTE-INPUT-PROTOCOL-V1.md` | Define rejeição de canal sem sessão e release-all em erro fatal. |
| `05-INPUT-ARCHITECTURE-SPEC.md` | Define estados pressionados e release-all em disconnect/session invalidada. |
| `09-TEST-PLAN.md` | Define SEC-001, SEC-002, SEC-003 e lifecycle/fail-safe. |
| `14-DOCUMENTATION-COVERAGE-AND-STATUS.md` | Indica que revogação/reset melhoraram, mas QA durante stream ativo ainda é lacuna. |

**Stack identificada:** token/pairing legacy; device registry; sessão temporária; input channel dedicado; `InputIngress`; `AllInputsUp`; logs com redaction; UI Mac de revoke/reset; Android re-pair.

**Comandos de validação do projeto:**

```bash
swift test
. scripts/android-env.sh && ./gradlew testDebugUnitTest
./scripts/preflight.sh --full
./scripts/collect-qa-evidence.sh --tap-connect
./scripts/collect-qa-evidence.sh --no-reverse --tailnet-host mac-mini-de-gabriel.tailad333c.ts.net --expect-stream --tap-connect
```

## 3. Impacto Técnico

**Afeta contratos entre módulos?** Sim. Segurança toca sessão, input channel, UI de pairing e logs.

| Área | Arquivo/módulo | Mudança necessária | Contrato afetado |
|------|----------------|-------------------|------------------|
| Pairing/token | `WirelessAuth.swift`, `AuthHandshake.kt` | Validar token inválido/reset; não logar segredo. | Sim |
| Device registry | `RemoteSessionStore.swift` | Confirmar revogação persistente e reset geral. | Sim |
| Sessão ativa | `AppDelegate`, `InputServer.swift`, `StreamingServer.swift` | Revogação deve derrubar stream/input ativos. | Sim |
| Input safety | `InputIngress.swift`, `CGEventInputBackend.swift`, `KarabinerVirtualHIDBackend.swift` | Release-all obrigatório em revogação, disconnect e erro. | Sim |
| Logs | `DiagLog.kt`, logs Mac | Remover token, texto digitado, auth tags completos. | Não |
| UI | Mac Settings/Android conexão | Mensagens de revogação e re-pair. | Não |

**Ordem recomendada:** testes automatizados de auth → smoke ativo → revogação durante stream → reset token → inspeção de logs → correções mínimas.

## 4. Testes

### Testes existentes relevantes

| Arquivo | O que cobre | Relevância |
|---------|-------------|------------|
| `09-TEST-PLAN.md` | SEC-001 token inválido, SEC-002 input sem sessão, SEC-003 revogação futura. | Matriz de segurança. |
| `MacHost/Tests/SideScreenTests/*Session*` | Sessão, registry, revogação, token, auth. | Protege autorização. |
| `MacHost/Tests/SideScreenTests/*InputIngress*` | Release-all, sequence, pressed state. | Protege stuck keys. |
| `AndroidClient/app/src/test/*Auth*` | Handshake/pairing Android. | Protege rejeição/re-pair. |
| `scripts/collect-qa-evidence.sh` | Smoke real e logs. | Precisa guardar evidência de revogação. |

### Testes que devem ser ajustados

| Arquivo | Motivo | Ação |
|---------|--------|------|
| Testes de `RemoteSessionStore` | Revogação de device ativo precisa invalidar sessão ativa. | Adicionar caso se ausente. |
| Testes de `InputServer` | Canal de input de device revogado precisa ser rejeitado antes do payload. | Adicionar caso se ausente. |
| Scripts de evidência | Revogação ativa precisa aparecer no pacote. | Adicionar marcador/log de revoke/reset se ausente. |
| Diagnóstico Android | Re-pair precisa ser claro após revoke/reset. | Ajustar mensagem se opaca. |

### Novos testes necessários

| Módulo | Arquivo | O que testar | Tipo | Justificativa |
|--------|---------|--------------|------|---------------|
| Sessão ativa | `qa-evidence/*` | Revogar tablet com stream e input ativos. | manual/e2e | Lacuna real explícita. |
| Sessão ativa | `qa-evidence/*` | Reset token durante sessão ativa. | manual/e2e | Deve derrubar acesso antigo. |
| Input auth | teste Mac/integração | Abrir input channel sem sessão/token. | integration | Não pode haver input anônimo. |
| Logs | `qa-evidence/*` | Inspecionar logs após auth/revoke/input. | manual/security | Não logar token/texto/auth tag. |
| Fail-safe | `qa-evidence/*` | Revogar segurando tecla/botão. | manual/e2e | Release-all precisa ser garantido. |

### Edge cases

- Revogar tablet no meio de drag.
- Resetar token enquanto Android tenta reconectar.
- Input channel permanece conectado depois que vídeo cai.
- Vídeo permanece por alguns segundos, mas input já deveria estar bloqueado.
- Tablet revogado ainda tem QR/token antigo salvo.
- Logs de erro mostram prefixo de token ou texto digitado.
- Sessão cai sem close limpo; watchdog precisa soltar inputs.

### O que não precisa de teste novo

- Criptografia app-level adicional sobre Tailscale. Futuro de hardening, não gate atual.
- Chaves assimétricas por device, se o fluxo atual ainda está em token/sessionToken legacy. Futuro Alpha avançado.
- Root security. Só quando RootEvdevBackend existir.

## 5. I18N

**Novas strings necessárias?** Sim, se UI atual não orientar re-pair/revogação.

| Chave/área | Texto base | Módulo | Arquivo | Ação |
|------------|------------|--------|---------|------|
| auth.device_revoked | “Este tablet foi revogado. Escaneie um novo QR para parear novamente.” | Android | UI conexão | Criar/ajustar |
| auth.token_reset | “O token de pareamento foi redefinido. Faça o pareamento novamente.” | Android/Mac | UI conexão/Settings | Criar/ajustar |
| auth.input_rejected | “Canal de input rejeitado: sessão inválida ou expirada.” | Android/Mac | Diagnóstico | Criar/ajustar |
| security.release_all | “Inputs soltos por segurança.” | Mac/Android | Diagnóstico input | Criar/ajustar |

**Arquivos a atualizar:**

- UI Mac de settings/revogação.
- UI Android de conexão/diagnóstico.
- `AndroidClient/app/src/main/res/values/strings.xml`, se existir.

**Strings hardcoded a evitar:**

- Token completo ou prefixo longo.
- Auth tag.
- Texto digitado.
- Mensagens genéricas tipo “connection failed” quando o motivo é device revoked.

## 6. Riscos e Mitigação

| # | Risco | Probabilidade | Impacto | Mitigação |
|---|-------|---------------|---------|-----------|
| 1 | Revogação rejeitar reconexão, mas não derrubar sessão ativa. | Média | Controle remoto continua ativo. | Teste manual durante stream + teste automatizado. |
| 2 | Input channel aceitar payload antes de auth. | Baixa/Média | Controle não autorizado. | Teste de canal sem sessão e validação antes de parsing. |
| 3 | Release-all falhar durante revogação segurando tecla. | Média | Ação destrutiva no Mac. | Caso específico segurando tecla/botão. |
| 4 | Logs vazarem segredo. | Média | Risco de segurança e reuso de token. | Inspeção de logs como gate. |
| 5 | Reset token quebrar pairing legítimo sem mensagem clara. | Média | UX ruim. | Mensagem re-pair e diagnóstico específico. |

## 7. Plano de Implementação

### Wave 1: Baseline de segurança automatizado

- [ ] Passo 1.1: Rodar testes Mac de sessão/registry/auth -> Verificação: revogação e token inválido verdes.
- [ ] Passo 1.2: Rodar testes Android de auth/pairing -> Verificação: token inválido/re-pair tratados.
- [ ] Passo 1.3: Rodar testes de InputIngress -> Verificação: release-all em disconnect/protocol error.
- [ ] Passo 1.4: Inspecionar logs de teste -> Verificação: nenhum token/texto digitado/auth tag completo.

### Wave 2: Revogação em sessão real

- [ ] Passo 2.1: Conectar tablet via Tailnet com vídeo e input -> Verificação: stream e input channel ativos.
- [ ] Passo 2.2: Segurar modificador ou botão do mouse -> Verificação: Mac registra pressed state ou evento equivalente.
- [ ] Passo 2.3: Revogar tablet pelo Mac -> Verificação: stream/input ativos caem.
- [ ] Passo 2.4: Confirmar release-all -> Verificação: nenhuma tecla/botão fica preso.
- [ ] Passo 2.5: Tentar reconectar sem novo QR -> Verificação: rejeição explícita.
- [ ] Passo 2.6: Escanear novo QR e reconectar -> Verificação: re-pair recupera uso legítimo.

### Wave 3: Reset token e canal inválido

- [ ] Passo 3.1: Resetar token durante sessão ativa -> Verificação: sessão antiga cai ou fica invalidada conforme política definida.
- [ ] Passo 3.2: Tentar abrir input channel sem sessão válida -> Verificação: Mac rejeita antes de payload.
- [ ] Passo 3.3: Tentar token antigo salvo no Android -> Verificação: Android mostra re-pair.
- [ ] Passo 3.4: Validar logs Mac/Android -> Verificação: segredos não aparecem.

### Wave 4: Correções e regressão

- [ ] Passo 4.1: Corrigir apenas falhas `BLOCKER/HIGH` -> Verificação: teste específico para cada falha.
- [ ] Passo 4.2: Reexecutar smoke Tailnet -> Verificação: segurança não quebrou conexão normal.
- [ ] Passo 4.3: Reexecutar input QA mínimo -> Verificação: fail-safe continua funcionando.

## 8. Checklist de Validação

- [ ] Build dos módulos alterados: `swift test` e `. scripts/android-env.sh && ./gradlew testDebugUnitTest`
- [ ] Testes relevantes: `./scripts/preflight.sh --full` e smoke Tailnet.
- [ ] Lint/typecheck relevantes: conforme ferramentas existentes.
- [ ] Confirmar que testes novos passam.
- [ ] Confirmar que testes afetados foram atualizados.
- [ ] Confirmar que I18N foi atualizado, quando aplicável.
- [ ] Confirmar critérios de aceite do HTML visual.
- [ ] Confirmar que revogação derruba sessão ativa.
- [ ] Confirmar que input sem sessão não injeta nada.
- [ ] Confirmar que logs não vazam segredos.

## 9. Revisão Crítica

**Resultado do advogado do diabo:** gaps abaixo.

| Severidade | Gap encontrado | Evidência | Ajuste aplicado |
|------------|----------------|-----------|-----------------|
| CRÍTICO | “Revogado” pode significar só “não reconecta”, não “derruba agora”. | Status diz que ainda precisa QA revogando durante stream. | Teste manual obrigatório com stream ativo. |
| CRÍTICO | Canal de input é mais sensível que vídeo. | App controla teclado/mouse do Mac. | Rejeitar input sem sessão antes de payload. |
| ALTO | Tecla presa após revoke pode executar ação destrutiva. | Fail-safe é requisito de segurança. | Testar revoke segurando tecla/botão. |
| MÉDIO | Logs podem vazar dados em caminhos de erro. | Security model proíbe tokens/texto/auth tags completos. | Inspeção de logs vira gate. |

## 10. Critérios de Aprovação Humana

Estes são os itens que devem aparecer resumidos no HTML:

- Revogar tablet durante stream ativo derruba vídeo e input.
- Reset token invalida sessão/token antigo conforme política definida.
- Input channel sem sessão válida é rejeitado antes de processar evento.
- Revogação durante tecla/botão pressionado dispara release-all.
- Logs não contêm token, auth tag completo, texto digitado ou dados sensíveis.
- Android mostra re-pair/motivo correto após revogação/reset.

## Status

Nada deve ser implementado até aprovação explícita.
