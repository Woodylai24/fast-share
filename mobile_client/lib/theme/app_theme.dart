import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Centralized theme definitions for the Fast Share mobile client.
///
/// Provides both dark and light [ThemeData] configurations that use
/// Material 3. The dark theme matches the PC client aesthetic with
/// #242424 scaffold backgrounds, #1a1a1a card surfaces, #007bff blue
/// accent, and white text.
///
/// Usage:
/// ```dart
/// MaterialApp(
///   theme: AppTheme.light,
///   darkTheme: AppTheme.dark,
///   themeMode: ThemeMode.dark,
/// )
/// ```
abstract final class AppTheme {
  // ──────────────────────────────────────────────
  // Brand colours
  // ──────────────────────────────────────────────
  static const Color accentBlue = Color(0xFF007BFF);
  static const Color accentBlueLight = Color(0xFF339DFF);
  static const Color accentBlueDark = Color(0xFF0056B3);

  // Dark palette (PC client aesthetic)
  static const Color darkScaffold = Color(0xFF242424);
  static const Color darkCard = Color(0xFF1A1A1A);
  static const Color darkSurface = Color(0xFF2A2A2A);
  static const Color darkDivider = Color(0xFF3A3A3A);
  static const Color darkInputFill = Color(0xFF2E2E2E);
  static const Color darkAppBar = Color(0xFF1F1F1F);

  // Light palette
  static const Color lightScaffold = Color(0xFFF5F5F5);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightDivider = Color(0xFFE0E0E0);
  static const Color lightInputFill = Color(0xFFEEEEEE);
  static const Color lightAppBar = Color(0xFFFFFFFF);

  // ──────────────────────────────────────────────
  // Shared helper builders
  // ──────────────────────────────────────────────

  static MaterialColor _toMaterialColor(Color color) {
    final int r = color.red;
    final int g = color.green;
    final int b = color.blue;
    return MaterialColor(color.value, {
      50: Color.fromARGB(255, (r + 204) ~/ 5, (g + 204) ~/ 5, (b + 204) ~/ 5),
      100: Color.fromARGB(255, (r + 153) * 2 ~/ 5, (g + 153) * 2 ~/ 5, (b + 153) * 2 ~/ 5),
      200: Color.fromARGB(255, (r + 102) * 3 ~/ 5, (g + 102) * 3 ~/ 5, (b + 102) * 3 ~/ 5),
      300: Color.fromARGB(255, (r + 51) * 4 ~/ 5, (g + 51) * 4 ~/ 5, (b + 51) * 4 ~/ 5),
      400: Color.fromARGB(230, r, g, b),
      500: color,
      600: Color.fromARGB(255, r * 4 ~/ 5, g * 4 ~/ 5, b * 4 ~/ 5),
      700: Color.fromARGB(255, r * 3 ~/ 5, g * 3 ~/ 5, b * 3 ~/ 5),
      800: Color.fromARGB(255, r * 2 ~/ 5, g * 2 ~/ 5, b * 2 ~/ 5),
      900: Color.fromARGB(255, r ~/ 5, g ~/ 5, b ~/ 5),
    });
  }

  static const String _fontFamily = 'Roboto';

  // ──────────────────────────────────────────────
  // Dark theme – matches PC client aesthetic
  // ──────────────────────────────────────────────
  static ThemeData get dark {
    final colorScheme = ColorScheme.dark(
      primary: accentBlue,
      onPrimary: Colors.white,
      primaryContainer: accentBlueDark,
      onPrimaryContainer: Colors.white,
      secondary: accentBlueLight,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFF1A3A5C),
      onSecondaryContainer: Colors.white,
      tertiary: accentBlue,
      surface: darkSurface,
      onSurface: Colors.white,
      surfaceContainerHighest: darkCard,
      error: Colors.redAccent,
      onError: Colors.white,
      outline: darkDivider,
      outlineVariant: const Color(0xFF2E2E2E),
      scrim: Colors.black,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      primaryColor: accentBlue,
      primaryColorDark: accentBlueDark,
      primaryColorLight: accentBlueLight,
      scaffoldBackgroundColor: darkScaffold,
      canvasColor: darkSurface,
      cardColor: darkCard,
      dividerColor: darkDivider,
      fontFamily: _fontFamily,
      materialTapTargetSize: MaterialTapTargetSize.padded,

      // ── AppBar ──
      appBarTheme: const AppBarTheme(
        backgroundColor: darkAppBar,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 2,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        iconTheme: IconThemeData(color: Colors.white, size: 24),
        actionsIconTheme: IconThemeData(color: Colors.white70, size: 24),
        titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),

      // ── Card ──
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 1,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      ),

