import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

class OcrException implements Exception {
  final String message;
  OcrException(this.message);
  @override
  String toString() => message;
}

class OcrTextLine {
  final String text;
  final double x;
  final double y;
  final double width;
  final double height;
  OcrTextLine(this.text, this.x, this.y, {this.width = 0, this.height = 0});
  double get cx => x + width / 2;
  double get cy => y + height / 2;
  String get compact => text.replaceAll(RegExp(r'\s+'), '').toUpperCase();
}

class OcrService {
  static int lastServerFailures = 0;
  static int lastLocalFailures = 0;
  static const _codePattern = r'\b(890\d{6})\b';
  static const _lpnPattern = r'[A-Za-z]{2}\d{6,}';
  static const _xsBatchPattern = r'XS\d{6,}';
  static const _supplierPattern = r'\b(\d{5})\b';
  static const _locationPattern = r'\b(6T\d{6}[A-Z]?|[0-9]{6,}[A-Z][A-Z0-9]*)\b';

  static Future<List<PickingItem>> recognizeLocalPicking(List<String> paths) async {
    if (kIsWeb) throw OcrException('当前平台不支持本地 OCR');
    final items = <PickingItem>[];
    String? lastError;
    lastLocalFailures = 0;
    for (var i = 0; i < paths.length; i++) {
      try {
        final prepared = await compressImage(paths[i], maxSide: 2400);
        final lines = await _recognizeLines(prepared);
        final parsed = _parsePickingLines(lines);
        for (final item in parsed) {
          items.add(item.copyWith(source: '本地'));
        }
      } catch (error) {
        lastError = '第 ${i + 1} 张：$error';
        lastLocalFailures++;
      }
    }
    if (items.isEmpty && lastError != null) throw OcrException(lastError);
    return items;
  }

  static Future<List<PickingItem>> recognizeServerPicking(
      List<String> paths, String serverUrl) async {
    final items = <PickingItem>[];
    String? lastError;
    lastServerFailures = 0;
    for (var i = 0; i < paths.length; i++) {
      try {
        final prepared = await compressImage(paths[i], maxSide: 2000, quality: 82);
        final file = File(prepared);
        if (!await file.exists()) {
          lastServerFailures++;
          continue;
        }
        final bytes = await file.readAsBytes();
        final response = await http
            .post(
              Uri.parse(serverUrl),
              headers: {'Content-Type': 'image/jpeg'},
              body: bytes,
            )
            .timeout(const Duration(seconds: 120));
        if (response.statusCode != 200) {
          lastError = '第 ${i + 1} 张服务端返回 ${response.statusCode}';
          lastServerFailures++;
          continue;
        }
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        if (data['ok'] != true) {
          lastError = '第 ${i + 1} 张：${data['error'] ?? '服务端识别失败'}';
          lastServerFailures++;
          continue;
        }
        final rows = data['rows'] as List<dynamic>? ?? [];
        if (rows.isEmpty) {
          lastError = '第 ${i + 1} 张未识别到数据';
          lastServerFailures++;
          continue;
        }
        for (final row in rows) {
          final map = row as Map<String, dynamic>;
          items.add(PickingItem(
            materialCode: '${map['materialCode'] ?? ''}',
            description: '${map['description'] ?? ''}',
            lpn: '${map['lpn'] ?? ''}',
            supplier: '${map['supplier'] ?? ''}',
            location: '${map['location'] ?? ''}',
            quantity: (map['quantity'] as num?)?.toInt() ?? 0,
            source: '服务端',
          ));
        }
      } catch (error) {
        lastError = '第 ${i + 1} 张：$error';
        lastServerFailures++;
      }
    }
    if (items.isEmpty && lastError != null) {
      throw OcrException(lastError);
    }
    return items;
  }

  /// 便于单元测试：只解析文本行，不依赖 ML Kit。
  static List<PickingItem> parsePickingTexts(List<String> texts) {
    return _parsePickingLines(
      texts.map((text) => OcrTextLine(text, 0, 0)).toList(),
    );
  }

  /// 便于单元测试：按文本和坐标解析表格。
  static List<PickingItem> parsePickingBoxes(List<OcrTextLine> lines) {
    return _parsePickingLines(lines);
  }

