# Appendix B — External References

Referências úteis para continuar o projeto. Todas foram consultadas/revisadas em 2026-06-30.

## Tailscale

### MagicDNS

URL: https://tailscale.com/docs/features/magicdns

Relevância:

- MagicDNS registra nomes DNS para dispositivos na Tailnet;
- deve ser a forma preferida de UX para conectar ao Mac mini.

### DNS in Tailscale

URL: https://tailscale.com/docs/reference/dns-in-tailscale

Relevância:

- explica como MagicDNS atribui nomes a dispositivos;
- confirma que MagicDNS é opcional, mas útil.

### Tailscale IP addresses

URL: https://tailscale.com/docs/concepts/tailscale-ip-addresses

Relevância:

- dispositivos recebem IPs 100.x.y.z;
- IP 100.x é bom como fallback/manual.

### IP and DNS addresses

URL: https://tailscale.com/docs/concepts/ip-and-dns-addresses

Relevância:

- descreve atribuição de IPs 100.x;
- útil para documentação de setup.

### Connect to devices

URL: https://tailscale.com/docs/how-to/connect-to-devices

Relevância:

- recomenda conectar por nome/MagicDNS ou IP Tailscale + porta.

### Connection types / DERP

URL: https://tailscale.com/docs/reference/connection-types

Relevância:

- Tailscale pode usar conexão direta ou relayed;
- direct connection não é garantida;
- relay pode afetar latência.

### DERP servers

URL: https://tailscale.com/docs/reference/derp-servers

Relevância:

- DERP ajuda NAT traversal e funciona como fallback;
- importante para diagnóstico de latência.

### Android app split tunneling

URL: https://tailscale.com/docs/features/client/android-app-split-tunneling

Relevância:

- no Android, app pode ser incluído/excluído da Tailnet;
- se o cliente for excluído, MagicDNS/IP 100.x podem falhar.

### Tailscale CLI

URL: https://tailscale.com/docs/reference/tailscale-cli

Relevância:

- no Mac pode ajudar a descobrir IP 100.x;
- não deve ser requisito do MVP.

## Android input

### Pointer capture / movement

URL: https://developer.android.com/develop/ui/views/touch-and-input/gestures/movement

Relevância:

- documenta `requestPointerCapture` e `onCapturedPointerEvent`;
- base para mouse relativo no tablet.

### View API — onCapturedPointerEvent

URL: https://developer.android.com/reference/android/view/View

Relevância:

- referência de API para eventos capturados.

### AccessibilityServiceInfo

URL: https://developer.android.com/reference/android/accessibilityservice/AccessibilityServiceInfo

Relevância:

- base para avaliar `FLAG_REQUEST_FILTER_KEY_EVENTS`;
- Accessibility pode ajudar, mas não deve ser backend principal.

### Android KeyEvent

URL: https://developer.android.com/reference/android/view/KeyEvent

Relevância:

- explica action down/up/repeat/metaState;
- usar como input source sem root, mas não como protocolo final.

### AOSP input overview

URL: https://source.android.com/docs/core/interaction/input

Relevância:

- descreve pipeline input driver/evdev/EventHub/InputReader/InputDispatcher;
- justifica por que `KeyEvent` é pós-framework.

### AOSP getevent

URL: https://source.android.com/docs/core/interaction/input/getevent

Relevância:

- útil para root backend futuro;
- mostra eventos crus do kernel.

### Android KeyEvent source

URL: https://android.googlesource.com/platform/frameworks/base/+/master/core/java/android/view/KeyEvent.java

Relevância:

- útil para entender teclas de sistema e comportamento de códigos.

## macOS input

### CGEvent

URL: https://developer.apple.com/documentation/coregraphics/cgevent

Relevância:

- base para fallback de injeção sintética.

### CGEvent.post(tap:)

URL: https://developer.apple.com/documentation/coregraphics/cgevent/post%28tap%3A%29

Relevância:

- usado pelo SideScreen para postar eventos em `.cghidEventTap`.

### AXIsProcessTrustedWithOptions

URL: https://developer.apple.com/documentation/applicationservices/1460720-axisprocesstrustedwithoptions

Relevância:

- permissões de Accessibility necessárias para automação/input sintético.

### HIDDriverKit

URL: https://developer.apple.com/documentation/hiddriverkit

Relevância:

- framework oficial para drivers HID via DriverKit;
- opção final, não MVP.

### Creating virtual devices / CoreHID

URL: https://developer.apple.com/documentation/corehid/creatingvirtualdevices

Relevância:

- Apple documenta conceito de dispositivo HID virtual;
- investigar compatibilidade e entitlements antes de escolher.

### HIDVirtualDevice

URL: https://developer.apple.com/documentation/corehid/hidvirtualdevice

Relevância:

- possível alternativa moderna para virtual HID;
- precisa investigação prática.

### DriverKit virtual HID entitlement

URL: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.hid.virtual.device

Relevância:

- virtual HID exige entitlement; impacta distribuição.

## Karabiner VirtualHID

### Karabiner-DriverKit-VirtualHIDDevice

URL: https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice

Relevância:

- implementa teclado e mouse virtuais usando DriverKit;
- reconhecido pelo macOS como hardware físico;
- melhor backend prático para Alpha.

### Releases

URL: https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases

Relevância:

- acompanhar versões e mudanças de compatibilidade.

