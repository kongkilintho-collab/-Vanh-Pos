/// Mirrors the `sale_item_kind` enum in supabase/migrations/0001_extensions_and_enums.sql.
enum SaleItemKind {
  service,
  product;

  String get dbValue => switch (this) {
        SaleItemKind.service => 'SERVICE',
        SaleItemKind.product => 'PRODUCT',
      };
}
