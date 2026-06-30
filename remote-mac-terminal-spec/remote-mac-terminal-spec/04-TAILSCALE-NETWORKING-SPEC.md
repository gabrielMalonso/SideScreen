# 04 — Tailscale Networking Spec

## Objetivo

Adaptar o projeto para funcionar pela internet usando Tailscale, mantendo a simplicidade do QR/pairing e evitando dependência de LAN.

## Premissas

- Mac mini e tablet Android estão na mesma Tailnet.
- Tailscale está instalado e conectado em ambos.
- O app não precisa implementar NAT traversal próprio.
- O app não deve usar APIs internas do Tailscale como requisito do MVP.
- O usuário pode usar MagicDNS ou IP 100.x manualmente.

## Conceito de endpoint

O projeto atual assume LAN. O novo projeto deve distinguir endpoint de rede.

```text
EndpointMode
  USB
  LAN
  TAILNET_MAGIC_DNS
  TAILNET_IP
  MANUAL
```

### USB

Usa ADB reverse, como SideScreen atual.

```text
Android conecta em 127.0.0.1:porta
Mac configura adb reverse
```

### LAN

Usa IP local.

```text
192.168.x.y
10.x.y.z
172.16-31.x.y
```

Pode continuar usando `LANAddressResolver`, mas somente para modo LAN.

### Tailnet MagicDNS

Preferido para uso real:

```text
mac-mini.<tailnet>.ts.net:porta
```

Também aceitar short name se o Android resolver corretamente, mas o QR deve preferir FQDN para reduzir ambiguidade.

### Tailnet IP

Fallback confiável:

```text
100.x.y.z:porta
```

IP 100.x é bom para diagnóstico e quando MagicDNS falha.

## QR de pareamento

Formato atual:

```text
sidescreen://host:port?t=TOKEN&name=Mac
```

Formato proposto para MVP:

```text
sidescreen://host:port?t=TOKEN&name=MacMini&mode=tailnet
```

Exemplos:

```text
sidescreen://mac-mini.tailnet-name.ts.net:54321?t=...&name=MacMini&mode=tailnet
sidescreen://100.101.102.103:54321?t=...&name=MacMini&mode=tailnet
sidescreen://192.168.1.50:54321?t=...&name=MacMini&mode=lan
```

O parser Android deve aceitar ausência de `mode` para compatibilidade com QR antigo. Se `mode` estiver ausente, tratar como `lan`/legacy.

## Mac: substituir LANAddressResolver como fonte única

Hoje a UI usa `LANAddressResolver.primaryIPv4()` para exibir listening address e gerar QR.

Novo modelo:

```text
EndpointAdvertiser
  currentMode
  configuredTailnetHost
  configuredTailnetIp
  lanAddressResolver
  buildPairingUrl()
```

### MVP simplificado

No MVP, não tentar descobrir MagicDNS automaticamente. Permitir o usuário informar:

- Tailnet hostname;
- ou IP 100.x do Mac;
- ou usar LAN automático.

Isso evita depender de CLI Tailscale e permissões adicionais.

### Pós-MVP

Opcionalmente, no Mac:

- detectar se `tailscale` CLI existe;
- usar `tailscale ip -4` para sugerir IP;
- permitir copiar hostname configurado;
- nunca tornar isso requisito.

## Android: remover bind Wi-Fi em modo Tailnet

Problema atual:

```text
StreamClient.connectWireless(...)
  procura Network com TRANSPORT_WIFI
  chama wifiNetwork.bindSocket(sock)
```

Esse comportamento deve ser preservado apenas como workaround de LAN, não em Tailnet.

Regra:

```text
if endpointMode == TAILNET_MAGIC_DNS or TAILNET_IP:
  não chamar bindSocket
  usar roteamento padrão do Android
else if endpointMode == LAN and workaroundEnabled:
  pode bindar Wi-Fi opcionalmente
```

## Split tunneling no Android

Tailscale Android suporta split tunneling por app. Se o usuário excluir o app cliente da Tailnet, MagicDNS/IP 100.x podem falhar.

A UI deve orientar:

```text
Se conexão Tailnet falhar:
  1. verificar se Tailscale está conectado
  2. verificar se este app não está excluído no split tunneling
  3. testar IP 100.x em vez de MagicDNS
  4. testar MagicDNS em vez de IP
```

## Direct vs relay

Tailscale pode usar conexão direta, peer relay ou DERP. Isso afeta latência e throughput.

O app não precisa controlar isso no MVP, mas deve medir:

- RTT;
- jitter aparente;
- bitrate sustentado;
- frame age;
- input latency.

Se a conexão cair em DERP, o app deve continuar funcionando, mas pode precisar reduzir bitrate/resolução/FPS.

## Porta e firewall

MVP:

- manter porta principal configurável do SideScreen;
- input channel pode usar `port + 1` inicialmente;
- documentar que ambos precisam estar acessíveis na Tailnet.

Alpha:

- migrar para single-port multi-channel se necessário.

Final:

- idealmente uma porta única;
- canais multiplexados por sessão;
- controle claro de permissões no firewall do macOS.

## Segurança

Tailscale reduz superfície de exposição, mas o app Mac ainda aceita controle remoto.

Exigências:

- não aceitar conexões sem auth fora de loopback;
- manter allowlist de dispositivos pareados;
- permitir revogar todos os dispositivos;
- permitir revogar um dispositivo;
- não logar tokens em texto claro;
- não exibir token inteiro na UI/log;
- usar token temporário de QR no futuro.

## Fluxo de conexão MVP via Tailnet

```text
MacHost:
  usuário seleciona modo Tailnet
  usuário informa host MagicDNS ou IP 100.x
  Mac gera QR com mode=tailnet
  Mac inicia listener

Android:
  usuário escaneia QR
  parser lê host/port/token/mode
  StreamClient cria Socket normal
  não faz bind Wi-Fi
  conecta host:port
  envia handshake atual
  recebe OK
  inicia vídeo
  inicia input channel separado
```

## Mensagens de erro sugeridas

| Situação | Mensagem |
|---|---|
| DNS `.ts.net` falhou | "Não consegui resolver o nome Tailnet. Teste usando o IP 100.x do Mac." |
| Timeout em IP 100.x | "Mac inacessível pela Tailnet. Verifique se Tailscale está ativo nos dois dispositivos." |
| Token rejeitado | "Pareamento rejeitado. Escaneie novamente o QR no Mac." |
| App excluído no split tunneling | "Verifique no Tailscale Android se este app não está excluído da Tailnet." |
| RTT alto | "Conexão Tailnet com alta latência. Reduza resolução/FPS ou verifique se está usando relay." |

## Critérios de aceite

- QR com `mode=tailnet` é aceito pelo Android.
- Host `.ts.net` é aceito e persistido.
- IP 100.x é aceito e persistido.
- Em Tailnet, `bindSocket` não é chamado.
- LAN antiga continua funcionando.
- USB antigo continua funcionando.
- Falhas de Tailnet têm mensagens específicas, não genéricas.

