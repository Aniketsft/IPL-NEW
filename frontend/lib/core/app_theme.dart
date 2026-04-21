import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primaryAmber = Color(0xFFFF9800);
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);

  static const Color lightBackground = Color(0xFFF5F5F5);
  static const Color lightSurface = Colors.white;

  static ThemeData get darkTheme => _buildTheme(Brightness.dark);
  static ThemeData get lightTheme => _buildTheme(Brightness.light);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bgColor = isDark ? darkBackground : lightBackground;
    final surfaceColor = isDark ? darkSurface : lightSurface;
    final textColor = isDark ? Colors.white : Colors.black87;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      primaryColor: primaryAmber,
      scaffoldBackgroundColor: bgColor,
      cardColor: surfaceColor,
      
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryAmber,
        brightness: brightness,
        primary: primaryAmber,
        onPrimary: Colors.black,
        primaryContainer: isDark ? const Color(0xFF332000) : const Color(0xFFFFEBD1),
        onPrimaryContainer: isDark ? const Color(0xFFFFDAB3) : const Color(0xFF4D3300),
        secondary: isDark ? const Color(0xFF03DAC6) : const Color(0xFF018786),
        onSecondary: Colors.black,
        secondaryContainer: isDark ? const Color(0xFF003D33) : const Color(0xFFCFEBEA),
        onSecondaryContainer: isDark ? const Color(0xFFB2DFDB) : const Color(0xFF002B26),
        surface: surfaceColor,
        onSurface: isDark ? Colors.white : Colors.black87,
        error: Colors.redAccent,
      ),

      iconTheme: IconThemeData(
        color: isDark ? Colors.white.withValues(alpha: 0.7) : Colors.black.withValues(alpha: 0.54),
      ),

      textTheme: GoogleFonts.outfitTextTheme(
        (isDark ? ThemeData.dark() : ThemeData.light()).textTheme,
      ).apply(
        bodyColor: textColor,
        displayColor: textColor,
      ).copyWith(
        headlineMedium: TextStyle(
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
          color: isDark ? Colors.white : Colors.black87,
        ),
        titleMedium: TextStyle(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: isDark ? Colors.white70 : Colors.black87,
        ),
      ),

      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: isDark ? 0 : 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: primaryAmber,
        unselectedLabelColor: isDark ? Colors.white38 : Colors.black38,
        indicatorSize: TabBarIndicatorSize.label,
        indicatorColor: primaryAmber,
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceColor,
        selectedItemColor: primaryAmber,
        unselectedItemColor: isDark ? Colors.white24 : Colors.black26,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF161616) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryAmber, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black26),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryAmber,
          foregroundColor: Colors.black,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: isDark ? 0 : 4,
          shadowColor: primaryAmber.withValues(alpha: 0.3),
          textStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            fontSize: 16,
          ),
        ),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: isDark ? primaryAmber : Colors.black87),
        titleTextStyle: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          fontFamily: GoogleFonts.outfit().fontFamily,
        ),
      ),
    );
  }
}
