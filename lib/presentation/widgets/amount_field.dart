import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 金额输入框：仅允许数字与一个小数点，最多两位小数。
class AmountField extends StatelessWidget {
  const AmountField({super.key, required this.controller, this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
      textAlign: TextAlign.center,
      decoration: const InputDecoration(
        hintText: '0.00',
        prefixText: '¥ ',
        border: InputBorder.none,
      ),
      inputFormatters: [AmountInputFormatter()],
      onChanged: onChanged,
    );
  }
}

class AmountInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    if (!RegExp(r'^\d{0,7}(\.\d{0,2})?$').hasMatch(text)) return oldValue;
    return newValue;
  }
}
