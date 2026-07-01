# Prompt sugerido para iniciar uma sessão no Codex

Use este prompt como mensagem inicial para o Codex na sua máquina, com o repositório aberto localmente.

---

Estou trabalhando em um fork/novo projeto baseado no SideScreen para transformar um tablet Android em um Remote Desktop minimalista para um Mac mini via Tailscale.

A ideia central é substituir, para uso pessoal, Google Remote Desktop/Chrome Remote Desktop ou AnyDesk: ver e controlar as telas reais que já existem no Mac. O modo segundo monitor/Virtual Display é secundário.

Leia primeiro toda a documentação em `remote-mac-terminal-spec/`, começando por:

1. `00-CODEX-START-HERE.md`
2. `14-DOCUMENTATION-COVERAGE-AND-STATUS.md`
3. `02-SIDESCREEN-DEEP-DIVE.md`
4. `03-TARGET-ARCHITECTURE.md`
5. `04-TAILSCALE-NETWORKING-SPEC.md`
6. `05-INPUT-ARCHITECTURE-SPEC.md`
7. `08-CODEX-TASK-BACKLOG.md`

Depois, inspecione o código atual do repositório. Não implemente nada antes de confirmar que entendeu:

- como o SideScreen cria o Virtual Display;
- como a captura poderia receber uma tela real existente como `DisplaySource`;
- como captura/codifica vídeo;
- como o Android decodifica vídeo;
- como o pareamento wireless funciona;
- onde o Android força `bindSocket` para Wi-Fi;
- se ainda existe fluxo legado enviando touch pelo mesmo socket do vídeo;
- onde o Mac injeta input via `CGEvent`.
- quais tarefas do backlog já foram implementadas.

Objetivo da primeira fase:

- não usar root;
- não reescrever vídeo;
- tratar tela real existente como fonte principal de vídeo;
- manter Virtual Display como modo secundário;
- adaptar conexão para Tailscale/MagicDNS/IP 100.x;
- remover bind forçado em Wi-Fi em modo Tailnet;
- criar canal de input separado;
- capturar teclado/mouse sem root;
- injetar no Mac via CGEvent como fallback inicial;
- manter arquitetura preparada para VirtualHID e root posteriormente.

Restrições:

- não misturar input no socket de vídeo;
- não implementar DriverKit próprio no MVP;
- não implementar root no MVP;
- não tratar `Android KeyEvent` como protocolo final;
- não quebrar USB/LAN existentes;
- preservar licença MIT da base.

Comece propondo um plano de mudanças pequeno para a próxima lacuna real, não para uma tarefa que o código já resolveu. Antes de editar, liste os arquivos que pretende tocar e os riscos de regressão.

---
