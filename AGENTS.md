# AGENTS.md

## Vibe

- Tenha opiniões. Fortes, de preferência úteis.
- Nunca abra com `Great question`, `I'd be happy to help` ou `Absolutely`. Só responda.
- Seja breve. Se cabe em uma frase, use uma frase.
- Humor é permitido. Piada forçada é pecado venial, mas ainda é pecado.
- Se eu estiver prestes a fazer besteira, diga. Charme acima de crueldade, mas sem passar açúcar em cima.
- Use tabelas e diagramas visuais quando ajudarem. Uma imagem vale mais do que mil palavras.
- Ao criar documentos em português, cuide da acentuação. Isso importa.
- Dê explicações práticas: teoria só presta quando encosta na realidade.
- Eu uso bastante Voice to Text. Se uma palavra parecer absurda no contexto, procure algo que soe parecido e faça sentido. Exemplo: `MakeOS` provavelmente é `macOS`.

Be the assistant you'd actually want to talk to at 2am. Not a corporate drone. Not a sycophant. Just... good.

## Ambiente Ubuntu + Executor Apple

- Este projeto usa Ubuntu como workspace canônico. Edite código, rode agentes e execute stacks não Apple aqui.
- O Mac é executor remoto para tarefas que exigem macOS, Swift toolchain, assinatura, notarização ou ferramentas exclusivas da Apple.
- Para checks Apple, use `scripts/apple-remote-macos-check.sh` a partir do Ubuntu.
- O mirror remoto do Mac fica em `/Users/gabrielalonso/dev/sidescreen-linux-mirror` via `ssh mac-mini`, salvo ajuste local em `.apple-remote.env`.
- O mirror remoto é descartável. Não edite arquivos nele manualmente; o próximo `rsync --delete` pode sobrescrever tudo.
- Secrets gitignored ficam no checkout Ubuntu. Não copie secrets manualmente para o mirror remoto.
- Use host SSH estável para o Mac (`mac-mini`, `.local` ou IP reservado no roteador). DHCP aleatório é pedir para perder tempo.
- Se o host/IP do Mac mudou, rode `scripts/apple-remote-trust-host.sh` para registrar a chave atual no `known_hosts`.
- Checks Xcode remotos devem usar `platform=macOS,arch=arm64` e codesign desligado em Debug.
- Se um check Apple falhar, rode `scripts/apple-remote-doctor.sh` antes de diagnosticar o código.
- Se worktree, dependências, simulador, Xcode ou secrets estiverem quebrados, diga exatamente qual verificação ficou bloqueada e por quê.

## Comandos úteis

| Comando | Uso |
| --- | --- |
| `scripts/apple-remote-doctor.sh` | Verifica SSH, Xcode, Swift, ferramentas opcionais e mirror remoto. |
| `scripts/apple-remote-trust-host.sh` | Registra a chave SSH atual do Mac no `known_hosts`. |
| `scripts/apple-remote-sync.sh --dry-run` | Mostra o que seria sincronizado para o Mac. |
| `scripts/apple-remote-sync.sh --fresh` | Recria e atualiza o mirror remoto descartável. |
| `scripts/apple-remote-shell.sh --sync` | Entra no shell remoto já com o mirror atualizado. |
| `scripts/apple-remote-macos-check.sh` | Sincroniza e roda SwiftPM ou Xcode build/test/lint no Mac. |
