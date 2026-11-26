import 'dart:io';

import 'package:goods_flutter/models.dart';
import 'package:goods_flutter/xlsx_export.dart';

void main() {
  final bytes = InventoryXlsx.build([
    InventoryRecord(
      id: '1',
      createdAt: DateTime(2026, 11, 25, 10, 30),
      systemStock: 100,
      actualStock: 85,
      materialCode: '890000002',
      perBox: 45,
      description: '测试物料F',
      batch: 'XS00000002',
      manufacturer: '示例制造',
      imagePath: '',
    ),
  ]);
  File('build/inventory_check.xlsx').writeAsBytesSync(bytes);
}
