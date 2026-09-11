import 'package:flutter/material.dart';

/// OTP Flow palette — taken from the logo (deep navy + electric blue + mint shield).
class AppColors {
  static const navy = Color(0xFF0E1F3C);
  static const navySoft = Color(0xFF1B3054);
  static const blue = Color(0xFF1E88FF);
  static const blueDeep = Color(0xFF0B62D6);
  static const blueLight = Color(0xFF57ACFF);
  static const sky = Color(0xFFE8F2FF);
  static const skyLine = Color(0xFFCFE2FA);
  static const mint = Color(0xFF2FBF71);
  static const mintSoft = Color(0xFFE4F7EC);
  static const paper = Color(0xFFF6F9FE);
  static const card = Colors.white;
  static const ink = Color(0xFF12233D);
  static const ink2 = Color(0xFF5C7292);
  static const danger = Color(0xFFD93025);
  static const warn = Color(0xFFB26A00);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0E1F3C), Color(0xFF11498F), Color(0xFF1E88FF)],
  );
  static const otpGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF0B62D6), Color(0xFF1E88FF)],
  );
}

ThemeData buildTheme() {
  final base = ThemeData(useMaterial3: true, brightness: Brightness.light);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.paper,
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.blue,
      secondary: AppColors.mint,
      surface: AppColors.card,
      error: AppColors.danger,
    ),
    textTheme: base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.skyLine, width: 1.4),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.skyLine, width: 1.4),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.blue, width: 1.8),
      ),
      labelStyle: const TextStyle(color: AppColors.ink2, fontWeight: FontWeight.w600),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.navy,
      contentTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
