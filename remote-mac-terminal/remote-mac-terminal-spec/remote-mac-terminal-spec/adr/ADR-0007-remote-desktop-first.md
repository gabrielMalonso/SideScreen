# ADR-0007 — Remote Desktop primeiro

## Status

Aceita.

## Contexto

A base SideScreen nasceu como segundo monitor para Android. Isso é útil, mas não descreve o produto desejado.

O objetivo do usuário é substituir, no uso pessoal, Google Remote Desktop/Chrome Remote Desktop ou AnyDesk por uma ferramenta minimalista para acessar o próprio Mac. Esse objetivo exige ver e controlar as telas reais que já existem no Mac, não apenas criar um display virtual.

## Decisão

O modo principal do produto será Remote Desktop Mode.

Remote Desktop Mode captura uma tela real existente do Mac, transmite essa tela ao Android e injeta input remoto no Mac.

Extended Display Mode, baseado em Virtual Display, continua suportado como modo secundário/herdado.

## Consequências

### Positivas

- O produto fica alinhado ao uso real: acessar o Mac, não ganhar mais uma tela.
- A UI pode ser menor: escolher tela, conectar, desconectar e revogar.
- A validação de uso diário fica honesta: controlar a tela real do Mac vira gate.
- O motor de vídeo do SideScreen continua valioso.

### Negativas

- A arquitetura precisa separar fonte de vídeo de criação de display virtual.
- QA precisa cobrir tela principal, monitor externo e troca de tela.
- Permissões de Screen Recording ficam ainda mais centrais.

## Implicação arquitetural

Criar a abstração:

```text
DisplaySource
  ExistingDisplaySource
    main display
    external display by CGDirectDisplayID

  VirtualDisplaySource
    CGVirtualDisplay
    extended display mode
```

Critério de aprovação: uma rodada de uso diário só conta como aprovação do produto principal quando o usuário consegue ver e controlar uma tela real existente do Mac.
