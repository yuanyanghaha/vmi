import 'package:flutter/material.dart';

import 'inventory_records_screen.dart';

/// 库存入口：列表主页，新增记录通过右上角按钮弹出表单。
class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const InventoryRecordsScreen();
  }
}
