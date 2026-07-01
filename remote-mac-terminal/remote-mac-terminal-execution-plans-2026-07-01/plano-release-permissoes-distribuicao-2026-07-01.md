# Plano Técnico - Release, Permissões e Distribuição

**Status:** Aguardando aprovação  
**Data:** 2026-07-01  
**HTML visual:** [`plano-release-permissoes-distribuicao-2026-07-01.html`](./plano-release-permissoes-distribuicao-2026-07-01.html)

> Este Markdown é a fonte da verdade para execução. O HTML é apenas o painel visual de aprovação.

## 1. Entendimento

**Tarefa:** Transformar builds locais funcionais em um caminho de release instalável e reproduzível, cobrindo assinatura Mac, permissões macOS, notarização, Android release signing, smoke pós-instalação e documentação de warnings aceitos.

**Escopo:** scripts de build; assinatura Mac; TCC/Screen Recording/Accessibility/Input Monitoring; VirtualHID/helper; notarização/staple; Android release signing/keystore; preflight; smoke USB/Tailnet; documentação de instalação.

**Premissas:**

- O preflight já passa com warnings esperados, mas warnings de notarização/credenciais/distribuição não podem virar “normal eterno”.
- A identidade de assinatura Mac precisa estabilizar TCC; rebuilds não devem pedir permissões infinitamente.
- Release Android debug-signed é útil para teste, não para distribuição.
- Este plano não decide loja/app store. Decide pacote instalável controlado.

## 2. Exploração

**Arquivos analisados:**

| Arquivo | Por que importa |
|---------|-----------------|
| `14-DOCUMENTATION-COVERAGE-AND-STATUS.md` | Lista warnings atuais: Android release debug-signed, app/DMG sem notarização, credenciais Android ausentes. |
| `13-SECURITY-MODEL.md` | Lista permissões macOS sensíveis e logs seguros. |
| `09-TEST-PLAN.md` | Define PERM-001/002/003 e smokes de rede/input. |
| `05-INPUT-ARCHITECTURE-SPEC.md` | VirtualHID exige permissão/driver/system extension e fallback claro. |
| `04-TAILSCALE-NETWORKING-SPEC.md` | Release precisa preservar MagicDNS/IP 100.x e diagnóstico de split tunneling. |
| `07-IMPLEMENTATION-ROADMAP.md` | Coloca installer polido e produto consistente como fase final. |

**Stack identificada:** macOS signing Developer ID/Apple Development; TCC; notarização/staple; VirtualHID helper/system extension; Gradle Android; Android keystore; preflight shell; smoke scripts; Tailnet.

**Comandos de validação do projeto:**

```bash
./scripts/preflight.sh --full
./scripts/build_mac.sh
swift test
. scripts/android-env.sh && ./gradlew testDebugUnitTest
. scripts/android-env.sh && ./gradlew assembleRelease
./scripts/collect-qa-evidence.sh --tap-connect
./scripts/collect-qa-evidence.sh --no-reverse --tailnet-host mac-mini-de-gabriel.tailad333c.ts.net --expect-stream --tap-connect
```

## 3. Impacto Técnico

**Afeta contratos entre módulos?** Não deveria afetar protocolo. Afeta empacotamento, permissões, instalação, scripts e UX de onboarding.

| Área | Arquivo/módulo | Mudança necessária | Contrato afetado |
|------|----------------|-------------------|------------------|
| Mac build | `scripts/build_mac.sh` | Garantir identidade estável e assinatura não ad-hoc quando possível. | Não |
| Mac release | app bundle/DMG | Notarizar/staple e documentar warnings. | Não |
| TCC | UI Mac/onboarding | Explicar Screen Recording, Accessibility, Input Monitoring e VirtualHID. | Não |
| VirtualHID | helper/installer | Validar instalação, permissão e fallback. | Não |
| Android release | Gradle signing config/keystore | Configurar release signing real. | Não |
| Preflight | `scripts/preflight.sh` | Separar warning aceitável de bloqueador de release. | Não |
| Smoke pós-release | `scripts/collect-qa-evidence.sh` | Rodar sobre build assinado, não só debug. | Não |

**Ordem recomendada:** inventário de identidades/credenciais → Mac e Android em paralelo → smoke pós-instalação → documento de release candidate.

## 4. Testes

### Testes existentes relevantes

| Arquivo | O que cobre | Relevância |
|---------|-------------|------------|
| `scripts/preflight.sh` | Build, assinatura, warnings, ambiente. | Gate principal de release. |
| `scripts/build_mac.sh` | Build/assinatura Mac. | Precisa estabilizar identidade/TCC. |
| `09-TEST-PLAN.md` | PERM-001/002/003 e smokes funcionais. | Define comportamento sem permissões. |
| `scripts/collect-qa-evidence.sh` | Smoke pós-instalação. | Prova release instalado, não só código compilado. |
| Gradle tests/release | `testDebugUnitTest`, `assembleRelease` | Garante Android build testável e empacotável. |

### Testes que devem ser ajustados

