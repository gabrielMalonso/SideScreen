# 01 — Project Brief

## Contexto

A base analisada é o SideScreen, um projeto macOS + Android que transforma um tablet Android em segundo display para macOS via USB-C ou Wi-Fi/LAN.

O projeto atual já resolve muito bem a parte de vídeo:

- criação de display virtual real no macOS;
- captura via ScreenCaptureKit;
- codificação via VideoToolbox;
- HEVC/H.265 com fallback H.264;
- decodificação Android via MediaCodec;
- streaming de baixa latência;
- suporte a HiDPI;
- touch básico.

O novo objetivo é mais ambicioso: não criar apenas um segundo monitor, mas um Remote Desktop minimalista para Mac.

O usuário quer substituir, no uso pessoal, Google Remote Desktop/Chrome Remote Desktop ou AnyDesk por uma ferramenta menor e menos intrusiva. Isso significa ver e controlar as telas reais que já existem no Mac, não apenas criar um monitor extra.

O modo de segundo monitor/Virtual Display deve continuar como capacidade secundária herdada do SideScreen. Ele não deve ditar o produto principal.

## Produto-alvo

O produto-alvo deve permitir:

```text
Mac mini em casa
  → app host rodando localmente
  → conectado à Tailnet

Tablet Android fora de casa
  → app client em fullscreen
  → Tailscale ativo
  → teclado Bluetooth
  → mouse Bluetooth
```

O usuário deve conseguir abrir o tablet, conectar ao Mac mini e trabalhar como se estivesse usando um MacBook remoto.

O primeiro fluxo de produto deve ser:

```text
Escolher Mac
  → escolher tela real do Mac
  → conectar
  → ver/controlar essa tela em fullscreen
  → desconectar ou revogar
```

## Não-objetivos iniciais

A primeira fase não deve tentar resolver tudo.

Não são objetivos do MVP:

- capturar todas as teclas de sistema do Android;
- usar root;
- usar DriverKit próprio;
- substituir Tailscale por NAT traversal próprio;
- criar clone completo de AnyDesk/Parsec/RustDesk com chat, transferência de arquivos, áudio, clipboard avançado e gestão de times;
- implementar clipboard, áudio, multi-monitor e file transfer imediatamente;
- suportar múltiplos clientes simultâneos.

## Princípio de produto

A percepção de qualidade será dominada por input e latência, não apenas por qualidade de imagem.

Uma imagem perfeita com input ruim parece ruim. Uma imagem ligeiramente comprimida com input excelente parece utilizável.

Logo, o projeto deve priorizar:

1. latência de input;
2. estabilidade de sessão;
3. mouse relativo correto;
4. teclado com mapeamento Mac previsível;
5. vídeo sem backlog;
6. recuperação rápida de rede.

## Critérios de sucesso do MVP

O MVP é bem-sucedido se:

- o Android conecta ao Mac via MagicDNS ou IP 100.x do Tailscale;
- vídeo da tela real selecionada do Mac aparece no tablet fora da LAN;
- Virtual Display continua disponível como modo secundário quando o usuário quiser segundo monitor;
- o app não força socket para Wi-Fi em modo Tailnet;
- mouse Bluetooth move o cursor do Mac com baixa latência;
- clique esquerdo, clique direito, drag e scroll funcionam;
- teclado Bluetooth envia letras, números, Enter, Escape, Tab e modificadores comuns;
- Command/Option/Control funcionam quando o Android entrega os eventos;
- desconectar não deixa teclas presas no Mac;
- quedas de rede não exigem reiniciar o Mac host;
- o usuário consegue usar Terminal, Finder, navegador e editor de texto com conforto básico.

## Critérios de sucesso da Alpha

A Alpha é bem-sucedida se:

- o input usa protocolo HID-like;
- vídeo e input estão em canais separados;
- o Mac tem backend Virtual HID ou integração Karabiner VirtualHID funcional;
- CGEvent continua disponível como fallback;
- mouse relativo usa pointer capture no Android;
- existe telemetria de RTT, frame age e input latency;
- existe configuração clara para layout de teclado;
- existe reconexão sem deixar estado preso.

## Critérios de sucesso da versão final

A versão final é bem-sucedida se:

- a experiência sem root é boa para uso diário;
- o modo root opcional melhora fidelidade de input sem afetar usuários normais;
- o host Mac tem instalação e permissões compreensíveis;
- o usuário conecta por nome, não por IP;
- o app identifica problemas de Tailnet, relay/DERP e split tunneling;
- o canal de input permanece responsivo mesmo com vídeo pesado;
- logs e diagnóstico permitem depurar problemas de rede e input.

## Modos de produto

```text
Remote Desktop Mode
  captura uma tela real existente do Mac
  envia essa tela ao Android
  injeta teclado/mouse no Mac
  é o modo principal

Extended Display Mode
  cria um Virtual Display no macOS
  envia esse display ao Android
  permite usar o tablet como segundo monitor
  é modo secundário/herdado
```

## Direção estratégica

Criar um projeto novo ou um fork fortemente refatorado. A base do SideScreen deve ser aproveitada como motor de vídeo, mas o produto final deve ter arquitetura de Remote Desktop minimalista.

Recomendação:

```text
Novo projeto/fork estruturado
  ├─ video engine reaproveitado do SideScreen
  ├─ display source layer novo
  ├─ session layer novo
  ├─ transport layer novo
  ├─ input layer novo
  └─ UI/configuração ajustada ao produto remoto
```

## Licença da base

O snapshot analisado contém `LICENSE` MIT. Ao reaproveitar código, preservar o copyright e a licença em cópias substanciais do código.
