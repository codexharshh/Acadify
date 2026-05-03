import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  bool _isDark = false;

  bool get isDark => _isDark;

  void toggle() {
    _isDark = !_isDark;
    notifyListeners();
  }

  // ── Colors ────────────────────────────────────────────────────────
  Color get bgColor =>
      _isDark ? const Color(0xFF1A1A2E) : const Color(0xFFEEEEF5);

  Color get textPrimary => _isDark ? Colors.white : const Color(0xFF2D2D2D);

  Color get textSecondary => _isDark ? Colors.white60 : Colors.black54;

  Color get accentColor => const Color(0xFF7C4DFF);

  Color get cardColor =>
      _isDark ? const Color(0xFF1A1A2E) : const Color(0xFFEEEEF5);

  Color get iconBg => _isDark
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.black.withValues(alpha: 0.06);

  Color get shadowDark => _isDark
      ? Colors.black.withValues(alpha: 0.4)
      : Colors.grey.withValues(alpha: 0.3);

  Color get shadowLight => _isDark
      ? Colors.white.withValues(alpha: 0.04)
      : Colors.white.withValues(alpha: 0.9);
}
