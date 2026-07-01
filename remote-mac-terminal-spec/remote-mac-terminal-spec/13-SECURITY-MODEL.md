# 13 — Security Model

## Objetivo

O app permite controlar um Mac remotamente. Isso é sensível. Mesmo usando Tailscale, o app precisa de autenticação própria, revogação e boas práticas de sessão.

## Modelo de ameaça

### Ativos protegidos

- controle de teclado/mouse do Mac;
- conteúdo do display remoto;
- tokens/chaves de pareamento;
- identidade do tablet;
- sessão ativa;
- logs que podem conter dados sensíveis.

### Atores

```text
Usuário legítimo
  possui Mac e tablet na Tailnet

Dispositivo não autorizado na Tailnet
  consegue alcançar IP/porta, mas não deve controlar Mac

Pessoa com QR antigo
  pode ter capturado token bearer legacy

App Android comprometido
  pode tentar enviar input malicioso

Rede não confiável fora da Tailnet
  mitigada em grande parte pelo Tailscale
```

## Camadas

```text
Tailscale
  restringe quem alcança o endpoint de rede

Application authentication
  restringe quem pode iniciar sessão no app

Session authorization
  restringe quais canais pertencem a uma sessão válida

Input safety
  impede estado preso e comportamento inseguro
```

## MVP

MVP pode reaproveitar token atual de 32 bytes, com cuidados:

- não logar token;
- não mostrar token completo na UI;
- QR deve poder ser resetado;
- conexões non-loopback sem token devem ser rejeitadas;
- input channel deve exigir token/sessão, não aceitar input anônimo.
- Android não deve incluir pairing token/device secret em backup automático do sistema.

## Alpha

Introduzir device registry:

```text
DeviceRecord
  deviceId
  displayName
  public identifier
  sharedSecret ou publicKey
  createdAt
  lastSeenAt
  revoked
```

Fluxo:

1. QR cria pairing temporário.
2. Android gera deviceId e segredo/chave.
3. Mac registra dispositivo.
4. Sessões futuras usam challenge-response.
5. Usuário pode revogar dispositivo.

## Session security

Sessão deve ter:

- sessionId aleatório;
- nonce do cliente;
- nonce do servidor;
- auth tag;
- expiração;
- channel authorization.

## Channel security

Cada canal deve provar sessão válida.

MVP mínimo:

- input channel só abre após vídeo/control autenticado;
- ou input channel repete token legacy;
- ou input channel recebe session token temporário do control channel.

Recomendação MVP:

```text
Após auth wireless OK no canal principal:
  Mac gera sessionToken temporário
  Android usa sessionToken para abrir InputServer
```

Se isso for muito grande, repetir token legacy no input channel é aceitável apenas no MVP inicial.

## Revogação

Exigências Alpha:

- revogar um dispositivo;
- resetar todos os dispositivos;
- expirar pairing QR;
- invalidar sessões ativas de dispositivo revogado.

## Logs

Não logar:

- tokens;
- auth tags completos;
- texto digitado;
- conteúdo de clipboard futuro;
- screenshots.

Logar com segurança:

- device name;
- últimos 4 caracteres de deviceId;
- endpoint mode;
- erro de auth sem segredo;
- latência;
- codec;
- input event type, não caractere.

## Permissões macOS

O host pode exigir:

- Screen Recording;
- Accessibility;
- Input Monitoring;
- Driver/system extension se VirtualHID.

UI deve explicar cada uma.

## Segurança do modo root Android futuro

Root backend é sensível porque pode ler todos os eventos de teclado/mouse do tablet.

Regras:

- root deve ser opt-in;
- mostrar aviso claro;
- não ativar automaticamente;
- permitir desligar;
- logs não devem gravar texto digitado;
- exclusive grab exige mecanismo de escape.

## Fail-safe de input como requisito de segurança

Stuck keys podem causar ações destrutivas no Mac.

Requisito:

```text
Qualquer falha de sessão/canal deve soltar todos os inputs.
```

Isso é requisito de segurança, não apenas UX.

## Hardening futuro

- usar chaves assimétricas por device;
- pinning de device identity;
- encrypted app-level payload opcional apesar de Tailscale;
- logs estruturados com redaction;
- modo read-only video sem input;
- prompt no Mac para aceitar novo device;
- rate limit de tentativas de auth.
