import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';

/// Formats amounts for display. LAK has no minor unit in everyday use, so
/// this shows whole numbers by default; other currencies (future
/// multi-currency support) keep two decimal places.
String formatMoney(Decimal amount, {String currency = 'LAK'}) {
  final pattern = currency == 'LAK' ? '#,##0' : '#,##0.00';
  final formatter = NumberFormat(pattern, 'en_US');
  return '${formatter.format(amount.toDouble())} $currency';
}