| Arquivo | Motivo | Ação |
|---------|--------|------|
| `scripts/preflight.sh` | Warnings de release precisam ter severidade correta. | Classificar notarização/keystore como bloqueador quando alvo for release público. |
| `scripts/collect-qa-evidence.sh` | Precisa aceitar caminho/build release. | Adicionar flag se só instala debug hoje. |
| Documentação de instalação | Usuário precisa saber permissões Mac em ordem certa. | Criar/ajustar guia curto de onboarding. |
| Android Gradle config | Release debug-signed não serve para distribuição. | Configurar keystore real fora do repositório. |

### Novos testes necessários

| Módulo | Arquivo | O que testar | Tipo | Justificativa |
|--------|---------|--------------|------|---------------|
| Mac release | `qa-evidence/*` | App assinado abre, pede permissões corretas e mantém TCC após rebuild com mesma identidade. | manual/release smoke | Permissão quebrada parece bug de input/vídeo. |
| Mac release | `qa-evidence/*` | DMG/app notarizado passa Gatekeeper. | release smoke | Sem isso, instalação externa vira dor. |
| VirtualHID | `qa-evidence/*` | Helper/driver instalável no pacote release. | manual/release smoke | Input profissional depende disso. |
| Android release | `qa-evidence/*` | APK/AAB release assinado instala e conecta. | release smoke | Debug build não é distribuição. |
| Tailnet pós-release | `qa-evidence/*` | MagicDNS/IP 100.x continuam funcionando no build release. | e2e | Release pode mudar permissões/manifest/network security. |
| Input pós-release | `qa-evidence/*` | Teclado/mouse funcionam no build release. | e2e | ProGuard/R8/permissões podem quebrar caminhos. |

### Edge cases

- macOS pede TCC novamente porque a identidade mudou.
- App assinado abre, mas helper VirtualHID não instala/ativa.
- Notarização passa, mas staple/Gatekeeper falha offline.
- Android release assina, mas não instala por `applicationId`/signature conflict.
- Build release remove logs necessários para diagnóstico mínimo.
- Build release conecta vídeo, mas input falha por permissão/serviço/manifest.

### O que não precisa de teste novo

- App Store/Play Store review. Fora deste plano.
- Auto-update. Futuro.
- Installer super polido. Aqui é instalável e seguro, não marketing.
- DriverKit próprio. Fora do release atual.

## 5. I18N

**Novas strings necessárias?** Sim, para permissões/onboarding e release diagnostics, se ainda não existirem.

| Chave/área | Texto base | Módulo | Arquivo | Ação |
|------------|------------|--------|---------|------|
| mac.permission.screen_recording | “Screen Recording é necessário para capturar a tela remota selecionada.” | Mac | Settings/onboarding | Criar/ajustar |
| mac.permission.accessibility | “Accessibility é necessário para o fallback CGEvent de teclado/mouse.” | Mac | Settings/onboarding | Criar/ajustar |
| mac.permission.input_monitoring | “Input Monitoring pode ser necessário para input remoto confiável.” | Mac | Settings/onboarding | Criar/ajustar |
| mac.virtualhid.permission | “Virtual HID exige aprovação do driver/helper no macOS.” | Mac | Settings/onboarding | Criar/ajustar |
| android.release.diagnostics | “Build release: diagnóstico reduzido, sem tokens ou texto digitado.” | Android | Diagnóstico | Criar se necessário |

**Arquivos a atualizar:**

- UI/Settings Mac.
- Guia de instalação Mac.
- Gradle/Android resources, se houver texto novo.
- README de release.

**Strings hardcoded a evitar:**

- Instruções de permissão duplicadas em código e documentação.
- Mensagens genéricas de input quando falta permissão específica.
- Logs de release com segredo.

## 6. Riscos e Mitigação

| # | Risco | Probabilidade | Impacto | Mitigação |
|---|-------|---------------|---------|-----------|
| 1 | Notarização virar problema tarde demais. | Média | Release bloqueado. | Trilho de release começa em paralelo na Wave 1. |
| 2 | TCC resetar a cada rebuild. | Média | QA perde tempo e usuário perde confiança. | Identidade de assinatura estável; documentar reset esperado uma vez. |
| 3 | VirtualHID helper não entrar bem no pacote. | Média | Input profissional falha no release. | Smoke de helper no pacote release. |
| 4 | Android release assinado quebrar instalação/conexão. | Média | Build não distribuível. | Smoke pós-instalação com build release. |
| 5 | Preflight continuar aceitando warning que deveria bloquear release. | Alta | Release “meia-boca”. | Severidade depende do alvo: dev vs release. |
| 6 | Onboarding de permissão virar tutorial gigante. | Média | Usuário ignora e acha que bugou. | Mensagem curta + status objetivo + botão para abrir Settings quando possível. |

## 7. Plano de Implementação

### Wave 1: Inventário e classificação de release

