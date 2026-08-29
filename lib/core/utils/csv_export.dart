/// Minimal CSV serialization -- no external package, since a full CSV
/// library is unnecessary for the small, flat tables this app exports.
/// Fields are quoted only when they contain a comma, quote, or newline,
/// with embedded quotes doubled per RFC 4180.
String toCsv(List<List<String>> rows) {
  return rows.map((row) => row.map(_csvField).join(',')).join('\r\n');
}

String _csvField(String value) {
  final needsQuoting = value.contains(',') || value.contains('"') || value.contains('\n');
  if (!needsQuoting) return value;
  return '"${value.replaceAll('"', '""')}"';
}
