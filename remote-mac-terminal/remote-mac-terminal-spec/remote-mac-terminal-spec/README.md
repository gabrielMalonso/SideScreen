# Remote Mac Terminal for Android Tablet — documentação de arquitetura

Data: 2026-06-30  
Base analisada: `SideScreen-source-macos-android-2026-06-30.zip`  
Objetivo: transformar um tablet Android com teclado e mouse Bluetooth em um terminal remoto para um Mac mini via Tailscale, com experiência o mais próxima possível de um MacBook remoto.

## Como usar esta documentação no Codex

Comece por `00-CODEX-START-HERE.md`. Ele contém o briefing operacional para uma sessão de Codex.

A documentação foi estruturada para permitir evolução incremental: primeiro sem root, depois com backends opcionais de Accessibility e root. A intenção é evitar uma reescrita desnecessária do motor de vídeo do SideScreen e concentrar o projeto em sessão, rede Tailnet e input.

## Índice recomendado de leitura

1. `00-CODEX-START-HERE.md` — instruções para o Codex e limites da primeira fase.
2. `01-PROJECT-BRIEF.md` — contexto, objetivo de produto e critérios de sucesso.
3. `02-SIDESCREEN-DEEP-DIVE.md` — análise do SideScreen existente.
4. `03-TARGET-ARCHITECTURE.md` — arquitetura final recomendada.
5. `04-TAILSCALE-NETWORKING-SPEC.md` — adaptação para Tailnet/MagicDNS/IP 100.x.
6. `05-INPUT-ARCHITECTURE-SPEC.md` — arquitetura profissional do canal de input.
7. `06-ANDROID-LIMITATIONS-AND-ROOT-PLAN.md` — limitações sem root e plano posterior com root.
8. `07-IMPLEMENTATION-ROADMAP.md` — MVP, Alpha, Beta e versão final.
9. `08-CODEX-TASK-BACKLOG.md` — backlog técnico acionável para desenvolvimento.
10. `09-TEST-PLAN.md` — plano de validação funcional, rede, latência e input.
11. `10-RISKS-AND-OPEN-QUESTIONS.md` — riscos arquiteturais e decisões resolvidas/condicionais.
12. `11-REMOTE-INPUT-PROTOCOL-V1.md` — especificação do protocolo de input.
13. `12-SESSION-AND-TRANSPORT-SPEC.md` — sessão, canais e transporte.
14. `13-SECURITY-MODEL.md` — modelo de segurança.
15. `14-DOCUMENTATION-COVERAGE-AND-STATUS.md` — matriz de cobertura, estado atual e definição de documentação 100%.
16. `adr/` — decisões arquiteturais registradas.
17. `appendix/` — referências de código do SideScreen e referências externas.

## Resumo executivo

A conclusão principal é: não transformar o SideScreen inteiro no produto final. O SideScreen deve ser tratado como um motor de vídeo muito bom, mas o produto desejado é outro: um terminal remoto de Mac com input de alta fidelidade e sessão robusta via Tailnet.

A arquitetura recomendada é:

```text
SideScreen video engine
+
novo session/transport layer
+
novo remote HID input system
+
Tailscale como underlay de rede
```

O desenvolvimento deve começar sem root. Isso valida vídeo, Tailscale, sessão, latência real, mouse capture, teclado comum e UX. Root deve ser uma fase posterior, implementada como backend opcional de captura de input, não como premissa do produto.

Para continuar o projeto sem se perder em backlog antigo, leia `14-DOCUMENTATION-COVERAGE-AND-STATUS.md` antes de implementar. Ele separa o que já existe, o que está documentado e o que é futuro intencional.
