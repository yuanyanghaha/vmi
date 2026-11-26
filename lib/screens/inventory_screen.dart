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
import 'inventory_records_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _picker = ImagePicker();
  final _systemController = TextEditingController();
  final _actualController = TextEditingController();
  final _codeController = TextEditingController();
  final _perBoxController = TextEditingController();
  final _descController = TextEditingController();
  final _batchController = TextEditingController();

  List<SupplierInfo> _suppliers = [];
  String? _supplierCode;
  String _recognizedManufacturer = '';
  String? _imagePath;
  String? _error;
  bool _busy = false;
  int? _actualPreview;

  @override
  void initState() {
    super.initState();
    _actualController.addListener(_updateActualPreview);
    _loadSuppliers();
  }

  @override
  void dispose() {
    _actualController.removeListener(_updateActualPreview);
    _systemController.dispose();
    _actualController.dispose();
    _codeController.dispose();
    _perBoxController.dispose();
    _descController.dispose();
    _batchController.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    final suppliers = await AppRepository.loadSuppliers();
    if (!mounted) return;
    setState(() => _suppliers = suppliers);
  }

  SupplierInfo? get _selectedSupplier {
    for (final supplier in _suppliers) {
      if (supplier.code == _supplierCode) return supplier;
    }
    return null;
  }

  void _updateActualPreview() {
    final text = _actualController.text.trim();
    if (text.isEmpty) {
      if (mounted) setState(() => _actualPreview = null);
      return;
    }
    try {
      final value = ExpressionEvaluator.evaluate(text);
      if (mounted) setState(() => _actualPreview = value.toInt());
    } catch (_) {
      if (mounted) setState(() => _actualPreview = null);
    }
  }

  void _insertActual(String value) {
    final text = _actualController.text;
    final selection = _actualController.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final next = text.replaceRange(start, end, value);
    _actualController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + value.length),
    );
  }

  Future<void> _pickAndRecognize() async {
    if (_busy) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SheetHandle(),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('拍摄货品图片'),
                subtitle: const Text('拍摄箱贴或货品标签'),
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
      if (_suppliers.isEmpty) await _loadSuppliers();
      if (data.materialCode.isNotEmpty) _codeController.text = data.materialCode;
      if (data.description.isNotEmpty) _descController.text = data.description;
      if (data.lpn.isNotEmpty) _batchController.text = data.lpn;
      if (data.perBox > 0) _perBoxController.text = '${data.perBox}';
      _recognizedManufacturer = data.manufacturer;
      if (data.manufacturer.isNotEmpty) {
        final matched = SupplierMatcher.matchAny(
          <String>[data.manufacturer, ...data.manufacturerCandidates],
          _suppliers,
        );
        _supplierCode = matched?.code;
      } else if (data.manufacturerCandidates.isNotEmpty) {
        final matched = SupplierMatcher.matchAny(
            data.manufacturerCandidates, _suppliers);
        _supplierCode = matched?.code;
        _recognizedManufacturer = data.manufacturerCandidates.first;
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
    if (text.trim().isEmpty) {
      setState(() => _error = '请填写$label');
      return null;
    }
    try {
      final value = ExpressionEvaluator.evaluate(text);
      if (value < 0 || value != value.roundToDouble()) {
        setState(() => _error = '$label 必须是整数');
        return null;
      }
      return value.toInt();
    } catch (e) {
      setState(() => _error = '$label 格式错误：$e');
      return null;
    }
  }

  Future<String> _saveImage(String source) async {
    final compressed =
        await OcrService.compressImage(source, maxSide: 1200, quality: 80);
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(dir.path, 'inventory_images'));
    await folder.create(recursive: true);
    final target = p.join(folder.path,
        'inventory_${DateTime.now().microsecondsSinceEpoch}${p.extension(compressed)}');
    await File(compressed).copy(target);
    return target;
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _error = null);
    final systemStock = _parseStock(_systemController.text, '系统库存');
    if (systemStock == null) return;
    final actualStock = _parseStock(_actualController.text, '实际库存');
    if (actualStock == null) return;
    if (!RegExp(r'^\d{9}$').hasMatch(_codeController.text.trim())) {
      setState(() => _error = '请先识别或填写 9 位物料代码');
      return;
    }
    final perBox = int.tryParse(_perBoxController.text.trim()) ?? 0;
    if (perBox <= 0) {
      setState(() => _error = '请先识别或填写包装数量');
      return;
    }
    final supplier = _selectedSupplier;
    if (supplier == null) {
      setState(() => _error = '请选择供应商');
      return;
    }
    setState(() => _busy = true);
    try {
      String savedImage = '';
      if (_imagePath != null) savedImage = await _saveImage(_imagePath!);
      final record = InventoryRecord(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        createdAt: DateTime.now(),
        systemStock: systemStock,
        actualStock: actualStock,
        materialCode: _codeController.text.trim(),
        perBox: perBox,
        description: _descController.text.trim(),
        batch: _batchController.text.trim(),
        manufacturer: supplier.name,
        imagePath: savedImage,
      );
      final list = await AppRepository.loadInventory();
      list.insert(0, record);
      await AppRepository.saveInventory(list);
      _systemController.clear();
      _actualController.clear();
      _codeController.clear();
      _perBoxController.clear();
      _descController.clear();
      _batchController.clear();
      _recognizedManufacturer = '';
      setState(() {
        _imagePath = null;
        _supplierCode = null;
        _actualPreview = null;
      });
      if (mounted) showMessage(context, '库存记录已保存');
    } catch (e) {
      setState(() => _error = '保存失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRecords() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InventoryRecordsScreen()),
    );
    await _loadSuppliers();
  }

  Future<void> _openCalculator() async {
    FocusManager.instance.primaryFocus?.unfocus();
    var expression = '';
    var result = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        String evaluate() {
          if (expression.trim().isEmpty) return '';
          var text = expression;
          while (text.isNotEmpty &&
              (text.endsWith('+') || text.endsWith('*'))) {
            text = text.substring(0, text.length - 1);
          }
          try {
            final value = ExpressionEvaluator.evaluate(text);
            return value == value.roundToDouble()
                ? '${value.toInt()}'
                : '$value';
          } catch (_) {
            return '';
          }
        }

        return StatefulBuilder(
          builder: (context, setSheetState) {
            void press(String value) {
              if (value == '填入') {
                if (result.isNotEmpty) {
                  _actualController.text = result;
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
                      height: 48,
                      child: FilledButton(
                        onPressed: () => press(label),
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          backgroundColor:
                              color ?? const Color(0xFFF4F7FD),
                          foregroundColor: fg ?? AppColors.text,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
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
                    const _SheetHandle(),
                    Row(
                      children: [
                        const Text('简易计算器',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFD),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(expression.isEmpty ? '0' : expression,
                              style: const TextStyle(
                                  fontSize: 26, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(result.isEmpty ? '只支持 + 和 *' : '= $result',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: result.isEmpty
                                      ? AppColors.sub
                                      : AppColors.primary)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
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
                      key('填入', color: const Color(0xFFEEF4FF), fg: AppColors.primary),
                    ]),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.soft,
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  _roundIcon(Icons.chevron_left, () => Navigator.pop(context)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('货品库存统计',
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w800)),
                        Text('拍照识别 · 录入库存 · 导出记录',
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFF98A2B3))),
                      ],
                    ),
                  ),
                  _roundIcon(Icons.calculate_outlined, _openCalculator),
                  const SizedBox(width: 6),
                  _roundIcon(Icons.receipt_long_outlined, _openRecords),
                ],
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                  child: Column(
                    children: [
                      SectionCard(child: _imageCard()),
                      const SizedBox(height: 12),
                      SectionCard(child: _formCard()),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundIcon(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 21, color: AppColors.text),
        ),
      ),
    );
  }

  Widget _imageCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('货品图片',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            if (_busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_imagePath != null)
          GestureDetector(
            onTap: () => _preview(_imagePath!),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  Image.file(File(_imagePath!),
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8)),
                      child: const Text('点击放大',
                          style: TextStyle(fontSize: 10, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            width: double.infinity,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5ECF8)),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.document_scanner_outlined,
                    color: AppColors.primary, size: 26),
                SizedBox(height: 6),
                Text('拍摄箱贴或货品标签，自动回填字段',
                    style: TextStyle(fontSize: 11, color: AppColors.sub)),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _pickAndRecognize,
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: Text(_busy ? '识别中...' : '拍图识别'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _openRecords,
                icon: const Icon(Icons.list_alt_outlined, size: 18),
                label: const Text('库存记录'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _formCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('库存信息',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _input(_systemController, '系统库存', Icons.warehouse_outlined)),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _actualController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+*]')),
                ],
                decoration: InputDecoration(
                  labelText: '实际库存',
                  hintText: '30+20+35',
                  prefixIcon: const Icon(Icons.fact_check_outlined, size: 19),
                  suffixIcon: IconButton(
                    tooltip: '插入 +',
                    onPressed: () => _insertActual('+'),
                    icon: const Icon(Icons.add, size: 19),
                  ),
                  helperText: _actualPreview == null ? null : '合计 ${_actualPreview!}',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _input(_codeController, '物料代码', Icons.qr_code_2_outlined,
            keyboardType: TextInputType.number, maxLength: 9),
        _input(_perBoxController, '包装数量', Icons.inventory_2_outlined,
            keyboardType: TextInputType.number),
        _input(_descController, '物料描述', Icons.description_outlined),
        _input(_batchController, 'XS 批次号', Icons.confirmation_number_outlined),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          // ignore: deprecated_member_use
          value: _supplierCode,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '供应商（原制造商）',
            prefixIcon: Icon(Icons.storefront_outlined, size: 19),
          ),
          hint: const Text('请选择供应商'),
          items: _suppliers
              .map((supplier) => DropdownMenuItem(
                    value: supplier.code,
                    child: Text('${supplier.code}  ${supplier.name}',
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (value) => setState(() => _supplierCode = value),
        ),
        if (_suppliers.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('尚未录入供应商，请先到货品配置添加',
                style: TextStyle(fontSize: 10, color: AppColors.red)),
          ),
        if (_recognizedManufacturer.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('识别到的制造商：$_recognizedManufacturer',
                style: const TextStyle(fontSize: 10, color: Color(0xFF98A2B3))),
          ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(fontSize: 11, color: AppColors.red)),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? '保存中...' : '保存库存记录'),
          ),
        ),
      ],
    );
  }

  Widget _input(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboardType,
    int? maxLength,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLength: maxLength,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 19),
          counterText: '',
        ),
      ),
    );
  }

  Future<void> _preview(String path) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: Center(
                child: Image.file(File(path), fit: BoxFit.contain),
              ),
            ),
          ),
          Positioned(
            top: 30,
            right: 16,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 4,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE0E6F0),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
