import 'package:flutter/material.dart';

/// 简约政务工具风：低饱和青绿色主色、强对比中性色、圆角 8/12。
class AppTheme {
  const AppTheme._();

  static const Color seed = Color(0xFF17695F);
  static const Color accent = Color(0xFF17A38C);
  static const Color warning = Color(0xFFC2570A);
  static const Color danger = Color(0xFFB3261E);
  static const Color online = Color(0xFF1B7F4B);

  static ThemeData dark() => _build(Brightness.dark);
  static ThemeData light() => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF101413) : const Color(0xFFF6F7F6),
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor:
            isDark ? const Color(0xFF141917) : const Color(0xFFFFFFFF),
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        color: isDark ? const Color(0xFF181D1C) : const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      listTileTheme: const ListTileThemeData(
        visualDensity: VisualDensity.compact,
        minLeadingWidth: 20,
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? const Color(0xFF242A28) : const Color(0xFFE4E7E5),
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor:
            isDark ? const Color(0xFF141917) : const Color(0xFFFFFFFF),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
    );
  }

  /// 状态色（在线/离线/告警），UI 与预览共用。
  static Color statusColor(bool ok, BuildContext context) => ok
      ? online
      : Theme.of(context).colorScheme.error;
}
