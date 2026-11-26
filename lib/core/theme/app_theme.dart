import 'package:material_ui/material_ui.dart';

class AppColors {
  const AppColors._();

  static const Color background = Color(0xFF06060A);
  static const Color surface = Color(0xFF101015);
  static const Color surfaceHigh = Color(0xFF17171F);
  static const Color border = Color(0xFF2A2A35);
  static const Color crimson = Color(0xFFFF3355);
  static const Color crimsonBright = Color(0xFFFF5C7A);
  static const Color crimsonDim = Color(0xFF7A1628);
  static const Color textPrimary = Color(0xFFF4F4F6);
  static const Color textSecondary = Color(0xFFA7A7B4);
  static const Color success = Color(0xFF3DDC97);
  static const Color warning = Color(0xFFFFB020);
  static const Color danger = Color(0xFFFF6B6B);
}

class AppTheme {
  const AppTheme._();

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final background = isDark ? AppColors.background : const Color(0xFFF7F7FA);
    final surface = isDark ? AppColors.surface : Colors.white;
    final surfaceHigh = isDark
        ? AppColors.surfaceHigh
        : const Color(0xFFEDEDF3);
    final border = isDark ? AppColors.border : const Color(0xFFD9D9E3);
    final textPrimary = isDark
        ? AppColors.textPrimary
        : const Color(0xFF15151B);
    final textSecondary = isDark
        ? AppColors.textSecondary
        : const Color(0xFF5B5B6B);

    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.crimson,
          brightness: brightness,
        ).copyWith(
          primary: isDark ? AppColors.crimson : const Color(0xFFC8102E),
          onPrimary: Colors.white,
          secondary: isDark ? AppColors.crimsonBright : const Color(0xFF9F1239),
          surface: surface,
          onSurface: textPrimary,
          error: isDark ? AppColors.danger : const Color(0xFFB3261E),
          outline: border,
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      textTheme: base.textTheme
          .apply(bodyColor: textPrimary, displayColor: textPrimary)
          .copyWith(
            headlineLarge: base.textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
            ),
            headlineMedium: base.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
            titleLarge: base.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
            titleMedium: base.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            bodySmall: base.textTheme.bodySmall?.copyWith(color: textSecondary),
            labelSmall: base.textTheme.labelSmall?.copyWith(
              color: textSecondary,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: textPrimary,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        hintStyle: TextStyle(color: textSecondary.withValues(alpha: 0.8)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? AppColors.crimson : scheme.primary,
            width: 1.4,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: isDark ? AppColors.crimson : scheme.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          minimumSize: const Size(0, 48),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? AppColors.crimsonBright : scheme.primary,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surfaceHigh,
        selectedColor: AppColors.crimsonDim,
        side: BorderSide(color: border),
        labelStyle: TextStyle(color: textPrimary, fontSize: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: isDark ? AppColors.crimson : scheme.primary,
        thumbColor: isDark ? AppColors.crimsonBright : scheme.primary,
        inactiveTrackColor: border,
        overlayColor: AppColors.crimson.withValues(alpha: 0.15),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: TextStyle(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: isDark ? AppColors.crimsonBright : scheme.primary,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: AppColors.crimson.withValues(alpha: 0.16),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 11, color: textSecondary),
        ),
      ),
    );
  }
}
