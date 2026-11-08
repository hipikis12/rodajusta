import 'package:flutter/material.dart';

/// Identidade visual do RodaJusta: verde da marca e âmbar da "vez".
class Cores {
  static const verde = Color(0xFF0F6B4F);
  static const verdeEscuro = Color(0xFF0A4D39);
  static const ambar = Color(0xFFF5B700);
  static const tinta = Color(0xFF10221B);
}

ThemeData temaRodaJusta(Brightness brilho) {
  final esquema = ColorScheme.fromSeed(
    seedColor: Cores.verde,
    brightness: brilho,
    primary: brilho == Brightness.light ? Cores.verde : null,
    secondary: Cores.ambar,
  );
  return ThemeData(
    colorScheme: esquema,
    useMaterial3: true,
    appBarTheme: AppBarTheme(
      backgroundColor: esquema.surface,
      foregroundColor: esquema.onSurface,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6)),
  );
}
