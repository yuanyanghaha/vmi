import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF2F6BFF);
  static const text = Color(0xFF101828);
  static const sub = Color(0xFF667085);
  static const soft = Color(0xFFF6F8FC);
  static const card = Color(0xFFF8FAFD);
  static const red = Color(0xFFE5484D);
  static const orange = Color(0xFFF97316);
  static const green = Color(0xFF0E9F6E);
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(milliseconds: 1600)),
  );
}

class CodeText extends StatelessWidget {
  const CodeText(this.code, {super.key, this.fontSize = 17});
  final String code;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final prefix = code.length > 4 ? code.substring(0, code.length - 4) : '';
    final suffix = code.length > 4 ? code.substring(code.length - 4) : code;
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: prefix, style: const TextStyle(color: AppColors.text)),
        TextSpan(
          text: suffix,
          style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.bold),
        ),
      ]),
      style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE9EEF7)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x082F6BFF), blurRadius: 24, offset: Offset(0, 10)),
        ],
      ),
      child: child,
    );
  }
}

class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontSize: 15, color: AppColors.sub)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, style: const TextStyle(fontSize: 11, color: Color(0xFF98A2B3))),
          ],
        ],
      ),
    );
  }
}
