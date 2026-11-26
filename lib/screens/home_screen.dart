import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../calculator.dart';
import '../models.dart';
import '../ocr_service.dart';
import '../repository.dart';
import '../widgets.dart';
import 'catalog_screen.dart';
import 'calculator_screen.dart';
import 'inventory_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _picker = ImagePicker();
  final List<String> _imagePaths = [];
  List<PickingItem> _items = [];
  List<HistoryRecord> _history = [];
  List<CatalogItem> _catalog = [];
  String _serverUrl = AppRepository.defaultServerUrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final catalog = await AppRepository.loadCatalog();
    final history = await AppRepository.loadHistory();
    final serverUrl = await AppRepository.loadServerUrl();
    if (!mounted) return;
    setState(() {
      _catalog = catalog;
      _history = history;
      _serverUrl = serverUrl;
      _applyCatalog();
    });
  }

  void _applyCatalog() {
    _items = _items.map((item) {
      CatalogItem? found;
      for (final c in _catalog) {
        if (c.supplier == item.supplier && c.materialCode == item.materialCode) {
          found = c;
          break;
        }
      }
      return item.copyWith(
        perBox: found?.perBox ?? 0,
        configured: found != null,
        description: item.description.isEmpty ? (found?.description ?? '') : item.description,
      );
    }).toList();
  }

  Future<void> _chooseImages() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍摄清单'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择（最多9张）'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      if (source == ImageSource.camera) {
        final file = await _picker.pickImage(source: source, imageQuality: 92);
        if (file != null && _imagePaths.length < 9) {
          setState(() => _imagePaths.add(file.path));
        }
      } else {
        final files = await _picker.pickMultiImage(imageQuality: 92);
        if (files.isNotEmpty) {
          setState(() {
            for (final file in files) {
              if (_imagePaths.length >= 9) break;
              _imagePaths.add(file.path);
            }
          });
        }
      }
    } catch (e) {
      if (mounted) showMessage(context, '选择图片失败：$e');
    }
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
                  errorBuilder: (_, __, ___) => const Text(
                    '图片无法加载',
                    style: TextStyle(color: Colors.white),
                  ),
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

  bool _incomplete(List<PickingItem> items) {
    if (items.isEmpty) return true;
    return items.any((e) =>
        e.quantity <= 0 ||
        !RegExp(r'^\d{5}$').hasMatch(e.supplier) ||
        e.materialCode.length != 9);
  }

  Future<void> _recognizeLocal() async {
    if (_imagePaths.isEmpty) {
      showMessage(context, '请先拍摄或上传清单图片');
      return;
    }
    setState(() => _busy = true);
    try {
      final items = await OcrService.recognizeLocalPicking(_imagePaths);
      if (!mounted) return;
      setState(() {
        _items = items;
        _applyCatalog();
      });
      if (OcrService.lastLocalFailures > 0) {
        showMessage(context, '${OcrService.lastLocalFailures} 张本地识别失败，已保留成功结果');
      }
      if (_incomplete(items)) {
        final useServer = await _askServer();
        if (!mounted) return;
        if (useServer == true) {
          setState(() => _busy = true);
          await _recognizeServer(saveAndMerge: true);
          return;
        }
      }
      await _finishRecognition(items);
    } catch (e) {
      if (!mounted) return;
      final useServer = await _askServer(error: '$e');
      if (useServer == true) {
        await _recognizeServer(saveAndMerge: true);
      } else {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _recognizeServer({bool saveAndMerge = false}) async {
    if (_imagePaths.isEmpty) {
      setState(() => _busy = false);
      showMessage(context, '请先拍摄或上传清单图片');
      return;
    }
    setState(() => _busy = true);
    try {
      final items = await OcrService.recognizeServerPicking(_imagePaths, _serverUrl);
      if (!mounted) return;
      setState(() {
        _items = items;
        _applyCatalog();
      });
      if (OcrService.lastServerFailures > 0) {
        showMessage(context, '${OcrService.lastServerFailures} 张服务端识别失败，已保留成功结果');
      }
      if (saveAndMerge) {
        await _finishRecognition(items);
      } else {
        setState(() => _busy = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showMessage(context, '服务端识别失败：$e');
    }
  }

  Future<void> _finishRecognition(List<PickingItem> raw) async {
    var merged = await _promptMerges(raw);
    if (!mounted) return;
    setState(() {
      _items = merged;
      _applyCatalog();
      _busy = false;
    });
    try {
      final record = await AppRepository.createHistory(
        sourceImages: _imagePaths,
        items: raw,
        mergedItems: merged,
      );
      _history = [record, ..._history];
      await AppRepository.saveHistory(_history);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<List<PickingItem>> _promptMerges(List<PickingItem> items) async {
    final groups = <String, List<PickingItem>>{};
    for (final item in items) {
      if (item.supplier.isEmpty) continue;
      final key = '${item.supplier}|${item.materialCode}';
      groups.putIfAbsent(key, () => []).add(item);
    }
    final duplicateGroups = groups.values.where((e) => e.length > 1).toList();
    var current = List<PickingItem>.from(items);
    for (var i = 0; i < duplicateGroups.length; i++) {
      final group = duplicateGroups[i];
      if (!mounted) break;
      final merge = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('重复货品合并（${i + 1}/${duplicateGroups.length}）'),
          content: Text('同一供应商 + 物料代码出现 ${group.length} 次，是否合并分配数量？\n'
              '${group.first.supplier} · ${group.first.materialCode}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('不合并本组')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('合并本组')),
          ],
        ),
      );
      if (merge == true) {
        current = _mergeGroup(current, group);
      }
    }
    return current;
  }

  List<PickingItem> _mergeGroup(List<PickingItem> items, List<PickingItem> group) {
    final first = group.first;
    final total = group.fold<int>(0, (sum, e) => sum + e.quantity);
    final parts = group.map((e) => e.quantity).toList();
    final merged = first.copyWith(
      quantity: total,
      lpn: group.map((e) => e.lpn).where((e) => e.isNotEmpty).join(' / '),
      mergeParts: parts,
    );
    final result = <PickingItem>[];
    var inserted = false;
    for (final item in items) {
      final match = item.supplier == first.supplier && item.materialCode == first.materialCode;
      if (match) {
        if (!inserted) {
          result.add(merged);
          inserted = true;
        }
      } else {
        result.add(item);
      }
    }
    return result;
  }

  Future<bool?> _askServer({String? error}) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('本地识别数据不完整'),
        content: Text(error == null
            ? '有数据缺少数量、供应商或物料代码，是否使用更精准的服务端识别？'
            : '本地识别失败：$error\n是否使用服务端识别？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('使用本地数据')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('使用服务端')),
        ],
      ),
    );
  }

  Future<void> _openData() async {
    if (_items.isEmpty) return;
    final lines = _aggregateData();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('识别数据'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('格式：供应商-物料代码后4位-数量',
                  style: TextStyle(fontSize: 12, color: AppColors.sub)),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  child: SelectableText(
                    lines.map((e) => '${e.supplier}-${e.suffix}-${e.quantity}').join('\n'),
                    style: const TextStyle(fontSize: 16, height: 1.7),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(
                text: lines.map((e) => '${e.suffix}-${e.quantity}').join('\n'),
              ));
              if (context.mounted) {
                showMessage(context, '已复制到剪贴板');
                Navigator.pop(context);
              }
            },
            child: const Text('复制'),
          ),
        ],
      ),
    );
  }

  List<_AggregatedLine> _aggregateData() {
    final map = <String, _AggregatedLine>{};
    final order = <String>[];
    for (final item in _items) {
      final supplier = item.supplier.isEmpty ? '未知' : item.supplier;
      final key = '$supplier|${item.materialCode}';
      if (!map.containsKey(key)) {
        map[key] = _AggregatedLine(supplier, item.codeSuffix, 0);
        order.add(key);
      }
      map[key]!.quantity += item.quantity;
    }
    return order.map((e) => map[e]!).toList();
  }

  Future<void> _editQuantity(PickingItem item) async {
    final controller = TextEditingController(text: '${item.quantity}');
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('分配数量'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '输入分配数量'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value != null && value > 0) {
      setState(() {
        item.quantity = value;
        _items = List.of(_items);
      });
    }
  }

  Future<void> _editPerBox(PickingItem item) async {
    final controller = TextEditingController(text: item.perBox > 0 ? '${item.perBox}' : '');
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('每箱数量'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '例如 100'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value == null || value <= 0) return;
    final existingIndex = _catalog.indexWhere(
        (e) => e.supplier == item.supplier && e.materialCode == item.materialCode);
    if (existingIndex >= 0) {
      _catalog[existingIndex].perBox = value;
    } else {
      _catalog.add(CatalogItem(
        materialCode: item.materialCode,
        description: item.description,
        lpn: item.lpn,
        supplier: item.supplier,
        perBox: value,
      ));
    }
    await AppRepository.saveCatalog(_catalog);
    setState(() {
      item.perBox = value;
      item.configured = true;
      _items = List.of(_items);
    });
  }

  Future<void> _allocate(PickingItem item) async {
    if (item.perBox <= 0) {
      await _editPerBox(item);
      if (item.perBox <= 0) return;
    }
    final outcome = BoxCalculator.calculate('${item.quantity}', '${item.perBox}');
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('装箱结果', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${outcome.boxes}',
                    style: const TextStyle(
                        fontSize: 40, fontWeight: FontWeight.bold, color: AppColors.primary)),
                const SizedBox(width: 6),
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('箱', style: TextStyle(fontSize: 14, color: AppColors.sub)),
                ),
                const SizedBox(width: 16),
                Text('+ ${outcome.remainder}',
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.orange)),
                const SizedBox(width: 4),
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text('个', style: TextStyle(fontSize: 14, color: AppColors.sub)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('总数 ${outcome.total} 个，每箱 ${outcome.perBox} 个',
                style: const TextStyle(fontSize: 12, color: AppColors.sub)),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF4FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_allocationAdvice(outcome),
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  String _allocationAdvice(BoxOutcome outcome) {
    if (outcome.remainder == 0) {
      return '正好 ${outcome.boxes} 箱，无需调整';
    }
    if (outcome.remainder <= outcome.perBox / 2) {
      return '建议拿 ${outcome.boxes} 箱，剩余 ${outcome.remainder} 个';
    }
    return '建议拿 ${outcome.boxes + 1} 箱，去掉 ${outcome.perBox - outcome.remainder} 个';
  }

  Future<void> _openHistory() async {
    var page = 0;
    const pageSize = 10;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Expanded(child: Text('识别历史')),
              TextButton(
                onPressed: () async {
                  await AppRepository.clearHistory(_history);
                  setDialogState(() {});
                  setState(() {});
                },
                child: const Text('清空', style: TextStyle(color: AppColors.red)),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 430,
            child: _history.isEmpty
                ? const EmptyHint(title: '暂无识别历史', subtitle: '每次识别会自动保存，保留 7 天')
                : Builder(builder: (context) {
                    final totalPages = (_history.length + pageSize - 1) ~/ pageSize;
                    if (page >= totalPages) page = totalPages - 1;
                    if (page < 0) page = 0;
                    final pageRecords =
                        _history.skip(page * pageSize).take(pageSize).toList();
                    return Column(
                      children: [
                        Expanded(
                          child: ListView.separated(
                            itemCount: pageRecords.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final record = pageRecords[index];
                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    _items = List.of(record.mergedItems.isNotEmpty
                                        ? record.mergedItems
                                        : record.items);
                                    _imagePaths
                                      ..clear()
                                      ..addAll(record.imagePaths);
                                    _applyCatalog();
                                  });
                                  Navigator.pop(context);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.card,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      if (record.imagePaths.isNotEmpty)
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.file(
                                            File(record.imagePaths.first),
                                            width: 54,
                                            height: 54,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => const SizedBox(
                                              width: 54,
                                              height: 54,
                                              child: ColoredBox(color: Color(0xFFF2F4F8)),
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(_formatTime(record.createdAt),
                                                style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600)),
                                            const SizedBox(height: 4),
                                            Text(
                                                '${record.displayLines} 行 · 合计 ${record.displayTotal} 个',
                                                style: const TextStyle(
                                                    fontSize: 11, color: AppColors.sub)),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () async {
                                          await AppRepository.deleteHistory(_history, record);
                                          if (page >= (_history.length + pageSize - 1) ~/ pageSize) {
                                            page = ((_history.length + pageSize - 1) ~/ pageSize) - 1;
                                          }
                                          if (page < 0) page = 0;
                                          setDialogState(() {});
                                          setState(() {});
                                        },
                                        icon: const Icon(Icons.delete_outline,
                                            size: 19, color: AppColors.red),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: page > 0
                                  ? () => setDialogState(() => page--)
                                  : null,
                              child: const Text('上一页'),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text('第 ${page + 1}/$totalPages 页',
                                  style: const TextStyle(fontSize: 12, color: AppColors.sub)),
                            ),
                            TextButton(
                              onPressed: page < totalPages - 1
                                  ? () => setDialogState(() => page++)
                                  : null,
                              child: const Text('下一页'),
                            ),
                          ],
                        ),
                      ],
                    );
                  }),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
          ],
        ),
      ),
    );
  }

  Future<void> _openServerSettings() async {
    final controller = TextEditingController(text: _serverUrl);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('识别服务设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('填写完整 /ocr 地址；本地 USB 用 http://127.0.0.1:8000/ocr，外网用 HTTPS 域名',
                style: TextStyle(fontSize: 12, color: AppColors.sub)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: 'https://example.com/ocr'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value != null && value.trim().isNotEmpty) {
      final normalized = AppRepository.normalizeServerUrl(value);
      await AppRepository.saveServerUrl(normalized);
      if (mounted) setState(() => _serverUrl = normalized);
    }
  }

  String _formatTime(DateTime date) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.soft,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEDF4FF), Color(0xFFF9FBFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFDCE8FB)),
                ),
                child: _header(),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                child: Column(
                  children: [
                    SectionCard(child: _imageSection()),
                    const SizedBox(height: 12),
                    SectionCard(child: _resultSection()),
                    const SizedBox(height: 12),
                    _footer(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('配货清单',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              SizedBox(height: 1),
              Text('拍照识别 · 自动配货',
                  style: TextStyle(fontSize: 10, color: Color(0xFF8B96A8))),
            ],
          ),
        ),
        _circleIcon(Icons.history, () => _openHistory(), badge: _history.length),
        const SizedBox(width: 5),
        _circleIcon(Icons.calculate_outlined, () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const CalculatorScreen()));
        }),
        const SizedBox(width: 5),
        _circleIcon(Icons.grid_view_rounded, () async {
          await Navigator.push(
              context, MaterialPageRoute(builder: (_) => const CatalogScreen()));
          await _load();
        }),
        const SizedBox(width: 5),
        _circleIcon(Icons.inventory_2_outlined, () async {
          await Navigator.push(
              context, MaterialPageRoute(builder: (_) => const InventoryScreen()));
        }),
      ],
    );
  }

  Widget _circleIcon(IconData icon, VoidCallback onTap, {int badge = 0}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.white,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(icon, size: 19, color: const Color(0xFF344054)),
            ),
          ),
        ),
        if (badge > 0)
          Positioned(
            right: -2,
            top: -3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: AppColors.orange,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$badge',
                  style: const TextStyle(fontSize: 9, color: Colors.white)),
            ),
          ),
      ],
    );
  }

  Widget _imageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF4FF),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.document_scanner_outlined,
                  size: 17, color: AppColors.primary),
            ),
            const SizedBox(width: 8),
            const Text('清单图片',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${_imagePaths.length}/9 张',
                style: const TextStyle(fontSize: 11, color: Color(0xFF98A2B3))),
          ],
        ),
        const SizedBox(height: 12),
        if (_imagePaths.isEmpty)
          Container(
            width: double.infinity,
            height: 80,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('拍摄或上传清单图片\n可多张，一次识别',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.sub, height: 1.6)),
          )
        else
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _imagePaths.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) => Stack(
                children: [
                  GestureDetector(
                    onTap: () => _previewImage(_imagePaths[index]),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(File(_imagePaths[index]),
                          width: 76, height: 76, fit: BoxFit.cover),
                    ),
                  ),
                  Positioned(
                    right: 2,
                    top: 2,
                    child: GestureDetector(
                      onTap: () => setState(() => _imagePaths.removeAt(index)),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                            color: Color(0xCC000000), shape: BoxShape.circle),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _chooseImages,
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('拍摄/上传'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : _recognizeLocal,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(_busy ? '识别中...' : '开始识别',
                    style: const TextStyle(fontSize: 15)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _busy ? null : () => _recognizeServer(),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(40),
              side: BorderSide.none,
              backgroundColor: const Color(0xFFEEF4FF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('服务端识别（高精度）',
                style: TextStyle(fontSize: 12, color: AppColors.primary)),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _items.isEmpty ? '拍摄或上传清单图片后点击“开始识别”' : '识别完成：共 ${_items.length} 行',
          style: const TextStyle(fontSize: 11, color: Color(0xFF98A2B3)),
        ),
      ],
    );
  }

  Widget _resultSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E8),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.playlist_add_check_circle_outlined,
                  size: 17, color: AppColors.orange),
            ),
            const SizedBox(width: 8),
            const Text('识别结果',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            if (_items.isNotEmpty)
              TextButton(
                onPressed: _openData,
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFEEF4FF),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 30),
                ),
                child: const Text('查看数据', style: TextStyle(fontSize: 11)),
              ),
            const SizedBox(width: 6),
            Text('${_items.length} 行',
                style: const TextStyle(fontSize: 11, color: Color(0xFF98A2B3))),
          ],
        ),
        const SizedBox(height: 10),
        if (_items.isEmpty)
          const EmptyHint(title: '暂无识别结果', subtitle: '拍摄或上传清单图片后，点击“开始识别”')
        else
          ..._items.map(_itemCard),
      ],
    );
  }

  Widget _itemCard(PickingItem item) {
    return Opacity(
      opacity: item.completed ? 0.62 : 1,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: item.completed ? const Color(0xFFECEFF3) : AppColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CodeText(item.materialCode),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFFF4E8),
                      borderRadius: BorderRadius.circular(6)),
                  child: Row(
                    children: [
                      const Text('供应商',
                          style: TextStyle(fontSize: 9, color: Color(0xFF98A2B3))),
                      const SizedBox(width: 3),
                      Text(item.supplier.isEmpty ? '未知' : item.supplier,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: item.supplier.isEmpty
                                  ? const Color(0xFF98A2B3)
                                  : AppColors.orange)),
                    ],
                  ),
                ),
                const Spacer(),
                Expanded(
                  child: Text(item.lpn,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: Color(0xFF7A8699))),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: Text(item.description.isEmpty ? '未识别到物料描述' : item.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.sub)),
                ),
                if (item.source.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: item.source == '服务端'
                          ? const Color(0xFFE7F8F0)
                          : const Color(0xFFEEF4FF),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(item.source,
                        style: TextStyle(
                            fontSize: 9,
                            color: item.source == '服务端'
                                ? AppColors.green
                                : AppColors.primary)),
                  ),
              ],
            ),
            if (item.mergeParts.length > 1) ...[
              const SizedBox(height: 4),
              Text('合并：${item.mergeParts.join('+')} = ${item.quantity}',
                  style: const TextStyle(fontSize: 10, color: Color(0xFFC4320A))),
            ],
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                InkWell(
                  onTap: () => _editQuantity(item),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('分配数量',
                          style: TextStyle(fontSize: 10, color: Color(0xFF98A2B3))),
                      Text(item.quantity > 0 ? '${item.quantity}' : '未识别',
                          style: TextStyle(
                              fontSize: item.quantity > 0 ? 25 : 14,
                              fontWeight: FontWeight.bold,
                              color: item.quantity > 0 ? AppColors.primary : AppColors.red)),
                    ],
                  ),
                ),
                const SizedBox(width: 26),
                InkWell(
                  onTap: () => _editPerBox(item),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('每箱数量',
                          style: TextStyle(fontSize: 10, color: Color(0xFF98A2B3))),
                      Text(item.configured ? '${item.perBox} 个' : '未配置',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: item.configured ? const Color(0xFF344054) : AppColors.red)),
                    ],
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => item.completed = !item.completed),
                  style: TextButton.styleFrom(
                    backgroundColor:
                        item.completed ? const Color(0xFFE5E7EB) : const Color(0xFFE7F8F0),
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: Text(item.completed ? '已完成' : '完成',
                      style: TextStyle(
                          fontSize: 12,
                          color: item.completed ? const Color(0xFF98A2B3) : AppColors.green)),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: item.configured ? () => _allocate(item) : () => _editPerBox(item),
                  style: FilledButton.styleFrom(
                    backgroundColor: item.configured ? AppColors.primary : const Color(0xFFB6C2D9),
                    minimumSize: const Size(64, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('分配', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    return Column(
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('服务端识别 / 本地识别可切换',
                  style: TextStyle(fontSize: 10, color: Color(0xFF98A2B3))),
            ),
            TextButton(
              onPressed: _openServerSettings,
              child: const Text('服务设置', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }
}

class _AggregatedLine {
  final String supplier;
  final String suffix;
  int quantity;
  _AggregatedLine(this.supplier, this.suffix, this.quantity);
}
