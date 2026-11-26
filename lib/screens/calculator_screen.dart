import 'package:flutter/material.dart';

import '../calculator.dart';
import '../widgets.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final _totalController = TextEditingController(text: '100+30');
  final _perBoxController = TextEditingController(text: '30');
  String? _error;
  BoxOutcome? _outcome;

  @override
  void initState() {
    super.initState();
    _calculate();
  }

  @override
  void dispose() {
    _totalController.dispose();
    _perBoxController.dispose();
    super.dispose();
  }

  void _calculate() {
    try {
      final value = BoxCalculator.calculate(_totalController.text, _perBoxController.text);
      setState(() {
        _outcome = value;
        _error = null;
      });
    } on CalculatorException catch (e) {
      setState(() {
        _outcome = null;
        _error = e.message;
      });
    }
  }

  String _advice(BoxOutcome outcome) {
    if (outcome.remainder == 0) return '正好 ${outcome.boxes} 箱，无需调整';
    if (outcome.remainder <= outcome.perBox / 2) {
      return '建议拿 ${outcome.boxes} 箱，剩余 ${outcome.remainder} 个';
    }
    return '建议拿 ${outcome.boxes + 1} 箱，去掉 ${outcome.perBox - outcome.remainder} 个';
  }

  void _append(String value) {
    final text = _totalController.text;
    _totalController.text = '$text$value';
    _totalController.selection =
        TextSelection.collapsed(offset: _totalController.text.length);
    _calculate();
  }

  void _backspace() {
    final text = _totalController.text;
    if (text.isEmpty) return;
    _totalController.text = text.substring(0, text.length - 1);
    _totalController.selection =
        TextSelection.collapsed(offset: _totalController.text.length);
    _calculate();
  }

  @override
  Widget build(BuildContext context) {
    final keys = <String>[
      '7', '8', '9', '÷',
      '4', '5', '6', '×',
      '1', '2', '3', '-',
      '(', '0', ')', '+',
    ];
    return Scaffold(
      backgroundColor: AppColors.soft,
      appBar: AppBar(
        backgroundColor: AppColors.soft,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Color(0xFF344054)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('计算器', style: TextStyle(color: AppColors.text, fontSize: 20)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('货品总数（支持算式）',
                        style: TextStyle(fontSize: 11, color: Color(0xFF98A2B3))),
                    TextField(
                      controller: _totalController,
                      keyboardType: TextInputType.number,
                      style:
                          const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(border: InputBorder.none),
                      onChanged: (_) => _calculate(),
                    ),
                    const Divider(),
                    Row(
                      children: [
                        const Text('每箱数量',
                            style: TextStyle(fontSize: 13, color: AppColors.sub)),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 110,
                          child: TextField(
                            controller: _perBoxController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.end,
                            decoration: const InputDecoration(isDense: true),
                            onChanged: (_) => _calculate(),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text('个'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                child: Column(
                  children: [
                    if (_outcome != null) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${_outcome!.boxes}',
                              style: const TextStyle(
                                  fontSize: 52,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary)),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 10, left: 4),
                            child: Text('箱', style: TextStyle(color: AppColors.sub)),
                          ),
                          const SizedBox(width: 18),
                          Text('+ ${_outcome!.remainder}',
                              style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.orange)),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8, left: 4),
                            child: Text('个', style: TextStyle(color: AppColors.sub)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('总数 ${_outcome!.total} 个 · 每箱 ${_outcome!.perBox} 个',
                          style: const TextStyle(fontSize: 12, color: AppColors.sub)),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF4FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(_advice(_outcome!),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary)),
                      ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(_error ?? '请输入货品总数和每箱数量',
                            style: const TextStyle(color: AppColors.red)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.5,
                children: keys
                    .map((e) => _key(
                          e,
                          () => _append(e == '×' ? '*' : e == '÷' ? '/' : e),
                          highlight: e == '+' || e == '-' || e == '×' || e == '÷',
                        ))
                    .toList()
                  ..addAll([
                    _key('清空', () {
                      _totalController.clear();
                      _calculate();
                    }, danger: true),
                    _key('⌫', _backspace),
                    _key('=', _calculate, primary: true),
                  ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _key(String label, VoidCallback onTap,
      {bool highlight = false, bool primary = false, bool danger = false}) {
    final color = danger
        ? const Color(0xFFFFF1F0)
        : primary
            ? AppColors.primary
            : highlight
                ? const Color(0xFFEEF4FF)
                : Colors.white;
    final textColor = primary
        ? Colors.white
        : danger
            ? AppColors.red
            : AppColors.text;
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Center(
          child: Text(label,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: textColor)),
        ),
      ),
    );
  }
}
