import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class AppColors {
  static const backgroundPrimary   = Color(0xFFFFFFFF);
  static const backgroundSecondary = Color(0xFFF5F5F7);
  static const surface             = Color(0xFFFFFFFF);
  static const separator           = Color(0xFFE1E1E6);

  static const accentBlue   = Color(0xFF0A84FF);
  static const accentGold   = Color(0xFFD4A843);
  static const accentGreen  = Color(0xFF30D158);
  static const accentRed    = Color(0xFFFF453A);
  static const accentOrange = Color(0xFFFF9F0A);
  static const accentPurple = Color(0xFFBF5AF2);
  static const accentCyan   = Color(0xFF64D2FF);
  static const accentPink   = Color(0xFFFF375F);

  static const textPrimary   = Color(0xFF0A0A0A);
  static const textSecondary = Color(0xFF4B4B53);
  static const textTertiary  = Color(0xFF7A7A85);

  static const List<Color> symbolPalette = [
    accentBlue, accentRed, accentGreen, accentOrange,
    accentPurple, accentCyan, accentPink, accentGold,
  ];
}

abstract final class AppSpacing {
  static const double sm  = 8;
  static const double md  = 16;
  static const double lg  = 24;
  static const double xl  = 32;
}

abstract final class AppRadius {
  static const double sm   = 8;
  static const double md   = 12;
  static const double lg   = 16;
  static const double xl   = 20;
  static const double pill = 100;
}

class AppTheme {
  const AppTheme._();

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.backgroundPrimary,
    fontFamily: '.SF Pro Display',
    colorScheme: const ColorScheme.light(
      primary:   AppColors.accentBlue,
      secondary: AppColors.accentGold,
      surface:   AppColors.backgroundSecondary,
      onSurface: AppColors.textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      iconTheme: IconThemeData(color: AppColors.textPrimary),
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: AppColors.textPrimary,
        fontFamily: '.SF Pro Display',
      ),
    ),
  );
}
