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

O novo objetivo é mais ambicioso: não criar apenas um segundo monitor, mas um terminal remoto para Mac.

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

## Não-objetivos iniciais

A primeira fase não deve tentar resolver tudo.

Não são objetivos do MVP:

- capturar todas as teclas de sistema do Android;
- usar root;
- usar DriverKit próprio;
- substituir Tailscale por NAT traversal próprio;
- criar concorrente completo de AnyDesk/Parsec/RustDesk;
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
- vídeo do Virtual Display aparece no tablet fora da LAN;
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

## Direção estratégica

Criar um projeto novo ou um fork fortemente refatorado. A base do SideScreen deve ser aproveitada como motor de vídeo, mas o produto final deve ter arquitetura de terminal remoto.

Recomendação:

```text
Novo projeto/fork estruturado
  ├─ video engine reaproveitado do SideScreen
  ├─ session layer novo
  ├─ transport layer novo
  ├─ input layer novo
  └─ UI/configuração ajustada ao produto remoto
```

## Licença da base

O snapshot analisado contém `LICENSE` MIT. Ao reaproveitar código, preservar o copyright e a licença em cópias substanciais do código.

