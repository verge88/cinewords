import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Material 3 Expressive theme for CineWords
class AppTheme {
  // Brand seed colors
  static const Color seedColor = Color(0xFF6750A4);
  static const Color secondarySeed = Color(0xFF00BFA5);
  static const Color tertiarySeed = Color(0xFFFFB74D);

  // Expressive shape theme: more rounded, organic shapes
  static final ShapeBorder expressiveSmall = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );
  static final ShapeBorder expressiveMedium = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(24),
  );
  static final ShapeBorder expressiveLarge = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(32),
  );

  static ThemeData lightTheme({ColorScheme? dynamicScheme}) {
    final colorScheme = dynamicScheme ??
        ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
          dynamicSchemeVariant: DynamicSchemeVariant.expressive,
        );

    return _buildTheme(colorScheme, Brightness.light);
  }

  static ThemeData darkTheme({ColorScheme? dynamicScheme}) {
    final colorScheme = dynamicScheme ??
        ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
          dynamicSchemeVariant: DynamicSchemeVariant.expressive,
        );

    return _buildTheme(colorScheme, Brightness.dark);
  }

  static ThemeData monochromeTheme() {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Colors.white,
      onPrimary: Colors.black,
      secondary: Color(0xFFEEEEEE),
      onSecondary: Colors.black,
      error: Color(0xFFCF6679),
      onError: Colors.black,
      surface: Colors.black,
      onSurface: Colors.white,
      surfaceContainerLow: Color(0xFF121212),
      surfaceContainer: Color(0xFF1E1E1E),
      surfaceContainerHighest: Color(0xFF2C2C2C),
      onSurfaceVariant: Color(0xFFB0B0B0),
      outline: Color(0xFF404040),
      outlineVariant: Color(0xFF606060),
    );

    return _buildTheme(colorScheme, Brightness.dark);
  }

  static ThemeData _buildTheme(ColorScheme colorScheme, Brightness brightness) {
    final textTheme = GoogleFonts.interTextTheme(
      brightness == Brightness.light
          ? ThemeData.light().textTheme
          : ThemeData.dark().textTheme,
    );

    // Expressive display font
    final displayTextTheme = textTheme.copyWith(
      displayLarge: GoogleFonts.plusJakartaSans(
        fontSize: 57,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.25,
        color: colorScheme.onSurface,
      ),
      displayMedium: GoogleFonts.plusJakartaSans(
        fontSize: 45,
        fontWeight: FontWeight.w700,
        color: colorScheme.onSurface,
      ),
      displaySmall: GoogleFonts.plusJakartaSans(
        fontSize: 36,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      headlineLarge: GoogleFonts.plusJakartaSans(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: colorScheme.onSurface,
      ),
      headlineMedium: GoogleFonts.plusJakartaSans(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      headlineSmall: GoogleFonts.plusJakartaSans(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: colorScheme.onSurface,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      textTheme: displayTextTheme,

      // Expressive shapes — high rounding
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        color: colorScheme.surfaceContainerLow,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          side: BorderSide(color: colorScheme.outline),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      ),

      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide.none,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        elevation: 2,
      ),

      navigationBarTheme: NavigationBarThemeData(
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 72,
        elevation: 0,
        backgroundColor: colorScheme.surfaceContainer,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        backgroundColor: colorScheme.surfaceContainerLow,
        showDragHandle: true,
      ),

      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 2,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint,
      ),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
