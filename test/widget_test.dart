import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goods_flutter/calculator.dart';
import 'package:goods_flutter/main.dart';
import 'package:goods_flutter/models.dart';
import 'package:goods_flutter/ocr_service.dart';
import 'package:goods_flutter/screens/inventory_records_screen.dart';
import 'package:goods_flutter/supplier_matcher.dart';
import 'package:goods_flutter/xlsx_export.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('home screen renders', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const GoodsApp());
    await tester.pumpAndSettle();
    expect(find.text('配货清单'), findsOneWidget);
  });

  testWidgets('calculator screen opens and computes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const GoodsApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.calculate_outlined));
    await tester.pumpAndSettle();
    expect(find.text('计算器'), findsWidgets);
    expect(find.text('+ 10'), findsOneWidget);
  });

  testWidgets('catalog screen opens', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const GoodsApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pumpAndSettle();
    expect(find.text('货品配置'), findsOneWidget);
  });

  testWidgets('inventory screen opens', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const GoodsApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.inventory_2_outlined));
    await tester.pumpAndSettle();
    expect(find.text('货品库存统计'), findsOneWidget);
  });

  test('catalog item keeps images through json', () {
    final item = CatalogItem(
      materialCode: '890000001',
      description: '测试物料E',
      lpn: 'XS00000001',
      supplier: '10001',
      perBox: 100,
      images: ['/a.jpg', '/b.jpg'],
    );
    final restored = CatalogItem.fromJson(item.toJson());
    expect(restored.images, ['/a.jpg', '/b.jpg']);
    expect(restored.perBox, 100);
  });

  test('column parser reads all fields from separate boxes', () {
    final lines = <OcrTextLine>[
      OcrTextLine('物料代码', 40, 40, width: 80, height: 20),
      OcrTextLine('物料描述', 180, 40, width: 80, height: 20),
      OcrTextLine('LPN', 400, 40, width: 40, height: 20),
      OcrTextLine('供应商', 500, 40, width: 60, height: 20),
      OcrTextLine('货位', 590, 40, width: 40, height: 20),
      OcrTextLine('预留数量', 660, 40, width: 70, height: 20),
      OcrTextLine('分配数量', 750, 40, width: 70, height: 20),
      OcrTextLine('890000003', 40, 110, width: 100, height: 20),
      OcrTextLine('测试物料A', 180, 110, width: 160, height: 20),
      OcrTextLine('XS00000003', 400, 110, width: 100, height: 20),
      OcrTextLine('10002', 500, 110, width: 50, height: 20),
      OcrTextLine('6T000000A', 590, 110, width: 90, height: 20),
      OcrTextLine('797', 660, 110, width: 30, height: 20),
      OcrTextLine('797', 750, 110, width: 30, height: 20),
    ];
    final items = OcrService.parsePickingBoxes(lines);
    expect(items, hasLength(1));
    expect(items.first.materialCode, '890000003');
    expect(items.first.description, '测试物料A');
    expect(items.first.lpn, 'XS00000003');
    expect(items.first.supplier, '10002');
    expect(items.first.location, '6T000000A');
    expect(items.first.quantity, 797);
  });

  test('picking parser keeps description digits out of quantity', () {
    final items = OcrService.parsePickingTexts([
      '890000004 测试物料C XS00000004 10003 6T000000A 170 170 170 170',
    ]);
    expect(items, hasLength(1));
    expect(items.first.materialCode, '890000004');
    expect(items.first.lpn, 'XS00000004');
    expect(items.first.supplier, '10003');
    expect(items.first.quantity, 170);
  });

  test('picking parser handles two rows with different quantities', () {
    final items = OcrService.parsePickingTexts([
      '890000005 测试物料B XS00000005 10002 6T000000A 2000 2000 2000 2000',
      '890000003 测试物料A XS00000003 10002 6T000000A 797 797 797 797',
    ]);
    expect(items.map((e) => e.quantity).toList(), [2000, 797]);
  });

  test('actual stock expression sums', () {
    final value = ExpressionEvaluator.evaluate('30+20+35');
    expect(value, 85);
  });

  test('inventory record keeps fields through json', () {
    final record = InventoryRecord(
      id: '1',
      createdAt: DateTime(2026, 11, 25, 10, 30),
      systemStock: 100,
      actualStock: 85,
      materialCode: '890000002',
      perBox: 45,
      description: '测试物料F',
      batch: 'XS00000002',
      manufacturer: '示例制造',
      imagePath: '/tmp/a.jpg',
    );
    final restored = InventoryRecord.fromJson(record.toJson());
    expect(restored.actualStock, 85);
    expect(restored.batch, 'XS00000002');
    expect(restored.manufacturer, '示例制造');
  });

  testWidgets('inventory records screen opens', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: InventoryRecordsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('库存记录'), findsOneWidget);
  });

  test('column parser recovers row when header cells are merged', () {
    final lines = <OcrTextLine>[
      OcrTextLine('物料代码 物料描述 LPN 供应商 货位 预留数量 分配数量', 30, 20,
          width: 760, height: 22),
      OcrTextLine('890000007', 30, 110, width: 100, height: 20),
      OcrTextLine('测试物料D', 190, 110, width: 170, height: 20),
      OcrTextLine('XS00000006', 400, 110, width: 100, height: 20),
      OcrTextLine('10001', 520, 110, width: 50, height: 20),
      OcrTextLine('6T000000A', 600, 110, width: 90, height: 20),
      OcrTextLine('210', 700, 110, width: 30, height: 20),
      OcrTextLine('210', 735, 110, width: 30, height: 20),
      OcrTextLine('210', 770, 110, width: 30, height: 20),
    ];
    final items = OcrService.parsePickingBoxes(lines);
    expect(items, hasLength(1));
    expect(items.first.supplier, '10001');
    expect(items.first.lpn, 'XS00000006');
    expect(items.first.location, '6T000000A');
    expect(items.first.quantity, 210);
  });

  test('label parser reads code, description, batch and manufacturer', () {
    final data = OcrService.parseLabelTexts([
      '物料代码 890000006',
      '物料描述 测试物料G',
      '包装数量 377',
      'XS00000002',
      '制造商 示例甲供应商制造有限公司',
    ]);
    expect(data.materialCode, '890000006');
    expect(data.description, '测试物料G');
    expect(data.perBox, 377);
    expect(data.lpn, 'XS00000002');
    expect(data.manufacturer, '示例甲供应商制造有限公司');
  });

  test('label parser handles manufacturer split across lines', () {
    final data = OcrService.parseLabelTexts([
      '物料代码 890000006',
      '制造商',
      '示例甲供应商制造有限公司',
      '甲供应商',
    ]);
    expect(data.manufacturer, '示例甲供应商制造有限公司');
    expect(data.manufacturerCandidates, contains('甲供应商'));
  });

  test('supplier matcher finds short name in manufacturer', () {
    final suppliers = [
      SupplierInfo('10004', '甲供应商'),
      SupplierInfo('10001', '乙供应商'),
    ];
    expect(SupplierMatcher.codeFor('示例甲供应商制造有限公司', suppliers), '10004');
    expect(SupplierMatcher.codeFor('其他制造有限公司', suppliers), '');
    expect(SupplierMatcher.matchAny(['甲供应商', '无匹配'], suppliers)?.code, '10004');
  });

  test('inventory xlsx is a zip package', () {
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
        manufacturer: '甲供应商',
        imagePath: '',
      ),
    ], ['10004']);
    expect(bytes.length, greaterThan(100));
    expect(bytes[0], 0x50);
    expect(bytes[1], 0x4b);
  });

  test('box calculator handles expression and remainder', () {
    final result = BoxCalculator.calculate('100+30', '30');
    expect(result.total, 130);
    expect(result.boxes, 4);
    expect(result.remainder, 10);
  });

  test('box calculator validates per box', () {
    expect(() => BoxCalculator.calculate('100', '0'), throwsA(isA<CalculatorException>()));
  });

  test('material code suffix is last four digits', () {
    final item = PickingItem(
      materialCode: '890000001',
      description: '',
      lpn: '',
      supplier: '10001',
      location: '',
      quantity: 10,
    );
    expect(item.codeSuffix, '0001');
  });
}
