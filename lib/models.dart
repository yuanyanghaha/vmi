import 'dart:convert';

class PickingItem {
  String materialCode;
  String description;
  String lpn;
  String supplier;
  String location;
  int quantity;
  int perBox;
  bool configured;
  String source;
  List<int> mergeParts;
  bool completed;

  PickingItem({
    required this.materialCode,
    required this.description,
    required this.lpn,
    required this.supplier,
    required this.location,
    required this.quantity,
    this.perBox = 0,
    this.configured = false,
    this.source = '',
    List<int>? mergeParts,
    this.completed = false,
  }) : mergeParts = mergeParts ?? <int>[];

  String get codeSuffix =>
      materialCode.length > 4 ? materialCode.substring(materialCode.length - 4) : materialCode;

  PickingItem copyWith({
    String? materialCode,
    String? description,
    String? lpn,
    String? supplier,
    String? location,
    int? quantity,
    int? perBox,
    bool? configured,
    String? source,
    List<int>? mergeParts,
    bool? completed,
  }) {
    return PickingItem(
      materialCode: materialCode ?? this.materialCode,
      description: description ?? this.description,
      lpn: lpn ?? this.lpn,
      supplier: supplier ?? this.supplier,
      location: location ?? this.location,
      quantity: quantity ?? this.quantity,
      perBox: perBox ?? this.perBox,
      configured: configured ?? this.configured,
      source: source ?? this.source,
      mergeParts: mergeParts ?? List<int>.from(this.mergeParts),
      completed: completed ?? this.completed,
    );
  }

  Map<String, dynamic> toJson() => {
        'materialCode': materialCode,
        'description': description,
        'lpn': lpn,
        'supplier': supplier,
        'location': location,
        'quantity': quantity,
        'perBox': perBox,
        'configured': configured,
        'source': source,
        'mergeParts': mergeParts,
        'completed': completed,
      };

  factory PickingItem.fromJson(Map<String, dynamic> json) => PickingItem(
        materialCode: json['materialCode'] as String? ?? '',
        description: json['description'] as String? ?? '',
        lpn: json['lpn'] as String? ?? '',
        supplier: json['supplier'] as String? ?? '',
        location: json['location'] as String? ?? '',
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        perBox: (json['perBox'] as num?)?.toInt() ?? 0,
        configured: json['configured'] as bool? ?? false,
        source: json['source'] as String? ?? '',
        mergeParts: (json['mergeParts'] as List<dynamic>?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            <int>[],
        completed: json['completed'] as bool? ?? false,
      );
}

class MergeGroup {
  final String supplier;
  final String materialCode;
  final String description;
  final String location;
  final String source;
  final List<String> lpns;
  final List<int> quantities;

  MergeGroup(PickingItem item)
      : supplier = item.supplier,
        materialCode = item.materialCode,
        description = item.description,
        location = item.location,
        source = item.source,
        lpns = <String>[item.lpn],
        quantities = <int>[item.quantity];

  int get total => quantities.fold(0, (a, b) => a + b);
  int get count => quantities.length;
}

class HistoryRecord {
  final String id;
  final DateTime createdAt;
  final List<String> imagePaths;
  final List<PickingItem> items;
  final List<PickingItem> mergedItems;

  HistoryRecord({
    required this.id,
    required this.createdAt,
    required this.imagePaths,
    required this.items,
    required this.mergedItems,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'images': imagePaths,
        'items': items.map((e) => e.toJson()).toList(),
        'merged': mergedItems.map((e) => e.toJson()).toList(),
      };

  factory HistoryRecord.fromJson(Map<String, dynamic> json) => HistoryRecord(
        id: json['id'] as String,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        imagePaths: (json['images'] as List<dynamic>? ?? []).cast<String>(),
        items: (json['items'] as List<dynamic>? ?? [])
            .map((e) => PickingItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        mergedItems: (json['merged'] as List<dynamic>? ?? [])
            .map((e) => PickingItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  int get displayTotal {
    final list = mergedItems.isNotEmpty ? mergedItems : items;
    return list.fold(0, (sum, item) => sum + item.quantity);
  }

  int get displayLines => mergedItems.isNotEmpty ? mergedItems.length : items.length;
}

class CatalogItem {
  String materialCode;
  String description;
  String lpn;
  String supplier;
  int perBox;
  List<String> images;

  CatalogItem({
    required this.materialCode,
    required this.description,
    required this.lpn,
    required this.supplier,
    required this.perBox,
    List<String>? images,
  }) : images = images ?? <String>[];

  Map<String, dynamic> toJson() => {
        'materialCode': materialCode,
        'description': description,
        'lpn': lpn,
        'supplier': supplier,
        'perBox': perBox,
        'images': images,
      };

  factory CatalogItem.fromJson(Map<String, dynamic> json) => CatalogItem(
        materialCode: json['materialCode'] as String? ?? '',
        description: json['description'] as String? ?? '',
        lpn: json['lpn'] as String? ?? '',
        supplier: json['supplier'] as String? ?? '',
        perBox: (json['perBox'] as num?)?.toInt() ?? 0,
        images: (json['images'] as List<dynamic>?)?.cast<String>() ?? <String>[],
      );
}

class SupplierInfo {
  String code;
  String name;
  SupplierInfo(this.code, this.name);

  Map<String, dynamic> toJson() => {'code': code, 'name': name};
  factory SupplierInfo.fromJson(Map<String, dynamic> json) =>
      SupplierInfo(json['code'] as String? ?? '', json['name'] as String? ?? '');
}

class GoodsLabelData {
  String materialCode = '';
  String description = '';
  String lpn = '';
  int perBox = 0;
  String supplier = '';
  String manufacturer = '';
  List<String> manufacturerCandidates = <String>[];
}

class InventoryRecord {
  final String id;
  final DateTime createdAt;
  final int systemStock;
  final int actualStock;
  final String materialCode;
  final int perBox;
  final String description;
  final String batch;
  final String manufacturer;
  final String imagePath;

  InventoryRecord({
    required this.id,
    required this.createdAt,
    required this.systemStock,
    required this.actualStock,
    required this.materialCode,
    required this.perBox,
    required this.description,
    required this.batch,
    required this.manufacturer,
    required this.imagePath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'systemStock': systemStock,
        'actualStock': actualStock,
        'materialCode': materialCode,
        'perBox': perBox,
        'description': description,
        'batch': batch,
        'manufacturer': manufacturer,
        'imagePath': imagePath,
      };

  factory InventoryRecord.fromJson(Map<String, dynamic> json) => InventoryRecord(
        id: json['id'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        systemStock: (json['systemStock'] as num?)?.toInt() ?? 0,
        actualStock: (json['actualStock'] as num?)?.toInt() ?? 0,
        materialCode: json['materialCode'] as String? ?? '',
        perBox: (json['perBox'] as num?)?.toInt() ?? 0,
        description: json['description'] as String? ?? '',
        batch: json['batch'] as String? ?? '',
        manufacturer: json['manufacturer'] as String? ?? '',
        imagePath: json['imagePath'] as String? ?? '',
      );
}

String encodeJson(Object value) => jsonEncode(value);