- [ ] Passo 1.1: Rodar `./scripts/preflight.sh --full` -> Verificação: warnings classificados como dev-only ou release-blocker.
- [ ] Passo 1.2: Identificar identidade Mac disponível: Developer ID / Apple Development / ad-hoc -> Verificação: log de assinatura anexado.
- [ ] Passo 1.3: Identificar estado da notarização/staple -> Verificação: matriz “não configurado / configurado / aprovado”.
- [ ] Passo 1.4: Identificar keystore Android release -> Verificação: release signing real ou bloqueador explícito.

### Wave 2: Mac e Android em paralelo

- [ ] Passo 2.M1: Rodar `./scripts/build_mac.sh` com identidade estável -> Verificação: app assinado sem ad-hoc quando possível.
- [ ] Passo 2.M2: Abrir app assinado e conceder permissões -> Verificação: Screen Recording/Accessibility/Input Monitoring reconhecidas.
- [ ] Passo 2.M3: Validar VirtualHID/helper no build assinado -> Verificação: backend ativo ou fallback claro.
- [ ] Passo 2.A1: Configurar Android release signing fora do repositório -> Verificação: `assembleRelease` gera artefato assinado.
- [ ] Passo 2.A2: Instalar build release no tablet -> Verificação: instala/abre sem conflito de assinatura.
- [ ] Passo 2.A3: Confirmar que diagnóstico release não vaza segredo -> Verificação: logs inspecionados.

### Wave 3: Notarização e smoke pós-release

- [ ] Passo 3.1: Notarizar/staple app/DMG Mac se credenciais estiverem disponíveis -> Verificação: Gatekeeper aceita pacote.
- [ ] Passo 3.2: Rodar smoke USB no build release -> Verificação: vídeo + input funcionam.
- [ ] Passo 3.3: Rodar smoke Tailnet no build release -> Verificação: MagicDNS/IP 100.x e input `P/P+1` funcionam.
- [ ] Passo 3.4: Rodar input QA mínimo no release -> Verificação: teclado/mouse e backend ativo.

### Wave 4: Documentação de instalação e decisão de release

- [ ] Passo 4.1: Criar/atualizar guia curto de instalação Mac -> Verificação: permissões explicadas na ordem certa.
- [ ] Passo 4.2: Criar/atualizar guia curto Android -> Verificação: Tailscale, split tunneling e pairing explicados.
- [ ] Passo 4.3: Atualizar preflight para falhar release quando faltar notarização/keystore -> Verificação: modo dev continua permitindo warnings, modo release não.
- [ ] Passo 4.4: Emitir decisão RC -> Verificação: release aprovado, bloqueado ou dev-only assumido.

## 8. Checklist de Validação

- [ ] Build dos módulos alterados: `./scripts/build_mac.sh`, `swift test`, `. scripts/android-env.sh && ./gradlew testDebugUnitTest`, `. scripts/android-env.sh && ./gradlew assembleRelease`.
- [ ] Testes relevantes: `./scripts/preflight.sh --full`, smoke USB e smoke Tailnet.
- [ ] Lint/typecheck relevantes: conforme ferramentas existentes.
- [ ] Confirmar que testes novos passam.
- [ ] Confirmar que testes afetados foram atualizados.
- [ ] Confirmar que I18N foi atualizado, quando aplicável.
- [ ] Confirmar critérios de aceite do HTML visual.
- [ ] Confirmar assinatura Mac estável.
- [ ] Confirmar permissões macOS reconhecidas.
- [ ] Confirmar Android release signing real ou bloqueador explícito.
- [ ] Confirmar notarização/staple ou decisão dev-only documentada.

## 9. Revisão Crítica

**Resultado do advogado do diabo:** gaps abaixo.

| Severidade | Gap encontrado | Evidência | Ajuste aplicado |
|------------|----------------|-----------|-----------------|
| ALTO | Build local funcional não significa release instalável. | Status cita warnings de notarização/credenciais. | Release vira trilho próprio. |
| ALTO | Permissões macOS podem quebrar input/vídeo sem bug no código. | Security model lista TCC e VirtualHID. | Smoke pós-assinatura e onboarding. |
| MÉDIO | Android debug-signed pode esconder problemas de release. | Status cita release debug-signed. | `assembleRelease` e instalação real viram gate. |
| MÉDIO | Preflight pode tratar bloqueador como warning. | Warnings aceitáveis dependem do alvo. | Separar modo dev e modo release. |

## 10. Critérios de Aprovação Humana

Estes são os itens que devem aparecer resumidos no HTML:

- App Mac assinado abre e reconhece permissões necessárias.
- TCC não fica resetando sem motivo após rebuild com mesma identidade.
- VirtualHID/helper funciona no pacote assinado ou fallback CGEvent aparece claramente.
- APK/AAB release assinado instala e conecta no tablet.
- Build release passa smoke USB e Tailnet.
- Notarização/staple está feita ou o release é explicitamente marcado como dev-only.
- Guia curto de instalação cobre permissões Mac, Tailscale Android e re-pair.

## Status

Nada deve ser implementado até aprovação explícita.
