import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../calculator.dart';
import '../models.dart';
import '../ocr_service.dart';
import '../repository.dart';
import '../widgets.dart';
import 'image_annotator.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final _searchSupplier = TextEditingController();
  final _searchCode = TextEditingController();
  final _picker = ImagePicker();
  List<CatalogItem> _items = [];
  List<SupplierInfo> _suppliers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchSupplier.dispose();
    _searchCode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await AppRepository.loadCatalog();
    final suppliers = await AppRepository.loadSuppliers();
    if (!mounted) return;
    setState(() {
      _items = items;
      _suppliers = suppliers;
    });
  }

  List<CatalogItem> get _filtered {
    final supplierQuery = _searchSupplier.text.trim();
    final codeQuery = _searchCode.text.trim();
    if (supplierQuery.isEmpty && codeQuery.isEmpty) return _items;
    return _items.where((item) {
      if (supplierQuery.isNotEmpty) {
        final name = _supplierName(item.supplier);
        if (!item.supplier.contains(supplierQuery) && !name.contains(supplierQuery)) {
          return false;
        }
      }
      if (codeQuery.isNotEmpty) {
        if (codeQuery.length <= 4) {
          if (!item.materialCode.endsWith(codeQuery)) return false;
        } else if (!item.materialCode.contains(codeQuery)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  String _supplierName(String code) {
    for (final s in _suppliers) {
      if (s.code == code) return s.name;
    }
    return '';
  }

  Future<void> _previewImage(String path) async {
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
                child: Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Text('图片无法加载',
                      style: TextStyle(color: Colors.white)),
                ),
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

  Future<String> _saveCatalogImage(String source) async {
    final compressed = await OcrService.compressImage(source, maxSide: 800, quality: 62);
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(dir.path, 'catalog_images'));
    await folder.create(recursive: true);
    final target = p.join(folder.path,
        'goods_${DateTime.now().microsecondsSinceEpoch}${p.extension(compressed)}');
    await File(compressed).copy(target);
    return target;
  }

  Future<void> _openBoxCalculator(CatalogItem item) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final controller = TextEditingController();
    var result = '';
    var error = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          void update(String value) {
            setSheetState(() {
              result = '';
              error = '';
              if (value.trim().isEmpty) return;
              try {
                final outcome = BoxCalculator.calculate(value, '${item.perBox}');
                result = '共 ${outcome.total} 个 · 整箱 ${outcome.boxes} 箱，余 ${outcome.remainder} 个';
              } catch (e) {
                error = '$e';
              }
            });
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  18, 10, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                          color: const Color(0xFFE0E6F0),
                          borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  Row(
                    children: [
                      const Text('装箱计算器',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('关闭')),
                    ],
                  ),
                  Text(
                    '${item.materialCode}${item.description.isEmpty ? '' : ' · ${item.description}'}',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF98A2B3)),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF4FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Text('每箱数量',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.sub)),
                        const Spacer(),
                        Text('${item.perBox} 个',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    onChanged: update,
                    decoration: const InputDecoration(
                      labelText: '货品总数',
                      hintText: '例如 100+30',
                    ),
                  ),
                  if (result.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(result,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ],
                  if (error.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(error,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.red)),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
    controller.dispose();
  }

  Future<void> _openGoodsDialog({CatalogItem? existing}) async {
    if (_suppliers.isEmpty && existing == null) {
      showMessage(context, '请先添加供应商');
      await _openSupplierManager();
      return;
    }
    final codeController = TextEditingController(text: existing?.materialCode ?? '');
    final descController = TextEditingController(text: existing?.description ?? '');
    final lpnController = TextEditingController(text: existing?.lpn ?? '');
    final perBoxController =
        TextEditingController(text: existing == null ? '' : '${existing.perBox}');
    var selectedSupplier = existing?.supplier ?? (_suppliers.isNotEmpty ? _suppliers.first.code : '');
    final images = List<String>.from(existing?.images ?? <String>[]);
    var recognizing = false;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? '新增货品配置' : '修改货品配置'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (existing == null)
                    OutlinedButton.icon(
                      onPressed: recognizing
                          ? null
                          : () async {
                              try {
                                final files = await _picker.pickMultiImage(imageQuality: 90);
                                if (files.isEmpty) return;
                                setDialogState(() => recognizing = true);
                                final data = await OcrService.recognizeLabelPaths(
                                    files.take(3).map((e) => e.path).toList());
                                if (data.materialCode.isNotEmpty) {
                                  codeController.text = data.materialCode;
                                }
                                if (data.description.isNotEmpty) {
                                  descController.text = data.description;
                                }
                                if (data.lpn.isNotEmpty) lpnController.text = data.lpn;
                                if (data.perBox > 0) {
                                  perBoxController.text = '${data.perBox}';
                                }
                                if (data.supplier.isNotEmpty &&
                                    _suppliers.any((e) => e.code == data.supplier)) {
                                  selectedSupplier = data.supplier;
                                }
                                setDialogState(() {});
                              } catch (e) {
                                setDialogState(() => error = '图片识别失败：$e');
                              } finally {
                                setDialogState(() => recognizing = false);
                              }
                            },
                      icon: const Icon(Icons.document_scanner_outlined, size: 18),
                      label: Text(recognizing ? '识别中...' : '箱贴识别填充（可选，不保存图片）'),
                    ),
                  if (existing == null) const SizedBox(height: 8),
                  if (existing == null)
                    const Text('仅用于自动填报字段；货品照片在下方单独上传（最多3张）',
                        style: TextStyle(fontSize: 10, color: Color(0xFF98A2B3))),
                  if (existing == null) const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: selectedSupplier.isEmpty ? null : selectedSupplier,
                    decoration: const InputDecoration(labelText: '供应商'),
                    items: _suppliers
                        .map((s) => DropdownMenuItem(
                              value: s.code,
                              child: Text('${s.code} ${s.name}'),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setDialogState(() => selectedSupplier = value);
                    },
                  ),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 9,
                    decoration: const InputDecoration(labelText: '物料代码（9位数字）'),
                  ),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(labelText: '物料描述（可选）'),
                  ),
                  TextField(
                    controller: lpnController,
                    decoration: const InputDecoration(labelText: 'LPN（可选）'),
                  ),
                  TextField(
                    controller: perBoxController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '每箱数量'),
                  ),
                  const SizedBox(height: 12),
                  const Text('货品图片（最多3张）',
                      style: TextStyle(fontSize: 12, color: AppColors.sub)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < images.length; i++)
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            GestureDetector(
                              onTap: () => _previewImage(images[i]),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(images[i]),
                                  width: 62,
                                  height: 62,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const SizedBox(
                                    width: 62,
                                    height: 62,
                                    child: ColoredBox(color: Color(0xFFF2F4F8)),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              right: -6,
                              top: -6,
                              child: GestureDetector(
                                onTap: () => setDialogState(() => images.removeAt(i)),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                      color: Color(0xCC000000), shape: BoxShape.circle),
                                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                            Positioned(
                              left: -6,
                              bottom: -6,
                              child: GestureDetector(
                                onTap: () async {
                                  final result = await Navigator.push<String>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ImageAnnotatorScreen(path: images[i]),
                                    ),
                                  );
                                  if (result != null) {
                                    setDialogState(() => images[i] = result);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle),
                                  child: const Icon(Icons.brush,
                                      size: 13, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      if (images.length < 3)
                        OutlinedButton(
                          onPressed: () async {
                            try {
                              final source = await showModalBottomSheet<ImageSource>(
                                context: context,
                                builder: (context) => SafeArea(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ListTile(
                                        leading: const Icon(Icons.photo_camera_outlined),
                                        title: const Text('拍摄货品照片'),
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
                              );
                              if (source == null) return;
                              final files = <XFile>[];
                              if (source == ImageSource.camera) {
                                final file =
                                    await _picker.pickImage(source: source, imageQuality: 90);
                                if (file != null) files.add(file);
                              } else {
                                files.addAll(await _picker.pickMultiImage(imageQuality: 90));
                              }
                              for (final file in files) {
                                if (images.length >= 3) break;
                                final saved = await _saveCatalogImage(file.path);
                                images.add(saved);
                              }
                              setDialogState(() {});
                            } catch (e) {
                              setDialogState(() => error = '图片上传失败：$e');
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(62, 62),
                            padding: EdgeInsets.zero,
                          ),
                          child: const Text('+ 图片', style: TextStyle(fontSize: 11)),
                        ),
                    ],
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 6),
                    Text(error!, style: const TextStyle(fontSize: 11, color: AppColors.red)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final supplier = selectedSupplier;
                final code = codeController.text.trim();
                final perBox = int.tryParse(perBoxController.text.trim()) ?? 0;
                if (supplier.isEmpty) {
                  setDialogState(() => error = '请选择供应商');
                  return;
                }
                if (!RegExp(r'^\d{9}$').hasMatch(code)) {
                  setDialogState(() => error = '物料代码需为 9 位数字');
                  return;
                }
                if (perBox <= 0) {
                  setDialogState(() => error = '每箱数量需为正整数');
                  return;
                }
                if (existing == null) {
                  final duplicate = _items.any(
                      (e) => e.supplier == supplier && e.materialCode == code);
                  if (duplicate) {
                    setDialogState(() => error = '该供应商 + 物料代码已存在，请直接编辑');
                    await showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('货品已存在'),
                        content: Text('供应商 $supplier 下的物料 $code 已存在，请直接在列表中编辑。'),
                        actions: [
                          FilledButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('知道了'),
                          ),
                        ],
                      ),
                    );
                    return;
                  }
                }
                final updated = CatalogItem(
                  materialCode: code,
                  description: descController.text.trim(),
                  lpn: lpnController.text.trim(),
                  supplier: supplier,
                  perBox: perBox,
                  images: List<String>.from(images),
                );
                final list = List<CatalogItem>.from(_items);
                if (existing != null) {
                  final index = list.indexWhere((e) =>
                      e.supplier == existing.supplier && e.materialCode == existing.materialCode);
                  if (index >= 0) {
                    list[index] = updated;
                  } else {
                    list.add(updated);
                  }
                } else {
                  list.add(updated);
                }
                await AppRepository.saveCatalog(list);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                await _load();
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSupplierManager() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Expanded(child: Text('供应商管理')),
              TextButton(
                onPressed: () async {
                  final added = await _supplierForm();
                  if (added) {
                    setDialogState(() {});
                    setState(() {});
                  }
                },
                child: const Text('新增'),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 360,
            child: _suppliers.isEmpty
                ? const EmptyHint(title: '暂无供应商')
                : ListView.separated(
                    itemCount: _suppliers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final supplier = _suppliers[index];
                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(supplier.code,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold, fontSize: 15)),
                                  Text(supplier.name,
                                      style: const TextStyle(
                                          fontSize: 12, color: AppColors.sub)),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                final edited = await _supplierForm(existing: supplier);
                                if (edited) {
                                  setDialogState(() {});
                                  setState(() {});
                                }
                              },
                              child: const Text('编辑'),
                            ),
                            TextButton(
                              onPressed: () async {
                                final confirmed = await _confirm(
                                    '删除供应商',
                                    '确认删除 ${supplier.code} ${supplier.name}？货品仍保留供应商编码。');
                                if (confirmed == true) {
                                  _suppliers.removeAt(index);
                                  await AppRepository.saveSuppliers(_suppliers);
                                  setDialogState(() {});
                                  setState(() {});
                                }
                              },
                              child: const Text('删除',
                                  style: TextStyle(color: AppColors.red)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _supplierForm({SupplierInfo? existing}) async {
    final codeController = TextEditingController(text: existing?.code ?? '');
    final nameController = TextEditingController(text: existing?.name ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? '添加供应商' : '编辑供应商'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeController,
              enabled: existing == null,
              keyboardType: TextInputType.number,
              maxLength: 5,
              decoration: const InputDecoration(labelText: '供应商编码（5位数字）'),
            ),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '供应商名称'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final code = codeController.text.trim();
              final name = nameController.text.trim();
              if (!RegExp(r'^\d{5}$').hasMatch(code) || name.isEmpty) return;
              if (existing == null && _suppliers.any((e) => e.code == code)) {
                if (context.mounted) {
                  await showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('供应商已存在'),
                      content: Text('供应商编码 $code 已存在，请直接编辑。'),
                      actions: [
                        FilledButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('知道了'),
                        ),
                      ],
                    ),
                  );
                }
                return;
              }
              if (existing == null) {
                _suppliers.add(SupplierInfo(code, name));
              } else {
                existing.name = name;
              }
              await AppRepository.saveSuppliers(_suppliers);
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<bool?> _confirm(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteGoods(CatalogItem item) async {
    final confirmed = await _confirm('删除货品', '确认删除 ${item.materialCode} ${item.description}？');
    if (confirmed != true) return;
    _items.removeWhere(
        (e) => e.supplier == item.supplier && e.materialCode == item.materialCode);
    await AppRepository.saveCatalog(_items);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: AppColors.soft,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('货品配置',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        Text('货品 / 供应商 / 箱贴识别',
                            style: TextStyle(fontSize: 11, color: Color(0xFF7A8699))),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _openSupplierManager,
                    child: const Text('供应商'),
                  ),
                  FilledButton(
                    onPressed: () => _openGoodsDialog(),
                    child: const Text('新增货品'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: SectionCard(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchSupplier,
                            decoration: const InputDecoration(
                              hintText: '供应商编码/名称',
                              isDense: true,
                              filled: true,
                              fillColor: Color(0xFFF4F7FD),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.all(Radius.circular(10)),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 112,
                          child: DropdownButtonFormField<String>(
                            initialValue: null,
                            hint: const Text('选择供应商', style: TextStyle(fontSize: 11)),
                            isExpanded: true,
                            decoration: const InputDecoration(
                              isDense: true,
                              filled: true,
                              fillColor: Color(0xFFEEF4FF),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.all(Radius.circular(10)),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            items: _suppliers
                                .map((s) => DropdownMenuItem(
                                      value: s.code,
                                      child: Text('${s.code} ${s.name}',
                                          style: const TextStyle(fontSize: 11)),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                _searchSupplier.text = value;
                                setState(() {});
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchCode,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: '物料代码后4位',
                              isDense: true,
                              filled: true,
                              fillColor: Color(0xFFF4F7FD),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.all(Radius.circular(10)),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            _searchSupplier.clear();
                            _searchCode.clear();
                            setState(() {});
                          },
                          child: const Text('清除'),
                        ),
                        Text('筛选 ${filtered.length} 条',
                            style: const TextStyle(fontSize: 10, color: AppColors.primary)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const EmptyHint(title: '暂无货品配置', subtitle: '点击右上角新增货品')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CodeText(item.materialCode, fontSize: 16),
                                  const Spacer(),
                                  Text('每箱 ${item.perBox} 个',
                                      style: const TextStyle(
                                          fontSize: 11, color: AppColors.primary)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(item.description.isEmpty ? '未填写描述' : item.description,
                                  style: const TextStyle(
                                      fontSize: 12, color: AppColors.sub)),
                              if (item.images.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: item.images
                                      .map((path) => GestureDetector(
                                            onTap: () => _previewImage(path),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(6),
                                              child: Image.file(
                                                File(path),
                                                width: 42,
                                                height: 42,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => const SizedBox(
                                                  width: 42,
                                                  height: 42,
                                                  child: ColoredBox(
                                                      color: Color(0xFFF2F4F8)),
                                                ),
                                              ),
                                            ),
                                          ))
                                      .toList(),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Text('供应商 ${item.supplier}',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.orange)),
                                  if (_supplierName(item.supplier).isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Text(_supplierName(item.supplier),
                                        style: const TextStyle(
                                            fontSize: 11, color: Color(0xFF98A2B3))),
                                  ],
                                  const Spacer(),
                                  Text(item.lpn,
                                      style: const TextStyle(
                                          fontSize: 10, color: Color(0xFF98A2B3))),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    tooltip: '装箱计算',
                                    onPressed: () => _openBoxCalculator(item),
                                    icon: const Icon(Icons.calculate_outlined,
                                        size: 20, color: AppColors.primary),
                                  ),
                                  TextButton(
                                    onPressed: () => _openGoodsDialog(existing: item),
                                    child: const Text('编辑'),
                                  ),
                                  TextButton(
                                    onPressed: () => _deleteGoods(item),
                                    child: const Text('删除',
                                        style: TextStyle(color: AppColors.red)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
