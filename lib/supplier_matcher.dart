import 'models.dart';

class SupplierMatcher {
  static SupplierInfo? match(String manufacturer, List<SupplierInfo> suppliers) {
    final text = manufacturer.replaceAll(RegExp(r'\s+'), '');
    if (text.isEmpty) return null;
    SupplierInfo? best;
    var bestLength = 0;
    for (final supplier in suppliers) {
      final name = supplier.name.replaceAll(RegExp(r'\s+'), '');
      if (name.isEmpty) continue;
      if (text.contains(name) && name.length > bestLength) {
        best = supplier;
        bestLength = name.length;
      }
    }
    return best;
  }

  /// 标签里可能有多行公司名，逐行尝试，取第一个能匹配的供应商。
  static SupplierInfo? matchAny(
      Iterable<String> manufacturers, List<SupplierInfo> suppliers) {
    SupplierInfo? best;
    var bestLength = 0;
    for (final manufacturer in manufacturers) {
      final found = match(manufacturer, suppliers);
      if (found == null) continue;
      final nameLength = found.name.length;
      if (nameLength > bestLength) {
        best = found;
        bestLength = nameLength;
      }
    }
    return best;
  }

  static String codeFor(String manufacturer, List<SupplierInfo> suppliers) {
    return match(manufacturer, suppliers)?.code ?? '';
  }
}
