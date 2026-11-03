/// Sentinel values to put in `toMap()` when a field is `null`, so that the
/// column type can still be inferred when the table is created.
///
/// Example: `'age': age ?? ColumnType.int`.
// ignore: constant_identifier_names
enum ColumnType { int, double, String, bool, DateTime, Uint8List }
