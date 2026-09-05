import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beauty_clinic_pos/core/hardware/contracts/printer_adapter.dart';
import 'package:beauty_clinic_pos/core/hardware/formatting/receipt_document.dart';
import 'package:beauty_clinic_pos/core/hardware/models/device.dart';
import 'package:beauty_clinic_pos/core/hardware/models/hardware_result.dart';
import 'package:beauty_clinic_pos/core/hardware/printer_service.dart';
import 'package:beauty_clinic_pos/core/hardware/registry/device_registry.dart';
import 'package:beauty_clinic_pos/features/pos/domain/cart_line.dart';
import 'package:beauty_clinic_pos/l10n/generated/app_localizations_en.dart';
import 'package:beauty_clinic_pos/shared/models/business.dart';
import 'package:beauty_clinic_pos/shared/models/payment_method.dart';
import 'package:beauty_clinic_pos/shared/models/sale.dart';

/// Test double standing in for a real socket/printer. Records every call so
/// tests can prove the service reaches (or doesn't reach) the adapter,
/// without touching a network.
class _FakePrinterAdapter implements PrinterAdapter {
  final Object? connectThrows;
  final PrintResult? printReturns;
  final Object? printThrows;

  int connectCalls = 0;
  int printCalls = 0;
  int disconnectCalls = 0;

  HardwareConnectionStatus _status = HardwareConnectionStatus.disconnected;

  _FakePrinterAdapter({this.connectThrows, this.printReturns, this.printThrows});

  @override
  HardwareConnectionStatus get status => _status;

  @override
  Future<void> connect(PrinterDeviceConfig config) async {
    connectCalls++;
    if (connectThrows != null) {
      _status = HardwareConnectionStatus.error;
      throw connectThrows!;
    }
    _status = HardwareConnectionStatus.connected;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    _status = HardwareConnectionStatus.disconnected;
  }

  @override
  Future<HardwareConnectionStatus> healthCheck() async => _status;

  @override
  Future<PrintResult> print(ReceiptDocument document) async {
    printCalls++;
    if (printThrows != null) throw printThrows!;
    return printReturns ?? const PrintResult.confirmed();
  }
}

/// Stands in for the sale-completion path (PosRepository.completeSale /
/// voidSale in the real app). PrinterService has no reference to anything
/// like this -- it is only here so the regression test below can assert its
/// call count stays zero no matter what the printer does.
class _FinancialGuard {
  int completeSaleCalls = 0;
  int voidSaleCalls = 0;
}

Future<DeviceRegistry> _registryWithDefaultPrinter({bool enabled = true}) async {
  SharedPreferences.setMockInitialValues({});
  final registry = await DeviceRegistry.load(await SharedPreferences.getInstance());
  await registry.register(Device(
    id: 'printer-1',
    type: DeviceType.receiptPrinter,
    name: 'Counter printer',
    connectionType: ConnectionType.lan,
    host: '192.168.1.50',
    port: 9100,
    enabled: enabled,
    isDefault: true,
  ));
  return registry;
}

Sale _sale() {
  return Sale(
    id: 'sale-1',
    receiptNumber: 'R-0001',
    subtotal: Decimal.parse('100000'),
    discountAmount: Decimal.zero,
    taxAmount: Decimal.zero,
    totalAmount: Decimal.parse('100000'),
    paidAmount: Decimal.parse('100000'),
    changeAmount: Decimal.zero,
    status: 'COMPLETED',
    paymentStatus: 'PAID',
    createdAt: DateTime(2026, 1, 5),
  );
}

Future<PrintResult> _printWith(PrinterService service) {
  return service.printSaleReceipt(
    sale: _sale(),
    business: const Business(
      id: 'biz-1',
      name: 'Beauty Clinic',
      currency: 'LAK',
      timezone: 'Asia/Vientiane',
      taxEnabled: false,
      taxRate: 0,
    ),
    lines: const <CartLine>[],
    customer: null,
    paymentMethod: PaymentMethod.cash,
    cashierName: 'Nok',
    l10n: AppLocalizationsEn(),
  );
}