      // ── ElevatedButton ──
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: accentBlue.withValues(alpha: 0.38),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.38),
          elevation: 2,
          shadowColor: accentBlue.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontFamily: _fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),

      // ── TextButton ──
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentBlueLight,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontFamily: _fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── OutlinedButton ──
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accentBlueLight,
          side: const BorderSide(color: accentBlue, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontFamily: _fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── InputDecoration / TextField ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkInputFill,
        hintStyle: TextStyle(color: Colors.grey[500], fontSize: 15),
        labelStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
        floatingLabelStyle: const TextStyle(color: accentBlueLight, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: accentBlue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        isDense: true,
      ),

      // ── Divider ──
      dividerTheme: const DividerThemeData(
        color: darkDivider,
        thickness: 0.8,
        space: 1,
      ),

      // ── BottomSheet ──
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        clipBehavior: Clip.antiAlias,
      ),

      // ── Dialog ──
      dialogTheme: DialogThemeData(
        backgroundColor: darkSurface,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),

      // ── Snackbar ──
      snackBarTheme: SnackBarThemeData(
        backgroundColor: darkSurface,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        behavior: SnackBarBehavior.floating,
        actionTextColor: accentBlueLight,
      ),

      // ── Chip ──
      chipTheme: ChipThemeData(
        backgroundColor: darkSurface,
        selectedColor: accentBlueDark,
        labelStyle: const TextStyle(color: Colors.white, fontSize: 13),
        secondaryLabelStyle: const TextStyle(color: Colors.white, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        side: const BorderSide(color: darkDivider, width: 0.8),
      ),

      // ── Floating Action Button ──
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accentBlue,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),

      // ── Icon ──
      iconTheme: const IconThemeData(
        color: Colors.white70,
        size: 24,
      ),

      // ── TabBar ──
      tabBarTheme: TabBarThemeData(
        labelColor: accentBlue,
        unselectedLabelColor: Colors.grey[500],
        indicatorColor: accentBlue,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
      ),

      // ── BottomNavigationBar ──
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: darkAppBar,
        selectedItemColor: accentBlue,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      // ── PopupMenu ──
      popupMenuTheme: PopupMenuThemeData(
        color: darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 14),
      ),

      // ── ListTile ──
      listTileTheme: const ListTileThemeData(
        textColor: Colors.white,
        iconColor: Colors.white70,
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),

      // ── ProgressIndicator ──
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accentBlue,
        linearTrackColor: darkDivider,
      ),

      // ── Switch ──
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accentBlue;
          return Colors.grey[600]!;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accentBlueDark;
          return Colors.grey[800]!;
        }),
      ),

      // ── Checkbox ──
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accentBlue;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
        ),
      ),

      // ── Tooltip ──
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: darkSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: darkDivider),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 13),
      ),

      // ── Text styles ──
      textTheme: const TextTheme(
        displayLarge: TextStyle(color: Colors.white, fontSize: 57, fontWeight: FontWeight.w400),
        displayMedium: TextStyle(color: Colors.white, fontSize: 45, fontWeight: FontWeight.w400),
        displaySmall: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w400),
        headlineLarge: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w400),
        headlineMedium: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w400),
        headlineSmall: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w400),
        titleLarge: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w500),
        titleMedium: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
        titleSmall: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w400),
        bodyMedium: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w400),
        bodySmall: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w400),
        labelLarge: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
        labelMedium: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
        labelSmall: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Light theme
  // ──────────────────────────────────────────────
  static ThemeData get light {
    final colorScheme = ColorScheme.light(
      primary: accentBlue,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFD0E8FF),
      onPrimaryContainer: const Color(0xFF001E3C),
      secondary: accentBlueLight,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFD4EAFF),
      onSecondaryContainer: const Color(0xFF001D36),
      tertiary: accentBlue,
      surface: lightSurface,
      onSurface: Colors.black87,
      surfaceContainerHighest: lightCard,
      error: Colors.redAccent,
      onError: Colors.white,
      outline: lightDivider,
      outlineVariant: const Color(0xFFF0F0F0),
      scrim: Colors.black,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      primaryColor: accentBlue,
      primaryColorDark: accentBlueDark,
      primaryColorLight: accentBlueLight,
      scaffoldBackgroundColor: lightScaffold,
      canvasColor: lightSurface,
      cardColor: lightCard,
      dividerColor: lightDivider,
      fontFamily: _fontFamily,
      materialTapTargetSize: MaterialTapTargetSize.padded,

      // ── AppBar ──
      appBarTheme: const AppBarTheme(
        backgroundColor: lightAppBar,
        foregroundColor: Colors.black87,
        elevation: 0,
        scrolledUnderElevation: 2,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        iconTheme: IconThemeData(color: Colors.black87, size: 24),
        actionsIconTheme: IconThemeData(color: Colors.black54, size: 24),
        titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),

      // ── Card ──
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 1,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      ),

      // ── ElevatedButton ──
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: accentBlue.withValues(alpha: 0.38),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.38),
          elevation: 2,
          shadowColor: accentBlue.withValues(alpha: 0.3),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontFamily: _fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),

      // ── TextButton ──
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentBlue,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontFamily: _fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── OutlinedButton ──
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accentBlue,
          side: const BorderSide(color: accentBlue, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontFamily: _fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── InputDecoration / TextField ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightInputFill,
        hintStyle: TextStyle(color: Colors.grey[500], fontSize: 15),
        labelStyle: TextStyle(color: Colors.grey[700], fontSize: 14),
        floatingLabelStyle: const TextStyle(color: accentBlue, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: accentBlue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        isDense: true,
      ),

      // ── Divider ──
      dividerTheme: const DividerThemeData(
        color: lightDivider,
        thickness: 0.8,
        space: 1,
      ),

      // ── BottomSheet ──
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        clipBehavior: Clip.antiAlias,
      ),

      // ── Dialog ──
      dialogTheme: DialogThemeData(
        backgroundColor: lightSurface,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),

      // ── Snackbar ──
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF323232),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        behavior: SnackBarBehavior.floating,
        actionTextColor: accentBlueLight,
      ),

      // ── Chip ──
      chipTheme: ChipThemeData(
        backgroundColor: lightInputFill,
        selectedColor: const Color(0xFFD0E8FF),
        labelStyle: const TextStyle(color: Colors.black87, fontSize: 13),
        secondaryLabelStyle: const TextStyle(color: Colors.black87, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        side: const BorderSide(color: lightDivider, width: 0.8),
      ),

      // ── Floating Action Button ──
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accentBlue,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),

      // ── Icon ──
      iconTheme: const IconThemeData(
        color: Colors.black54,
        size: 24,
      ),

      // ── TabBar ──
      tabBarTheme: TabBarThemeData(
        labelColor: accentBlue,
        unselectedLabelColor: Colors.grey[600],
        indicatorColor: accentBlue,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
      ),

      // ── BottomNavigationBar ──
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: lightAppBar,
        selectedItemColor: accentBlue,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      // ── PopupMenu ──
      popupMenuTheme: PopupMenuThemeData(
        color: lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(color: Colors.black87, fontSize: 14),
      ),

      // ── ListTile ──
      listTileTheme: const ListTileThemeData(
        textColor: Colors.black87,
        iconColor: Colors.black54,
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),

      // ── ProgressIndicator ──
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accentBlue,
        linearTrackColor: lightDivider,
      ),

      // ── Switch ──
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accentBlue;
          return Colors.grey[400]!;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return const Color(0xFFD0E8FF);
          return Colors.grey[300]!;
        }),
      ),

      // ── Checkbox ──
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accentBlue;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
        ),
      ),

      // ── Tooltip ──
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF323232),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 13),
      ),

      // ── Text styles ──
      textTheme: const TextTheme(
        displayLarge: TextStyle(color: Colors.black87, fontSize: 57, fontWeight: FontWeight.w400),
        displayMedium: TextStyle(color: Colors.black87, fontSize: 45, fontWeight: FontWeight.w400),
        displaySmall: TextStyle(color: Colors.black87, fontSize: 36, fontWeight: FontWeight.w400),
        headlineLarge: TextStyle(color: Colors.black87, fontSize: 32, fontWeight: FontWeight.w400),
        headlineMedium: TextStyle(color: Colors.black87, fontSize: 28, fontWeight: FontWeight.w400),
        headlineSmall: TextStyle(color: Colors.black87, fontSize: 24, fontWeight: FontWeight.w400),
        titleLarge: TextStyle(color: Colors.black87, fontSize: 22, fontWeight: FontWeight.w500),
        titleMedium: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w500),
        titleSmall: TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w400),
        bodyMedium: TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w400),
        bodySmall: TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w400),
        labelLarge: TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w500),
        labelMedium: TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w500),
        labelSmall: TextStyle(color: Colors.black45, fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }
}
