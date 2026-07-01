# ADR-0006 — CGEvent primeiro, Virtual HID depois

## Status

Aceita.

## Contexto

Virtual HID é tecnicamente superior para experiência de Mac nativo, mas exige driver/system extension e mais atrito. CGEvent já é usado no SideScreen para mouse/touch e permite validar a arquitetura de input rapidamente.

## Decisão

Usar CGEvent como backend inicial/MVP. Integrar Karabiner VirtualHID na Alpha. Considerar DriverKit próprio apenas no futuro.

## Consequências

### Positivas

- MVP mais rápido.
- Menos dependências no início.
- Valida protocolo e canal antes do driver.

### Negativas

- CGEvent não é input físico real.
- Alguns apps/contextos podem se comportar diferente.
- Permissões ainda são necessárias.

## Implicação arquitetural

Criar abstração:

```text
InputBackend
  CGEventBackend
  KarabinerVirtualHIDBackend
  DriverKitOwnBackend futuro
```