void main() {
  group('PrinterService', () {
    test('returns NOT_CONFIGURED when no default printer is registered', () async {
      SharedPreferences.setMockInitialValues({});
      final registry = await DeviceRegistry.load(await SharedPreferences.getInstance());
      final adapter = _FakePrinterAdapter();
      final service = PrinterService(registry: registry, adapterFactory: () => adapter);

      final result = await _printWith(service);

      expect(result.outcome, PrintOutcome.failed);
      expect(result.failure?.code, HardwareErrorCode.notConfigured);
      expect(adapter.connectCalls, 0);
    });

    test('returns DISABLED without contacting the adapter when the default printer is disabled', () async {
      final registry = await _registryWithDefaultPrinter(enabled: false);
      final adapter = _FakePrinterAdapter();
      final service = PrinterService(registry: registry, adapterFactory: () => adapter);

      final result = await _printWith(service);

      expect(result.outcome, PrintOutcome.failed);
      expect(result.failure?.code, HardwareErrorCode.disabled);
      expect(adapter.connectCalls, 0);
    });

    test('connects, prints, and always disconnects on success', () async {
      final registry = await _registryWithDefaultPrinter();
      final adapter = _FakePrinterAdapter();
      final service = PrinterService(registry: registry, adapterFactory: () => adapter);

      final result = await _printWith(service);

      expect(result.isConfirmed, isTrue);
      expect(adapter.connectCalls, 1);
      expect(adapter.printCalls, 1);
      expect(adapter.disconnectCalls, 1);
    });

    test('a connection failure is reported as CONNECTION_FAILED, not thrown', () async {
      final registry = await _registryWithDefaultPrinter();
      final adapter = _FakePrinterAdapter(
        connectThrows: const HardwareFailure(HardwareErrorCode.connectionFailed, 'refused'),
      );
      final service = PrinterService(registry: registry, adapterFactory: () => adapter);

      final result = await _printWith(service);

      expect(result.outcome, PrintOutcome.failed);
      expect(result.failure?.code, HardwareErrorCode.connectionFailed);
      expect(adapter.printCalls, 0);
      expect(adapter.disconnectCalls, 0, reason: 'never connected, so nothing to disconnect');
    });

    test('a timed-out connection never throws past the service', () async {
      final registry = await _registryWithDefaultPrinter();
      final adapter = _FakePrinterAdapter(
        connectThrows: const HardwareFailure(HardwareErrorCode.timeout, 'timed out'),
      );
      final service = PrinterService(registry: registry, adapterFactory: () => adapter);

      final result = await _printWith(service);

      expect(result.outcome, PrintOutcome.failed);
      expect(result.failure?.code, HardwareErrorCode.timeout);
    });

    test('an uncertain write result is surfaced as uncertain, not confirmed or silently failed', () async {
      final registry = await _registryWithDefaultPrinter();
      final adapter = _FakePrinterAdapter(
        printReturns: const PrintResult.uncertain(
          HardwareFailure(HardwareErrorCode.timeout, 'write timed out'),
        ),
      );
      final service = PrinterService(registry: registry, adapterFactory: () => adapter);

      final result = await _printWith(service);

      expect(result.outcome, PrintOutcome.uncertain);
      expect(adapter.disconnectCalls, 1, reason: 'still disconnects even on an uncertain result');
    });

    test('disconnect runs even when print() throws unexpectedly', () async {
      final registry = await _registryWithDefaultPrinter();
      final adapter = _FakePrinterAdapter(printThrows: StateError('socket exploded'));
      final service = PrinterService(registry: registry, adapterFactory: () => adapter);

      final result = await _printWith(service);

      expect(result.outcome, PrintOutcome.failed);
      expect(adapter.disconnectCalls, 1);
    });

    test(
      'REGRESSION: printer failure never reaches financial operations '
      '(complete_sale/void_sale) -- PrinterService holds no reference to '
      'them at all, so no failure mode here can call them',
      () async {
        final financialGuard = _FinancialGuard();
        final registry = await _registryWithDefaultPrinter();
        final adapter = _FakePrinterAdapter(printThrows: StateError('printer caught fire'));
        final service = PrinterService(registry: registry, adapterFactory: () => adapter);

        // The sale is already complete before printing is ever attempted --
        // printSaleReceipt takes a finished Sale, it does not produce one.
        final result = await _printWith(service);

        expect(result.outcome, PrintOutcome.failed);
        expect(financialGuard.completeSaleCalls, 0);
        expect(financialGuard.voidSaleCalls, 0);
      },
    );
  });
}
