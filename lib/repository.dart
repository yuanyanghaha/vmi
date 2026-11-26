import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class AppRepository {
  static const _catalogKey = 'catalog_items_v1';
  static const _supplierKey = 'supplier_items_v1';
  static const _historyKey = 'picking_history_v1';
  static const _inventoryKey = 'inventory_records_v1';
  static const _serverKey = 'ocr_server_url';
  static const defaultServerUrl = 'https://your-ocr-server.example.com/ocr';

  static Future<List<CatalogItem>> loadCatalog() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_catalogKey);
    if (raw != null && raw.isNotEmpty) {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => CatalogItem.fromJson(e as Map<String, dynamic>)).toList();
    }
    try {
      final text = await rootBundle.loadString('assets/goods_catalog.json');
      final data = jsonDecode(text) as Map<String, dynamic>;
      final items = (data['items'] as List<dynamic>)
          .map((e) => CatalogItem.fromJson(e as Map<String, dynamic>))
          .toList();
      await saveCatalog(items);
      return items;
    } catch (_) {
      return <CatalogItem>[];
    }
  }

  static Future<void> saveCatalog(List<CatalogItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_catalogKey, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  static Future<List<SupplierInfo>> loadSuppliers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_supplierKey);
    if (raw == null || raw.isEmpty) return <SupplierInfo>[];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => SupplierInfo.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> saveSuppliers(List<SupplierInfo> suppliers) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_supplierKey, jsonEncode(suppliers.map((e) => e.toJson()).toList()));
  }

  static Future<String> loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_serverKey);
    if (saved == null || saved.isEmpty) return defaultServerUrl;
    // 兼容旧版本遗留在手机上的 localhost 默认值；Android 上它不可用。
    if (saved == 'http://127.0.0.1:8000/ocr' ||
        saved == 'http://localhost:8000/ocr') {
      await prefs.setString(_serverKey, defaultServerUrl);
      return defaultServerUrl;
    }
    return saved;
  }

  static Future<void> saveServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverKey, normalizeServerUrl(url));
  }

  static String normalizeServerUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return defaultServerUrl;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    if (!url.endsWith('/ocr')) url = '$url/ocr';
    return url;
  }

  static Future<List<HistoryRecord>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    final records = <HistoryRecord>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        records.addAll(list.map((e) => HistoryRecord.fromJson(e as Map<String, dynamic>)));
      } catch (_) {
        // ignore corrupt history
      }
    }
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final valid = records.where((r) => r.createdAt.isAfter(cutoff)).toList();
    if (valid.length != records.length) {
      await saveHistory(valid);
      for (final r in records.where((r) => !valid.contains(r))) {
        await _deleteHistoryImages(r);
      }
    }
    return valid;
  }

  static Future<void> saveHistory(List<HistoryRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_historyKey, jsonEncode(records.map((e) => e.toJson()).toList()));
  }

  static Future<List<InventoryRecord>> loadInventory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_inventoryKey);
    if (raw == null || raw.isEmpty) return <InventoryRecord>[];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => InventoryRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return <InventoryRecord>[];
    }
  }

  static Future<void> saveInventory(List<InventoryRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _inventoryKey, jsonEncode(records.map((e) => e.toJson()).toList()));
  }

  static Future<HistoryRecord> createHistory({
    required List<String> sourceImages,
    required List<PickingItem> items,
    List<PickingItem> mergedItems = const <PickingItem>[],
  }) async {
    final now = DateTime.now();
    final id = '${now.millisecondsSinceEpoch}';
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(dir.path, 'picking_history'));
    await folder.create(recursive: true);
    final savedPaths = <String>[];
    for (var i = 0; i < sourceImages.length; i++) {
      final source = File(sourceImages[i]);
      if (!await source.exists()) continue;
      final ext = p.extension(sourceImages[i]).isEmpty ? '.jpg' : p.extension(sourceImages[i]);
      final target = File(p.join(folder.path, '${id}_$i$ext'));
      try {
        await source.copy(target.path);
        savedPaths.add(target.path);
      } catch (_) {
        savedPaths.add(sourceImages[i]);
      }
    }
    return HistoryRecord(
      id: id,
      createdAt: now,
      imagePaths: savedPaths,
      items: items,
      mergedItems: mergedItems,
    );
  }

  static Future<void> _deleteHistoryImages(HistoryRecord record) async {
    for (final path in record.imagePaths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  static Future<void> deleteHistory(List<HistoryRecord> records, HistoryRecord record) async {
    await _deleteHistoryImages(record);
    records.removeWhere((e) => e.id == record.id);
    await saveHistory(records);
  }

  static Future<void> clearHistory(List<HistoryRecord> records) async {
    for (final record in records) {
      await _deleteHistoryImages(record);
    }
    records.clear();
    await saveHistory(records);
  }
}
