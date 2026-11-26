class BoxOutcome {
  final int total;
  final int perBox;
  final int boxes;
  final int remainder;

  const BoxOutcome(this.total, this.perBox, this.boxes, this.remainder);
}

class CalculatorException implements Exception {
  final String message;
  CalculatorException(this.message);
  @override
  String toString() => message;
}

class _ExpressionParser {
  _ExpressionParser(this.text);
  final String text;
  int pos = 0;

  double parse() {
    final value = _additive();
    _skipSpaces();
    if (pos < text.length) {
      throw CalculatorException('表达式格式有误，请检查运算符或括号');
    }
    return value;
  }

  double _additive() {
    var value = _multiplicative();
    while (true) {
      _skipSpaces();
      final ch = _peek();
      if (ch == '+') {
        pos++;
        value += _multiplicative();
      } else if (ch == '-') {
        pos++;
        value -= _multiplicative();
      } else {
        break;
      }
    }
    return value;
  }

  double _multiplicative() {
    var value = _unary();
    while (true) {
      _skipSpaces();
      final ch = _peek();
      if (ch == '*') {
        pos++;
        value *= _unary();
      } else if (ch == '/') {
        pos++;
        final divisor = _unary();
        if (divisor == 0) throw CalculatorException('除数不能为 0');
        value /= divisor;
      } else {
        break;
      }
    }
    return value;
  }

  double _unary() {
    _skipSpaces();
    final ch = _peek();
    if (ch == '+') {
      pos++;
      return _unary();
    }
    if (ch == '-') {
      pos++;
      return -_unary();
    }
    if (ch == '(') {
      pos++;
      final value = _additive();
      _skipSpaces();
      if (_peek() != ')') throw CalculatorException('括号不匹配');
      pos++;
      return value;
    }
    return _number();
  }

  double _number() {
    _skipSpaces();
    final start = pos;
    var hasDot = false;
    while (pos < text.length) {
      final ch = text[pos];
      if (ch.compareTo('0') >= 0 && ch.compareTo('9') <= 0) {
        pos++;
        continue;
      }
      if (ch == '.' && !hasDot) {
        hasDot = true;
        pos++;
        continue;
      }
      break;
    }
    final raw = text.substring(start, pos);
    if (raw.isEmpty || raw == '.' || raw.endsWith('.')) {
      throw CalculatorException('算式不完整或数字格式有误');
    }
    final value = double.tryParse(raw);
    if (value == null || !value.isFinite) throw CalculatorException('数字超出可计算范围');
    return value;
  }

  void _skipSpaces() {
    while (pos < text.length && text[pos] == ' ') {
      pos++;
    }
  }

  String _peek() => pos < text.length ? text[pos] : '';
}

class ExpressionEvaluator {
  static double evaluate(String input) {
    final text = normalize(input).trim();
    if (text.isEmpty) throw CalculatorException('请输入货品总数');
    if (text.length > 120) throw CalculatorException('算式太长，请精简到 120 个字符以内');
    if (!RegExp(r'^[0-9+\-*/(). ]+$').hasMatch(text)) {
      throw CalculatorException('仅支持数字、+ - × ÷ 和括号');
    }
    final value = _ExpressionParser(text).parse();
    if (!value.isFinite) throw CalculatorException('计算结果无效');
    return value;
  }

  static String normalize(String raw) {
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final ch = raw[i];
      final code = raw.codeUnitAt(i);
      if (code >= 0xFF10 && code <= 0xFF19) {
        buffer.writeCharCode(code - 0xFEE0);
        continue;
      }
      switch (ch) {
        case '（':
          buffer.write('(');
        case '）':
          buffer.write(')');
        case '＋':
          buffer.write('+');
        case '－':
        case '−':
        case '–':
          buffer.write('-');
        case '×':
        case 'x':
        case 'X':
        case '＊':
          buffer.write('*');
        case '÷':
        case '／':
          buffer.write('/');
        case '．':
          buffer.write('.');
        case '　':
        case '\t':
        case '\n':
          buffer.write(' ');
        default:
          buffer.write(ch);
      }
    }
    return buffer.toString();
  }

  static bool hasExpression(String text) => RegExp(r'[+\-*/×÷（）()]').hasMatch(text);
}

class BoxCalculator {
  static const maxValue = 1000000000000000;

  static BoxOutcome calculate(String totalText, String perBoxText) {
    final totalDouble = ExpressionEvaluator.evaluate(totalText);
    if (totalDouble < 0) throw CalculatorException('货品总数不能是负数');
    if (totalDouble != totalDouble.roundToDouble()) throw CalculatorException('货品总数需要是整数');
    if (totalDouble > maxValue) throw CalculatorException('货品总数过大');
    final total = totalDouble.toInt();

    final perText = perBoxText.trim();
    if (perText.isEmpty) throw CalculatorException('请输入每箱数量');
    if (!RegExp(r'^[0-9]+$').hasMatch(perText)) throw CalculatorException('每箱数量必须是正整数');
    final perBox = int.tryParse(perText) ?? 0;
    if (perBox <= 0) throw CalculatorException('每箱数量必须大于 0');
    final boxes = total ~/ perBox;
    final remainder = total - boxes * perBox;
    return BoxOutcome(total, perBox, boxes, remainder);
  }
}
