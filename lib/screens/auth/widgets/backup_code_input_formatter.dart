import 'package:flutter/services.dart';

/// Formats backup codes as XXXXX-XXXXX, inserting the hyphen
/// automatically once a sixth raw character exists.
class BackupCodeInputFormatter extends TextInputFormatter {
  static const int _maxRaw = 10;
  static const int _groupSize = 5;
  static final RegExp _nonRaw = RegExp(r'[^A-Z0-9]');

  static String _raw(String text) =>
      text.toUpperCase().replaceAll(_nonRaw, '');

  static String _format(String raw) => raw.length > _groupSize
      ? '${raw.substring(0, _groupSize)}-${raw.substring(_groupSize)}'
      : raw;

  static int _offsetForRawIndex(int rawIndex) =>
      rawIndex <= _groupSize ? rawIndex : rawIndex + 1;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Backspacing over the hyphen would reformat back to it; delete the
    // raw character before the hyphen instead so backspace keeps working.
    final extent = newValue.selection.extentOffset;
    if (newValue.text.length == oldValue.text.length - 1 &&
        extent >= 0 &&
        extent < oldValue.text.length &&
        oldValue.text[extent] == '-' &&
        _raw(newValue.text) == _raw(oldValue.text)) {
      final rawBefore =
          _raw(oldValue.text.substring(0, extent)).length;
      if (rawBefore > 0) {
        final raw = _raw(oldValue.text);
        final kept = raw.substring(0, rawBefore - 1) +
            raw.substring(rawBefore);
        return TextEditingValue(
          text: _format(kept),
          selection:
              TextSelection.collapsed(offset: _offsetForRawIndex(rawBefore - 1)),
        );
      }
    }

    var raw = _raw(newValue.text);
    if (raw.length > _maxRaw) raw = raw.substring(0, _maxRaw);
    final formatted = _format(raw);

    if (extent < 0) {
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
    final clamped = extent.clamp(0, newValue.text.length);
    var rawBeforeCaret = _raw(newValue.text.substring(0, clamped)).length;
    if (rawBeforeCaret > _maxRaw) rawBeforeCaret = _maxRaw;
    return TextEditingValue(
      text: formatted,
      selection:
          TextSelection.collapsed(offset: _offsetForRawIndex(rawBeforeCaret)),
    );
  }
}
