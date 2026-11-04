import 'package:flutter/material.dart';

class AppTheme {
  static const Color background = Color(0xFF0B0D0F);
  static const Color cardBackground = Color(0xFF131719);
  static const Color inputBackground = Color(0xFF1A1D20);

  static const Color primaryGreen = Color(0xFF00C9A7);
  static const Color accentYellow = Color(0xFFDCE45B);

  static const Color primaryText = Color(0xFFF2F3F1);
  static const Color secondaryText = Color(0xFF858B8D);
  static const Color borderColor = Color(0xFF292E30);
  static const Color errorColor = Color(0xFFFF6B6B);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      fontFamily: 'Arial',
      colorScheme: const ColorScheme.dark(
        primary: primaryGreen,
        secondary: accentYellow,
        surface: cardBackground,
        error: errorColor,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: primaryText,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputBackground,
        hintStyle: const TextStyle(
          color: secondaryText,
        ),
        labelStyle: const TextStyle(
          color: secondaryText,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(
            color: borderColor,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(
            color: borderColor,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(
            color: primaryGreen,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}