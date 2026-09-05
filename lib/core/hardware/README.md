# Hardware layer

Extension layer for POS peripherals, sitting entirely above the existing
business/security core. Nothing in this directory calls a Supabase table or
RPC directly, and nothing outside this directory should reference an
adapter, a socket, or ESC/POS bytes directly.

```
POS UI (e.g. ReceiptSheet)
      |
      v
HardwareService            <- one facade, injected via hardwareServiceProvider
      |
      v
PrinterService              <- returns PrintResult, never throws, never
      |                         touches sales/payments/inventory
      v
PrinterAdapter (contract)   <- connect / disconnect / status / healthCheck / print
      |
      v
EscPosLanPrinterAdapter     <- protocol-based: ESC/POS over TCP (port 9100
      |                         convention), no manufacturer-specific code
      v
PrinterSocketTransport      <- dart:io Socket on Windows/Android;
                                throws UnsupportedError on Web (conditional
                                import keeps dart:io out of the Web build)
```

## Boundary this layer must never cross

Hardware code must never call `complete_sale`, `void_sale`,
`record_sale_payment`, or write to `sales`/`sale_items`/`payments`/
`inventory_movements`/`commissions` directly. A print failure is reported as
a `PrintResult` (confirmed / failed / uncertain) and must never roll back or
retry a sale.

## Printer configuration

A `Device` (`models/device.dart`) is local-only configuration: host, port,
connect timeout, enabled, is-default. It is persisted via
`shared_preferences` by `DeviceRegistry` (`registry/device_registry.dart`)
and is never synced to Supabase in this slice. There is no UI to add a
device yet -- registering one today means calling
`DeviceRegistry.register(...)` (e.g. from a debug/settings entry point added
later).

## Known platform limitations

- **Web**: cannot open a raw TCP socket to a LAN printer. `PrinterService`
  reports `HardwareErrorCode.unsupportedOperation` rather than attempting a
  browser workaround. Web printing needs a future Local Hardware Bridge.
- **Non-Latin text**: the ESC/POS encoder sends UTF-8 bytes; standard
  ESC/POS printers use a single-byte code page and will not render Lao
  correctly without vendor-specific code-page selection (not implemented).
- **Cut/drawer-kick commands**: sent optimistically; a printer without a
  cutter ignores the bytes rather than erroring, but this has not been
  confirmed against a real printer (see acceptance criteria in the
  implementation report).

## Adding the next adapter

1. Add a contract under `contracts/` only for the module you're building
   (mirror `printer_adapter.dart`) -- do not add empty contracts for modules
   with no adapter yet.
2. Add the adapter under `adapters/`, named by protocol
   (`UsbHidScannerAdapter`, not a manufacturer name).
3. Add a `<Module>Service` next to `printer_service.dart` and a field on
   `HardwareService`.
4. Keep the POS-facing API returning typed results, never throwing past the
   service boundary.