  static List<PickingItem> _parsePickingLines(List<OcrTextLine> lines) {
    if (lines.isEmpty) return <PickingItem>[];
    if (lines.every((e) => e.x == 0 && e.y == 0)) {
      return _parseFullLines(lines);
    }
    final columnItems = _parseColumnLines(lines);
    return columnItems.isNotEmpty ? columnItems : _parseFullLines(lines);
  }

  static OcrTextLine? _findHeader(List<OcrTextLine> lines, String keyword) {
    for (final line in lines) {
      if (line.text.replaceAll(RegExp(r'\s+'), '').contains(keyword)) {
        return line;
      }
    }
    return null;
  }

  static OcrTextLine? _nearestLine(List<OcrTextLine> candidates, double x, double y,
      double maxDx, double maxDy) {
    OcrTextLine? best;
    var bestDistance = double.infinity;
    for (final line in candidates) {
      final dx = (line.cx - x).abs();
      final dy = (line.cy - y).abs();
      if (dx > maxDx || dy > maxDy) continue;
      final distance = dx + dy * 1.6;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = line;
      }
    }
    return best;
  }

  static String _compactDigits(String text) =>
      text.replaceAll(',', '').replaceAll(RegExp(r'\s+'), '');

  static List<PickingItem> _parseColumnLines(List<OcrTextLine> lines) {
    final codeHeader = _findHeader(lines, '物料代码');
    final descHeader = _findHeader(lines, '物料描述');
    final lpnHeader = _findHeader(lines, 'LPN');
    final supplierHeader = _findHeader(lines, '供应商');
    final locationHeader = _findHeader(lines, '货位');
    final reserveHeader = _findHeader(lines, '预留数量');
    final allocHeader = _findHeader(lines, '分配数量');
    if (codeHeader == null || lpnHeader == null || supplierHeader == null) {
      return <PickingItem>[];
    }

    final codes = lines
        .where((line) {
          final match = RegExp(_codePattern).firstMatch(line.text);
          return match != null && line.cy > codeHeader.cy - 10;
        })
        .toList()
      ..sort((a, b) => a.y.compareTo(b.y));
    if (codes.isEmpty) return <PickingItem>[];

    final gaps = <double>[];
    for (var i = 1; i < codes.length; i++) {
      gaps.add(codes[i].cy - codes[i - 1].cy);
    }
    gaps.sort();
    final gap = gaps.isEmpty ? 80.0 : gaps[gaps.length ~/ 2];
    final rowTol = codes.length == 1 ? 230.0 : (gap * 0.8).clamp(35.0, 95.0);
    final descX = descHeader?.cx ??
        codeHeader.cx + (lpnHeader.cx - codeHeader.cx) / 2;
    final locationX = locationHeader?.cx ?? supplierHeader.cx + 100;
    final reserveX = reserveHeader?.cx ?? locationX + 100;
    final allocX = allocHeader?.cx ?? reserveX + (reserveX - locationX);
    final numberLines = lines.where((line) {
      final digits = _compactDigits(line.compact);
      return RegExp(r'^\d{1,6}$').hasMatch(digits);
    }).toList();

    final items = <PickingItem>[];
    for (final codeLine in codes) {
      final base = _parseSingleLine(codeLine);
      if (base == null) continue;
      final y = codeLine.cy;
      final candidates = lines
          .where((line) => (line.cy - y).abs() <= rowTol)
          .toList();

      // 独立于表头的行内兜底：按 x 坐标从左到右识别 LPN、供应商、货位、数量。
      // 这样即使 ML Kit 把表头合并成一行，也能正确取到这些列。
      final xsLines = candidates
          .where((line) =>
              line.cx > codeLine.cx &&
              RegExp(_xsBatchPattern, caseSensitive: false)
                  .hasMatch(line.compact))
          .toList()
        ..sort((a, b) => a.cx.compareTo(b.cx));
      final rowLpnLine = xsLines.isEmpty ? null : xsLines.first;
      final rowLpn = rowLpnLine == null
          ? ''
          : RegExp(_xsBatchPattern, caseSensitive: false)
              .firstMatch(rowLpnLine.compact)!
              .group(0)!
              .toUpperCase();

      final supplierCandidates = candidates.where((line) {
        final match = RegExp(_supplierPattern).firstMatch(line.compact);
        if (match == null) return false;
        return match.group(1) !=
            base.materialCode.substring(base.materialCode.length - 5);
      }).toList()
        ..sort((a, b) => a.cx.compareTo(b.cx));
      final lpnAnchor = rowLpnLine?.cx ?? codeLine.cx;
      final rowSupplierLine = supplierCandidates
              .where((line) => line.cx > lpnAnchor)
              .toList()
              .isEmpty
          ? (supplierCandidates.isEmpty ? null : supplierCandidates.first)
          : supplierCandidates.where((line) => line.cx > lpnAnchor).first;
      final rowSupplier = rowSupplierLine == null
          ? ''
          : RegExp(_supplierPattern)
              .firstMatch(rowSupplierLine.compact)!
              .group(1)!;

      final locationCandidates = candidates
          .where((line) =>
              line.cx > (rowSupplierLine?.cx ?? codeLine.cx) &&
              RegExp(_locationPattern).hasMatch(line.compact))
          .toList()
        ..sort((a, b) => a.cx.compareTo(b.cx));
      final rowLocationLine =
          locationCandidates.isEmpty ? null : locationCandidates.first;
      final rowLocation = rowLocationLine == null
          ? ''
          : RegExp(_locationPattern)
              .firstMatch(rowLocationLine.compact)!
              .group(1)!;

      final quantityAnchor =
          rowLocationLine?.cx ?? rowSupplierLine?.cx ?? codeLine.cx;
      final rowNumbers = candidates.where((line) {
        final digits = _compactDigits(line.compact);
        return line.cx > quantityAnchor &&
            RegExp(r'^\d{1,6}$').hasMatch(digits);
      }).toList()
        ..sort((a, b) => a.cx.compareTo(b.cx));
      final rowQuantityLine = rowNumbers.isEmpty
          ? null
          : (rowNumbers.length >= 2 ? rowNumbers[1] : rowNumbers.first);
      final rowQuantity = rowQuantityLine == null
          ? 0
          : int.tryParse(_compactDigits(rowQuantityLine.compact)) ?? 0;

      final lpnLine = base.lpn.isEmpty
          ? _nearestLine(
              candidates.where((line) => RegExp(_lpnPattern).hasMatch(line.compact)).toList(),
              lpnHeader.cx, y, 140, rowTol)
          : null;
      final lpn = base.lpn.isNotEmpty
          ? base.lpn
          : (lpnLine == null
              ? ''
              : RegExp(_lpnPattern)
                  .firstMatch(lpnLine.compact)!
                  .group(0)!
                  .replaceAll('O', '0')
                  .replaceAll('I', '1'));

      OcrTextLine? supplierLine;
      for (final line in candidates) {
        for (final match in RegExp(_supplierPattern).allMatches(line.compact)) {
          final value = match.group(1)!;
          if (value == base.materialCode.substring(base.materialCode.length - 5)) {
            continue;
          }
          if (supplierLine == null ||
              (line.cx - supplierHeader.cx).abs() <
                  (supplierLine.cx - supplierHeader.cx).abs()) {
            supplierLine = line;
          }
        }
      }
      final supplier = base.supplier.isNotEmpty
          ? base.supplier
          : supplierLine == null
              ? ''
              : RegExp(_supplierPattern)
                  .firstMatch(supplierLine.compact)!
                  .group(1)!;

      final locationLine = _nearestLine(
          candidates.where((line) => RegExp(_locationPattern).hasMatch(line.compact)).toList(),
          locationX, y, 150, rowTol);
      final location = base.location.isNotEmpty
          ? base.location
          : locationLine == null
              ? ''
              : RegExp(_locationPattern).firstMatch(locationLine.compact)!.group(1)!;

      final allocLine = _nearestLine(numberLines, allocX, y, 120, rowTol);
      final reserveLine = _nearestLine(numberLines, reserveX, y, 120, rowTol);
      final quantityLine = allocLine ?? reserveLine;
      final quantity = quantityLine == null
          ? base.quantity
          : int.tryParse(_compactDigits(quantityLine.compact)) ?? base.quantity;

      final descLine = base.description.isEmpty
          ? _nearestLine(
              candidates.where((line) {
                if (line == codeLine || RegExp(_codePattern).hasMatch(line.text)) {
                  return false;
                }
                if (RegExp(_lpnPattern).hasMatch(line.compact)) return false;
                if (RegExp(_supplierPattern).hasMatch(line.compact)) return false;
                if (RegExp(_locationPattern).hasMatch(line.compact)) return false;
                return line.cx > codeHeader.cx - 10 && line.cx < lpnHeader.cx;
              }).toList(),
              descX, y, 180, rowTol)
          : null;
      final description = base.description.isNotEmpty
          ? base.description
          : (descLine?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '');

      final finalLpn = rowLpn.isNotEmpty ? rowLpn : lpn;
      final finalSupplier = rowSupplier.isNotEmpty ? rowSupplier : supplier;
      final finalLocation = rowLocation.isNotEmpty ? rowLocation : location;
      final finalQuantity = rowQuantity > 0 ? rowQuantity : quantity;

      items.add(PickingItem(
        materialCode: base.materialCode,
        description: description,
        lpn: finalLpn,
        supplier: finalSupplier,
        location: finalLocation,
        quantity: finalQuantity,
      ));
    }
    return items;
  }

  static PickingItem? _parseSingleLine(OcrTextLine line) {
    final text = line.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final codeMatch = RegExp(_codePattern).firstMatch(text);
    if (codeMatch == null) return null;
    final code = codeMatch.group(1)!;
    final lpnMatch = RegExp(_lpnPattern).firstMatch(text);
    final lpn = (lpnMatch?.group(0) ?? '').toUpperCase().replaceAll('O', '0').replaceAll('I', '1');
    final supplierMatches = RegExp(_supplierPattern).allMatches(text).toList();
    var supplier = '';
    for (final match in supplierMatches) {
      final value = match.group(1)!;
      if (value != code.substring(code.length - 5)) {
        supplier = value;
        break;
      }
    }
    final locationMatch = RegExp(_locationPattern).firstMatch(text);
    final location = locationMatch?.group(1) ?? '';
    var descriptionEnd = text.length;
    if (lpnMatch != null && lpnMatch.start > codeMatch.end) {
      descriptionEnd = lpnMatch.start;
    }
    var description = text.substring(codeMatch.end, descriptionEnd);
    description = description
        .replaceAll(RegExp(r'物料描述|物料代码|供应商|货位|LPN', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    var quantityStart = codeMatch.end;
    if (lpnMatch != null && lpnMatch.end > quantityStart) quantityStart = lpnMatch.end;
    if (locationMatch != null && locationMatch.end > quantityStart) {
      quantityStart = locationMatch.end;
    }
    if (supplierMatches.isNotEmpty) {
      final lastSupplier = supplierMatches.last;
      if (lastSupplier.end > quantityStart) quantityStart = lastSupplier.end;
    }
    final quantityText = text.substring(quantityStart);
    final numbers = RegExp(r'\b\d{1,6}\b')
        .allMatches(quantityText)
        .map((m) => int.tryParse(m.group(0)!) ?? 0)
        .where((n) => n > 0)
        .toList();
    final quantity = numbers.isEmpty
        ? 0
        : (numbers.length >= 2 ? numbers[1] : numbers.first);
    return PickingItem(
      materialCode: code,
      description: description,
      lpn: lpn,
      supplier: supplier,
      location: location,
      quantity: quantity,
    );
  }

  static List<PickingItem> _parseFullLines(List<OcrTextLine> lines) {
    final items = <PickingItem>[];
    for (final line in lines) {
      final item = _parseSingleLine(line);
      if (item != null) items.add(item);
    }
    return items;
  }

  static Future<GoodsLabelData> recognizeLabelPaths(List<String> paths) async {
    final result = GoodsLabelData();
    for (final path in paths.take(3)) {
      final prepared = await compressImage(path, maxSide: 1800, quality: 88);
      var best = _parseLabel(await _recognizeLines(prepared));
      var bestScore = _labelScore(best);
      var bestManufacturer = best.manufacturer;
      final allManufacturers = <String>[...best.manufacturerCandidates];
      if (bestManufacturer.isNotEmpty) allManufacturers.add(bestManufacturer);
      if (bestScore < 17) {
        for (final angle in <int>[90, 180, 270]) {
          try {
            final rotated = await _rotateImage(prepared, angle);
            final candidate = _parseLabel(await _recognizeLines(rotated));
            final score = _labelScore(candidate);
            allManufacturers.addAll(candidate.manufacturerCandidates);
            if (candidate.manufacturer.length > bestManufacturer.length) {
              bestManufacturer = candidate.manufacturer;
            }
            if (score > bestScore) {
              best = candidate;
              bestScore = score;
            }
          } catch (_) {
            // 某个方向失败不影响其它方向
          }
        }
      }
      if (bestManufacturer.isNotEmpty) best.manufacturer = bestManufacturer;
      for (final manufacturer in allManufacturers) {
        if (!result.manufacturerCandidates.contains(manufacturer)) {
          result.manufacturerCandidates.add(manufacturer);
        }
      }
      if (result.materialCode.isEmpty && best.materialCode.isNotEmpty) {
        result.materialCode = best.materialCode;
      }
      if (result.description.isEmpty && best.description.isNotEmpty) {
        result.description = best.description;
      }
      if (result.lpn.isEmpty && best.lpn.isNotEmpty) result.lpn = best.lpn;
      if (result.perBox <= 0 && best.perBox > 0) result.perBox = best.perBox;
      if (result.supplier.isEmpty && best.supplier.isNotEmpty) {
        result.supplier = best.supplier;
      }
      if (result.manufacturer.isEmpty && best.manufacturer.isNotEmpty) {
        result.manufacturer = best.manufacturer;
      }
    }
    return result;
  }

  static int _labelScore(GoodsLabelData data) {
    var score = 0;
    if (data.materialCode.isNotEmpty) score += 8;
    if (data.description.isNotEmpty) score += 4;
    if (data.lpn.isNotEmpty) score += 4;
    if (data.perBox > 0) score += 3;
    if (data.manufacturer.isNotEmpty) score += 2;
    return score;
  }

  static Future<String> _rotateImage(String path, int angle) async {
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return path;
    final rotated = img.copyRotate(decoded, angle: angle);
    final dir = await getTemporaryDirectory();
    final out = File(p.join(dir.path,
        'ocr_rot_${angle}_${DateTime.now().microsecondsSinceEpoch}.jpg'));
    await out.writeAsBytes(img.encodeJpg(rotated, quality: 90));
    return out.path;
  }

  /// 便于单元测试：只解析标签文本。
  static GoodsLabelData parseLabelTexts(List<String> texts) {
    return _parseLabel(
      texts
          .map((text) => OcrTextLine(text, 0, 0))
          .toList(),
    );
  }

  static GoodsLabelData _parseLabel(List<OcrTextLine> lines) {
    final data = GoodsLabelData();
    final all = lines.map((e) => e.text.replaceAll(RegExp(r'\s+'), ' ').trim()).toList();
    for (final text in all) {
      final match = RegExp(_codePattern).firstMatch(text);
      if (match != null) {
        data.materialCode = match.group(1)!;
        break;
      }
    }
    for (final text in all) {
      final index = text.indexOf('物料描述');
      if (index >= 0) {
        var value = text.substring(index + 4).replaceFirst(RegExp(r'^[:：\s]+'), '').trim();
        if (value.isNotEmpty && !value.contains('有限公司')) {
          data.description = value;
        }
        break;
      }
    }
    if (data.description.isEmpty) {
      for (final text in all) {
        if (RegExp(r'[\u4e00-\u9fa5A-Za-z_]{2,}').hasMatch(text) &&
            !text.contains('有限公司') &&
            !text.contains('物料代码') &&
            !text.contains('包装数量') &&
            !text.contains('生产')) {
          data.description = text;
          break;
        }
      }
    }
    for (final text in all) {
      final match = RegExp(_xsBatchPattern, caseSensitive: false).firstMatch(text);
      if (match != null) {
        data.lpn = match.group(0)!.toUpperCase().replaceAll('O', '0').replaceAll('I', '1');
        break;
      }
    }
    for (final text in all) {
      final match = RegExp(r'(?:包装数量|数量)\s*[:：]?\s*(\d{1,5})').firstMatch(text);
      if (match != null) {
        final value = int.tryParse(match.group(1)!) ?? 0;
        if (value > 0 && value < 100000) {
          data.perBox = value;
          break;
        }
      }
    }
    if (data.perBox <= 0) {
      for (var i = 0; i < all.length; i++) {
        if (!all[i].contains('包装数量') && !all[i].contains('数量')) continue;
        for (var j = i + 1; j < all.length && j <= i + 3; j++) {
          final value = int.tryParse(all[j].trim());
          if (value == null || value <= 0 || value > 99999) continue;
          if (all[j].contains(RegExp(r'890\d{6}'))) continue;
          data.perBox = value;
          break;
        }
        if (data.perBox > 0) break;
      }
    }
    for (final text in all) {
      if (text.contains('供应商')) {
        final match = RegExp(_supplierPattern).firstMatch(text);
        if (match != null) data.supplier = match.group(1)!;
        break;
      }
    }
    final candidates = <String>[];
    for (final text in all) {
      if (_looksLikeCompany(text) &&
          !text.contains('收货单位') &&
          !text.contains('送货单位')) {
        if (!candidates.contains(text)) candidates.add(text);
      }
    }
    // 供应商名称可能被 OCR 单独拆成一行，例如“甲供应商”。
    for (final text in all) {
      if (text.length >= 2 &&
          RegExp(r'[\u4e00-\u9fa5]{2,}').hasMatch(text) &&
          !candidates.contains(text) &&
          !text.contains('物料代码') &&
          !text.contains('包装数量') &&
          !text.contains('物料描述')) {
        candidates.add(text);
      }
    }
    for (var i = 0; i < all.length; i++) {
      final text = all[i];
      var index = text.indexOf('制造商');
      var labelLength = 3;
      if (index < 0) {
        index = text.indexOf('制造厂');
        labelLength = 3;
      }
      if (index < 0) {
        index = text.indexOf('生产厂家');
        labelLength = 4;
      }
      if (index < 0) {
        index = text.indexOf('生产商');
        labelLength = 3;
      }
      if (index < 0) {
        index = text.indexOf('制造企业');
        labelLength = 4;
      }
      if (index < 0) continue;
      final value = text
          .substring(index + labelLength)
          .replaceFirst(RegExp(r'^[:：\s]+'), '')
          .trim();
      if (value.isNotEmpty && _looksLikeCompany(value)) {
        data.manufacturer = value;
        break;
      }
      // “制造商”与公司名被 OCR 拆成两行时，向下找最多 3 行。
      for (var j = i + 1; j < all.length && j <= i + 3; j++) {
        if (_looksLikeCompany(all[j])) {
          data.manufacturer = all[j];
          break;
        }
      }
      if (data.manufacturer.isNotEmpty) break;
    }
    if (data.manufacturer.isEmpty && candidates.isNotEmpty) {
      candidates.sort((a, b) => b.length.compareTo(a.length));
      data.manufacturer = candidates.first;
    }
    if (data.manufacturer.isNotEmpty && !candidates.contains(data.manufacturer)) {
      candidates.add(data.manufacturer);
    }
    data.manufacturerCandidates = candidates;
    return data;
  }

  static bool _looksLikeCompany(String text) {
    if (text.length < 4) return false;
    return text.contains('有限公司') ||
        text.contains('股份公司') ||
        text.contains('集团') ||
        text.endsWith('厂') ||
        text.contains('科技') ||
        text.contains('电器');
  }

  static Future<List<OcrTextLine>> _recognizeLines(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    try {
      final input = InputImage.fromFilePath(path);
      final result = await recognizer.processImage(input);
      final lines = <OcrTextLine>[];
      for (final block in result.blocks) {
        for (final line in block.lines) {
          final box = line.boundingBox;
          lines.add(OcrTextLine(line.text, box.left, box.top,
              width: box.width, height: box.height));
        }
      }
      return lines;
    } finally {
      await recognizer.close();
    }
  }

  static Future<String> compressImage(String path, {int maxSide = 1200, int quality = 72}) async {
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return path;
    final longest = decoded.width > decoded.height ? decoded.width : decoded.height;
    if (longest <= maxSide) return path;
    final scale = maxSide / longest;
    final resized = img.copyResize(
      decoded,
      width: (decoded.width * scale).round(),
      height: (decoded.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
    final dir = await getTemporaryDirectory();
    final name = 'ocr_${DateTime.now().microsecondsSinceEpoch}${p.extension(path)}';
    final out = File(p.join(dir.path, name));
    await out.writeAsBytes(img.encodeJpg(resized, quality: quality));
    return out.path;
  }
}
