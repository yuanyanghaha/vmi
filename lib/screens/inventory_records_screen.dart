import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../calculator.dart';
import '../models.dart';
import '../repository.dart';
import '../supplier_matcher.dart';
import '../widgets.dart';
import '../xlsx_export.dart';
import 'inventory_form_dialog.dart';

class InventoryRecordsScreen extends StatefulWidget {
  const InventoryRecordsScreen({super.key});

  @override
  State<InventoryRecordsScreen> createState() => _InventoryRecordsScreenState();
}

class _InventoryRecordsScreenState extends State<InventoryRecordsScreen> {
  static const _shareChannel = MethodChannel('goods_flutter/share');
  List<InventoryRecord> _records = [];
  List<SupplierInfo> _suppliers = [];
  final _codeSearch = TextEditingController();
  DateTimeRange? _range;
  String? _supplierCode;
  int _page = 0;
  bool _busy = false;
  static const _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeSearch.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final records = await AppRepository.loadInventory();
    final suppliers = await AppRepository.loadSuppliers();
    if (!mounted) return;
    setState(() {
      _records = records;
      _suppliers = suppliers;
    });
  }

  List<InventoryRecord> get _filtered {
    return _records.where((record) {
      if (_range != null) {
        final day = DateTime(record.createdAt.year, record.createdAt.month,
            record.createdAt.day);
        final start = DateTime(_range!.start.year, _range!.start.month,
            _range!.start.day);
        final end =
            DateTime(_range!.end.year, _range!.end.month, _range!.end.day);
        if (day.isBefore(start) || day.isAfter(end)) return false;
      }
      if (_supplierCode != null &&
          SupplierMatcher.codeFor(record.manufacturer, _suppliers) !=
              _supplierCode) {
        return false;
      }
      final code = _codeSearch.text.trim();
      if (code.isNotEmpty && !record.materialCode.endsWith(code)) {
        return false;
      }
      return true;
    }).toList();
  }

  int get _pageCount {
    final count = (_filtered.length + _pageSize - 1) ~/ _pageSize;
    return count < 1 ? 1 : count;
  }

  List<InventoryRecord> get _paged {
    final filtered = _filtered;
    final start = _page * _pageSize;
    if (start >= filtered.length) return <InventoryRecord>[];
    return filtered.sublist(
        start, (start + _pageSize).clamp(0, filtered.length));
  }

  String _supplierLabel(InventoryRecord record) {
    final supplier = SupplierMatcher.match(record.manufacturer, _suppliers);
    if (supplier != null) return '${supplier.code} ${supplier.name}';
    return record.manufacturer.isEmpty ? '未匹配供应商' : record.manufacturer;
  }

  String _dateText(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035, 12, 31),
      initialDateRange: _range,
      helpText: '选择录入时间范围',
      saveText: '确定',
    );
    if (range == null) return;
    setState(() {
      _range = range;
      _page = 0;
    });
  }

  Future<void> _edit(InventoryRecord record) async {
    final updated = await showDialog<InventoryRecord>(
      context: context,
      builder: (context) =>
          _EditInventoryDialog(record: record, suppliers: _suppliers),
    );
    if (updated == null) return;
    final list = await AppRepository.loadInventory();
    for (var i = 0; i < list.length; i++) {
      if (list[i].id == updated.id) {
        list[i] = updated;
        break;
      }
    }
    await AppRepository.saveInventory(list);
    setState(() {
      _records = list;
      if (_page >= _pageCount) _page = _pageCount - 1;
      if (_page < 0) _page = 0;
    });
    final added = await _syncMissingToCatalog(only: updated);
    if (mounted) {
      showMessage(context,
          added > 0 ? '已更新，并同步到货品配置' : '库存记录已更新');
    }
  }

  Future<void> _delete(InventoryRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除库存记录'),
        content: Text('确认删除 ${record.materialCode} 这条记录？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final list = await AppRepository.loadInventory();
    list.removeWhere((e) => e.id == record.id);
    await AppRepository.saveInventory(list);
    setState(() {
      _records = list;
      if (_page >= _pageCount) _page = _pageCount - 1;
      if (_page < 0) _page = 0;
    });
  }

  Future<int> _syncMissingToCatalog({InventoryRecord? only}) async {
    final catalog = await AppRepository.loadCatalog();
    final existing = <String>{
      for (final item in catalog) '${item.supplier}|${item.materialCode}',
    };
    final source = only == null ? _records : <InventoryRecord>[only];
    var added = 0;
    for (final record in source) {
      final supplier = SupplierMatcher.match(record.manufacturer, _suppliers);
      if (supplier == null) continue;
      final key = '${supplier.code}|${record.materialCode}';
      if (existing.contains(key)) continue;
      catalog.add(CatalogItem(
        materialCode: record.materialCode,
        description: record.description,
        lpn: record.batch,
        supplier: supplier.code,
        perBox: record.perBox,
        images: record.imagePath.isEmpty ? <String>[] : <String>[record.imagePath],
      ));
      existing.add(key);
      added++;
    }
    if (added > 0) await AppRepository.saveCatalog(catalog);
    return added;
  }

  Future<void> _syncAll() async {
    final added = await _syncMissingToCatalog();
    if (!mounted) return;
    showMessage(context,
        added > 0 ? '已同步 $added 个货品到货品配置' : '货品配置已是最新，无需同步');
  }

  Future<void> _addInventory() async {
    final created = await showDialog<InventoryRecord>(
      context: context,
      builder: (_) => InventoryFormDialog(suppliers: _suppliers),
    );
    if (created == null) return;
    final list = await AppRepository.loadInventory();
    list.insert(0, created);
    await AppRepository.saveInventory(list);
    final added = await _syncMissingToCatalog(only: created);
    if (!mounted) return;
    setState(() {
      _records = list;
      _page = 0;
    });
    showMessage(context,
        added > 0 ? '库存已保存，并同步到货品配置' : '库存记录已保存');
  }


  Future<void> _export() async {
    final exportRecords = _filtered;
    if (exportRecords.isEmpty) {
      showMessage(context, '暂无库存记录可导出');
      return;
    }
    setState(() => _busy = true);
    try {
      final codes = exportRecords
          .map((record) =>
              SupplierMatcher.codeFor(record.manufacturer, _suppliers))
          .toList();
      final bytes = InventoryXlsx.build(exportRecords, codes);
      final dir = await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      String two(int value) => value.toString().padLeft(2, '0');
      final name = '库存统计_${now.year}${two(now.month)}${two(now.day)}_'
          '${two(now.hour)}${two(now.minute)}${two(now.second)}.xlsx';
      final file = File(p.join(dir.path, name));
      await file.writeAsBytes(bytes);
      try {
        await _shareChannel
            .invokeMethod('shareFile', {'path': file.path, 'text': '库存统计'});
      } on MissingPluginException {
        if (mounted) showMessage(context, 'Excel 已导出：${file.path}');
      }
    } catch (e) {
      if (mounted) showMessage(context, '导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
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
                        Text('库存列表 · 同步货品配置',
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFF98A2B3))),
                      ],
                    ),
                  ),
                  _roundIcon(Icons.sync, _syncAll),
                  const SizedBox(width: 4),
                  _roundIcon(Icons.add, _addInventory),
                  const SizedBox(width: 4),
                  _roundIcon(Icons.file_download_outlined, _export),
                ],
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                    child: SectionCard(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _pickRange,
                                  icon: const Icon(Icons.date_range_outlined,
                                      size: 17),
                                  label: Text(
                                    _range == null
                                        ? '全部时间'
                                        : '${_dateText(_range!.start)} 至 ${_dateText(_range!.end)}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(38),
                                  ),
                                ),
                              ),
                              if (_range != null) ...[
                                const SizedBox(width: 6),
                                IconButton(
                                  tooltip: '清除日期',
                                  onPressed: () => setState(() {
                                    _range = null;
                                    _page = 0;
                                  }),
                                  icon: const Icon(Icons.close, size: 18),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                flex: 1,
                                child: DropdownButtonFormField<String>(
                                  // ignore: deprecated_member_use
                                  value: _supplierCode,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: '供应商',
                                    prefixIcon: Icon(
                                        Icons.storefront_outlined,
                                        size: 18),
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                  ),
                                  hint: const Text('全部供应商'),
                                  items: _suppliers
                                      .map((supplier) => DropdownMenuItem(
                                            value: supplier.code,
                                            child: Text(
                                                '${supplier.code}  ${supplier.name}',
                                                overflow:
                                                    TextOverflow.ellipsis),
                                          ))
                                      .toList(),
                                  onChanged: (value) => setState(() {
                                    _supplierCode = value;
                                    _page = 0;
                                  }),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 1,
                                child: TextField(
                                  controller: _codeSearch,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(4),
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: '代码后4位',
                                    prefixIcon:
                                        Icon(Icons.search, size: 18),
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 10),
                                    counterText: '',
                                  ),
                                  onChanged: (_) =>
                                      setState(() => _page = 0),
                                ),
                              ),
                              if (_range != null ||
                                  _supplierCode != null ||
                                  _codeSearch.text.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                TextButton(
                                  onPressed: () => setState(() {
                                    _range = null;
                                    _supplierCode = null;
                                    _codeSearch.clear();
                                    _page = 0;
                                  }),
                                  child: const Text('重置'),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text('共 ${_records.length} 条 · 筛选 ${filtered.length} 条',
                                  style: const TextStyle(
                                      fontSize: 10, color: Color(0xFF98A2B3))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? EmptyHint(
                            title: _records.isEmpty ? '暂无库存记录' : '没有符合条件的记录',
                            subtitle: _records.isEmpty
                                ? '返回上一页拍照识别并保存库存'
                                : '可调整时间范围或供应商',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            itemCount: _paged.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) =>
                                _recordCard(_paged[index]),
                          ),
                  ),
                  if (filtered.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed:
                                _page > 0 ? () => setState(() => _page--) : null,
                            child: const Text('上一页'),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            child: Text('第 ${_page + 1}/$_pageCount 页',
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.sub)),
                          ),
                          TextButton(
                            onPressed: _page < _pageCount - 1
                                ? () => setState(() => _page++)
                                : null,
                            child: const Text('下一页'),
                          ),
                        ],
                      ),
                    ),
                ],
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
        onTap: _busy ? null : onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 21, color: AppColors.text),
        ),
      ),
    );
  }

  Widget _recordCard(InventoryRecord record) {
    final supplier = SupplierMatcher.match(record.manufacturer, _suppliers);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDF1F7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CodeText(record.materialCode, fontSize: 17),
              const Spacer(),
              Text(_formatTime(record.createdAt),
                  style: const TextStyle(
                      fontSize: 10, color: Color(0xFF98A2B3))),
            ],
          ),
          const SizedBox(height: 4),
          Text(record.description.isEmpty ? '无描述' : record.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.sub)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _pill('系统 ${record.systemStock}', const Color(0xFFEEF4FF),
                  AppColors.primary),
              _pill('实际 ${record.actualStock}', const Color(0xFFECFDF3),
                  AppColors.green),
              _pill('包装 ${record.perBox}', const Color(0xFFFFFAEB),
                  const Color(0xFFB54708)),
              _pill(
                  '差异 ${record.actualStock - record.systemStock > 0 ? '+' : ''}'
                  '${record.actualStock - record.systemStock}',
                  record.actualStock == record.systemStock
                      ? const Color(0xFFF2F4F8)
                      : record.actualStock > record.systemStock
                          ? const Color(0xFFECFDF3)
                          : const Color(0xFFFFF1F2),
                  record.actualStock == record.systemStock
                      ? AppColors.sub
                      : record.actualStock > record.systemStock
                          ? AppColors.green
                          : AppColors.red),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.storefront_outlined,
                  size: 14, color: Color(0xFF98A2B3)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  supplier == null
                      ? _supplierLabel(record)
                      : '${supplier.code}  ${supplier.name}',
                  style: TextStyle(
                      fontSize: 11,
                      color: supplier == null
                          ? AppColors.red
                          : const Color(0xFF475467)),
                ),
              ),
              TextButton(
                onPressed: () => _edit(record),
                style: TextButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Text('编辑', style: TextStyle(fontSize: 12)),
              ),
              TextButton(
                onPressed: () => _delete(record),
                style: TextButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Text('删除',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.red)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10,
              color: foreground,
              fontWeight: FontWeight.w600)),
    );
  }

  String _formatTime(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }
}

