import '../../features/pos/domain/cart_line.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/models/business.dart';
import '../../shared/models/customer.dart';
import '../../shared/models/payment_method.dart';
import '../../shared/models/sale.dart';
import 'contracts/printer_adapter.dart';
import 'formatting/receipt_formatter.dart';
import 'models/device.dart';
import 'models/hardware_result.dart';
import 'registry/device_registry.dart';

/// Presentation-facing printer service. This is the only printer API POS
/// UI code should touch -- it never exposes the concrete adapter, a socket,
/// or ESC/POS bytes.
///
/// CRITICAL INVARIANT: this method never calls, and must never be changed
/// to call, anything in PosRepository/SalesRepository (complete_sale,
/// void_sale, record_sale_payment, or any table mutation). Printing is a
/// side effect of an already-completed sale, not a precondition for one --
/// every code path below returns a [PrintResult] and never throws past this
/// method, so a printer failure can never surface as, or be mistaken for, a
/// sale/payment failure.
class PrinterService {
  final DeviceRegistry _registry;
  final PrinterAdapter Function() _adapterFactory;
  final ReceiptFormatter _formatter;

  PrinterService({
    required DeviceRegistry registry,
    required PrinterAdapter Function() adapterFactory,
    ReceiptFormatter formatter = const ReceiptFormatter(),
  })  : _registry = registry,
        _adapterFactory = adapterFactory,
        _formatter = formatter;

  Future<PrintResult> printSaleReceipt({
    required Sale sale,
    required Business business,
    required List<CartLine> lines,
    required Customer? customer,
    required PaymentMethod paymentMethod,
    required String cashierName,
    required AppLocalizations l10n,
  }) async {
    final device = _registry
        .list(type: DeviceType.receiptPrinter)
        .cast<Device?>()
        .firstWhere((d) => d!.isDefault, orElse: () => null);
    if (device == null) {
      return const PrintResult.failed(
        HardwareFailure(HardwareErrorCode.notConfigured, 'No default receipt printer configured'),
      );
    }
    if (!device.enabled) {
      return const PrintResult.failed(
        HardwareFailure(HardwareErrorCode.disabled, 'Configured receipt printer is disabled'),
      );
    }

    final PrinterDeviceConfig config;
    try {
      config = PrinterDeviceConfig.fromDevice(device);
    } catch (_) {
      return const PrintResult.failed(
        HardwareFailure(HardwareErrorCode.notConfigured, 'Receipt printer is misconfigured'),
      );
    }

    final document = _formatter.format(
      sale: sale,
      business: business,
      lines: lines,
      customer: customer,
      paymentMethod: paymentMethod,
      cashierName: cashierName,
      l10n: l10n,
    );

    final adapter = _adapterFactory();
    try {
      await adapter.connect(config);
    } on HardwareFailure catch (failure) {
      return PrintResult.failed(failure);
    } catch (_) {
      return const PrintResult.failed(
        HardwareFailure(HardwareErrorCode.unknown, 'Unexpected error while connecting to the printer'),
      );
    }

    try {
      return await adapter.print(document);
    } catch (_) {
      return const PrintResult.failed(
        HardwareFailure(HardwareErrorCode.unknown, 'Unexpected error while printing'),
      );
    } finally {
      await adapter.disconnect();
    }
  }
}
