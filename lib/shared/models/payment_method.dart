/// Mirrors the `payment_method_enum` enum in supabase/migrations/0001_extensions_and_enums.sql.
enum PaymentMethod {
  cash,
  bankTransfer,
  card,
  other;

  static PaymentMethod fromDb(String value) {
    return PaymentMethod.values.firstWhere(
      (m) => m.dbValue == value,
      orElse: () => throw ArgumentError('Unknown payment_method_enum: $value'),
    );
  }

  String get dbValue => switch (this) {
        PaymentMethod.cash => 'CASH',
        PaymentMethod.bankTransfer => 'BANK_TRANSFER',
        PaymentMethod.card => 'CARD',
        PaymentMethod.other => 'OTHER',
      };

  String get label => switch (this) {
        PaymentMethod.cash => 'Cash',
        PaymentMethod.bankTransfer => 'Bank transfer',
        PaymentMethod.card => 'Card',
        PaymentMethod.other => 'Other',
      };
}
