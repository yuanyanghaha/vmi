import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../calculator.dart';
import '../models.dart';
import '../ocr_service.dart';
import '../repository.dart';
import '../supplier_matcher.dart';
import '../widgets.dart';

class InventoryFormDialog extends StatefulWidget {
  const InventoryFormDialog({super.key, required this.suppliers});
  final List<SupplierInfo> suppliers;

  @override
  State<InventoryFormDialog> createState() => _InventoryFormDialogState();
}

class _InventoryFormDialogState extends State<InventoryFormDialog> {
  final _picker = ImagePicker();
  final _system = TextEditingController();
  final _actual = TextEditingController();
  final _code = TextEditingController();
  final _perBox = TextEditingController();
  final _desc = TextEditingController();
  final _batch = TextEditingController();
  String? _supplierCode;
  String _recognizedManufacturer = '';
  String? _imagePath;
  String? _error;
  String _hint = '';
  bool _busy = false;

  @override
  void dispose() {
    _system.dispose();
    _actual.dispose();
    _code.dispose();
    _perBox.dispose();
    _desc.dispose();
    _batch.dispose();
    super.dispose();
  }

  SupplierInfo? get _supplier {
    for (final item in widget.suppliers) {
      if (item.code == _supplierCode) return item;
    }
    return null;
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                    color: const Color(0xFFE0E6F0),
                    borderRadius: BorderRadius.circular(4)),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('拍摄货品图片'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('从相册选择'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;
    final file = await _picker.pickImage(source: source, imageQuality: 92);
    if (file == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _imagePath = file.path;
    });
    try {
      final data = await OcrService.recognizeLabelPaths([file.path]);
      if (data.materialCode.isNotEmpty) _code.text = data.materialCode;
      if (data.description.isNotEmpty) _desc.text = data.description;
      if (data.lpn.isNotEmpty) _batch.text = data.lpn;
      if (data.perBox > 0) _perBox.text = '${data.perBox}';
      _recognizedManufacturer = data.manufacturer;
      final matched = SupplierMatcher.matchAny([
        data.manufacturer,
        ...data.manufacturerCandidates,
      ], widget.suppliers);
      _supplierCode = matched?.code;
      final records = await AppRepository.loadInventory();
      InventoryRecord? existing;
      for (final record in records) {
        if (record.materialCode != data.materialCode) continue;
        if (matched != null &&
            SupplierMatcher.match(record.manufacturer, widget.suppliers)?.code !=
                matched.code) {
          continue;
        }
        existing = record;
        break;
      }
      if (existing != null) {
        _system.text = '${existing.systemStock}';
        _actual.text = '${existing.actualStock}';
        _perBox.text = '${existing.perBox}';
        _desc.text = existing.description;
        _batch.text = existing.batch;
        final existingSupplier =
            SupplierMatcher.match(existing.manufacturer, widget.suppliers);
        if (existingSupplier != null) _supplierCode = existingSupplier.code;
        _hint = '已存在该货品库存，已带出原有数据';
      } else {
        _hint = '';
      }
      if (data.materialCode.isEmpty &&
          data.description.isEmpty &&
          data.perBox <= 0 &&
          data.lpn.isEmpty &&
          data.manufacturer.isEmpty) {
        setState(() => _error = '未识别到货品信息，请换一张更清晰的标签照片');
      }
    } catch (e) {
      setState(() => _error = '图片识别失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int? _parseStock(String text, String label) {
    final value = int.tryParse(text.trim());
    if (value == null || value < 0) {
      setState(() => _error = '$label 需要是非负整数');
      return null;
    }
    return value;
  }

  Future<String> _saveImage(String source) async {
    final compressed =
        await OcrService.compressImage(source, maxSide: 1200, quality: 80);
    final root = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(root.path, 'inventory_images'));
    await folder.create(recursive: true);
    final target = p.join(folder.path,
        'inventory_${DateTime.now().microsecondsSinceEpoch}${p.extension(compressed)}');
    await File(compressed).copy(target);
    return target;
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _error = null);
    if (!RegExp(r'^\d{9}$').hasMatch(_code.text.trim())) {
      setState(() => _error = '物料代码需要是 9 位数字');
      return;
    }
    final perBox = int.tryParse(_perBox.text.trim()) ?? 0;
    if (perBox <= 0) {
      setState(() => _error = '包装数量必须是正整数');
      return;
    }
    final supplier = _supplier;
    if (supplier == null) {
      setState(() => _error = '请选择供应商');
      return;
    }
    final system = _parseStock(_system.text, '系统库存');
    if (system == null) return;
    final actual = _parseStock(_actual.text, '实际库存');
    if (actual == null) return;
    setState(() => _busy = true);
    try {
      String image = '';
      if (_imagePath != null) image = await _saveImage(_imagePath!);
      final record = InventoryRecord(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        createdAt: DateTime.now(),
        systemStock: system,
        actualStock: actual,
        materialCode: _code.text.trim(),
        perBox: perBox,
        description: _desc.text.trim(),
        batch: _batch.text.trim(),
        manufacturer: supplier.name,
        imagePath: image,
      );
      if (mounted) Navigator.pop(context, record);
    } catch (e) {
      setState(() => _error = '保存失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _calculator() async {
    FocusManager.instance.primaryFocus?.unfocus();
    var expression = '';
    var result = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          String evaluate() {
            var text = expression;
            while (text.isNotEmpty &&
                (text.endsWith('+') || text.endsWith('*'))) {
              text = text.substring(0, text.length - 1);
            }
            try {
              final value = ExpressionEvaluator.evaluate(text);
              return value == value.roundToDouble() ? '${value.toInt()}' : '$value';
            } catch (_) {
              return '';
            }
          }

          void press(String value) {
            if (value == '填入') {
              if (result.isNotEmpty) {
                _actual.text = result;
                Navigator.pop(context);
              }
              return;
            }
            setSheetState(() {
              if (value == '+' || value == '*') {
                if (expression.isEmpty) return;
                final last = expression[expression.length - 1];
                if (last == '+' || last == '*') {
                  expression = expression.substring(0, expression.length - 1);
                }
              }
              expression += value;
              result = evaluate();
            });
          }

          Widget key(String label, {Color? color, Color? fg}) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: SizedBox(
                    height: 46,
                    child: FilledButton(
                      onPressed: () => press(label),
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: color ?? const Color(0xFFF4F7FD),
                        foregroundColor: fg ?? AppColors.text,
                      ),
                      child: Text(label,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              );

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                        color: const Color(0xFFE0E6F0),
                        borderRadius: BorderRadius.circular(4)),
                  ),
                  Row(
                    children: [
                      const Text('计算器',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('关闭')),
                    ],
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFD),
                        borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(expression.isEmpty ? '0' : expression,
                            style: const TextStyle(
                                fontSize: 25, fontWeight: FontWeight.w700)),
                        Text(result.isEmpty ? '只支持 + 和 *' : '= $result',
                            style: TextStyle(
                                fontSize: 12,
                                color: result.isEmpty
                                    ? AppColors.sub
                                    : AppColors.primary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(children: [
                    key('7'),
                    key('8'),
                    key('9'),
                    key('+', color: const Color(0xFFEEF4FF), fg: AppColors.primary)
                  ]),
                  Row(children: [
                    key('4'),
                    key('5'),
                    key('6'),
                    key('*', color: const Color(0xFFEEF4FF), fg: AppColors.primary)
                  ]),
                  Row(children: [
                    key('1'),
                    key('2'),
                    key('3'),
                    key('清除', color: const Color(0xFFFFF1F2), fg: AppColors.red)
                  ]),
                  Row(children: [
                    key('0'),
                    key('退格'),
                    key('=', color: AppColors.primary, fg: Colors.white),
                    key('填入', color: const Color(0xFFEEF4FF), fg: AppColors.primary)
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('新增库存记录',
                        style: TextStyle(
                            fontSize: 19, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    tooltip: '计算器',
                    onPressed: _busy ? null : _calculator,
                    icon: const Icon(Icons.calculate_outlined),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                child: Column(
                  children: [
                    if (_imagePath != null)
                      GestureDetector(
                        onTap: () => _showImage(_imagePath!),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(File(_imagePath!),
                              width: double.infinity,
                              height: 130,
                              fit: BoxFit.cover),
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        height: 92,
                        decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(12)),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.document_scanner_outlined,
                                color: AppColors.primary),
                            SizedBox(height: 4),
                            Text('拍摄标签后自动回填，也可手动填写',
                                style: TextStyle(
                                    fontSize: 11, color: AppColors.sub)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _pickImage,
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: Text(_busy ? '识别中...' : '拍照/上传识别'),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(38)),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _system,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: '系统库存'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _actual,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            decoration: const InputDecoration(
                              labelText: '实际库存',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      maxLength: 9,
                      decoration: const InputDecoration(
                          labelText: '物料代码', counterText: ''),
                    ),
                    TextField(
                      controller: _perBox,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '包装数量'),
                    ),
                    TextField(
                      controller: _desc,
                      decoration: const InputDecoration(labelText: '物料描述'),
                    ),
                    TextField(
                      controller: _batch,
                      decoration: const InputDecoration(labelText: 'XS 批次号'),
                    ),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: _supplierCode,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: '供应商'),
                      hint: const Text('请选择供应商'),
                      items: widget.suppliers
                          .map((s) => DropdownMenuItem(
                                value: s.code,
                                child: Text('${s.code}  ${s.name}',
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _supplierCode = value),
                    ),
                    if (widget.suppliers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('尚未配置供应商，请先到货品配置添加',
                            style:
                                TextStyle(fontSize: 10, color: AppColors.red)),
                      ),
                    if (_recognizedManufacturer.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('识别制造商：$_recognizedManufacturer',
                            style: const TextStyle(
                                fontSize: 10, color: Color(0xFF98A2B3))),
                      ),
                    if (_hint.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(_hint,
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.green)),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(_error!,
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.red)),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_busy ? '保存中...' : '保存库存记录'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showImage(String path) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              child: Center(
                  child: Image.file(File(path), fit: BoxFit.contain)),
            ),
          ),
          Positioned(
            top: 30,
            right: 16,
            child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close,
                    color: Colors.white, size: 30)),
          ),
        ],
      ),
    );
  }
}