class _EditInventoryDialog extends StatefulWidget {
  const _EditInventoryDialog({required this.record, required this.suppliers});
  final InventoryRecord record;
  final List<SupplierInfo> suppliers;

  @override
  State<_EditInventoryDialog> createState() => _EditInventoryDialogState();
}

class _EditInventoryDialogState extends State<_EditInventoryDialog> {
  late final TextEditingController _system;
  late final TextEditingController _actual;
  late final TextEditingController _code;
  late final TextEditingController _perBox;
  late final TextEditingController _desc;
  late final TextEditingController _batch;
  String? _supplierCode;
  String? _error;
  int? _actualPreview;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _system = TextEditingController(text: '${record.systemStock}');
    _actual = TextEditingController(text: '${record.actualStock}');
    _code = TextEditingController(text: record.materialCode);
    _perBox = TextEditingController(text: '${record.perBox}');
    _desc = TextEditingController(text: record.description);
    _batch = TextEditingController(text: record.batch);
    for (final supplier in widget.suppliers) {
      if (record.manufacturer.contains(supplier.name)) {
        _supplierCode = supplier.code;
        break;
      }
    }
    _actual.addListener(_updatePreview);
    _updatePreview();
  }

  @override
  void dispose() {
    _actual.removeListener(_updatePreview);
    _system.dispose();
    _actual.dispose();
    _code.dispose();
    _perBox.dispose();
    _desc.dispose();
    _batch.dispose();
    super.dispose();
  }

  void _updatePreview() {
    try {
      final value = ExpressionEvaluator.evaluate(_actual.text);
      setState(() => _actualPreview = value.toInt());
    } catch (_) {
      setState(() => _actualPreview = null);
    }
  }

  void _save() {
    try {
      if (!RegExp(r'^\d{9}$').hasMatch(_code.text.trim())) {
        throw const FormatException('物料代码必须是 9 位数字');
      }
      final perBox = int.tryParse(_perBox.text.trim()) ?? 0;
      if (perBox <= 0) throw const FormatException('包装数量必须大于 0');
      final system = ExpressionEvaluator.evaluate(_system.text);
      final actual = ExpressionEvaluator.evaluate(_actual.text);
      if (system < 0 || system != system.roundToDouble()) {
        throw const FormatException('系统库存必须是整数');
      }
      if (actual < 0 || actual != actual.roundToDouble()) {
        throw const FormatException('实际库存必须是整数');
      }
      SupplierInfo? supplier;
      for (final item in widget.suppliers) {
        if (item.code == _supplierCode) {
          supplier = item;
          break;
        }
      }
      if (supplier == null) throw const FormatException('请选择供应商');
      Navigator.pop(
        context,
        InventoryRecord(
          id: widget.record.id,
          createdAt: widget.record.createdAt,
          systemStock: system.toInt(),
          actualStock: actual.toInt(),
          materialCode: _code.text.trim(),
          perBox: perBox,
          description: _desc.text.trim(),
          batch: _batch.text.trim(),
          manufacturer: supplier.name,
          imagePath: widget.record.imagePath,
        ),
      );
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑库存记录'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                      child: TextField(
                    controller: _system,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '系统库存'),
                  )),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _actual,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9+*]')),
                      ],
                      decoration: InputDecoration(
                        labelText: '实际库存',
                        helperText: _actualPreview == null
                            ? null
                            : '合计 $_actualPreview',
                        suffixIcon: IconButton(
                          tooltip: '插入 +',
                          onPressed: () {
                            final text = _actual.text;
                            _actual.text = '$text+';
                            _actual.selection = TextSelection.collapsed(
                                offset: _actual.text.length);
                          },
                          icon: const Icon(Icons.add, size: 18),
                        ),
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
                decoration:
                    const InputDecoration(labelText: '物料代码', counterText: ''),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _perBox,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '包装数量'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _desc,
                decoration: const InputDecoration(labelText: '物料描述'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _batch,
                decoration: const InputDecoration(labelText: 'XS 批次号'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
          value: _supplierCode,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '供应商'),
                hint: const Text('请选择供应商'),
                items: widget.suppliers
                    .map((supplier) => DropdownMenuItem(
                          value: supplier.code,
                          child: Text('${supplier.code}  ${supplier.name}',
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _supplierCode = value),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style:
                        const TextStyle(fontSize: 11, color: AppColors.red)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
