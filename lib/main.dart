import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'router/app_router.dart';

// ─── Design Tokens (mirrors web-app/style.css) ────────────────────────────────
class AppColors {
  static const bgBase    = Color(0xFF0A0D14);
  static const bgCard    = Color(0xFF12162B);
  static const bgGlass   = Color(0xD012162B); // ~82% opacity
  static const border    = Color(0x14FFFFFF); // ~8% white
  static const borderLight = Color(0x24FFFFFF); // ~14% white

  static const textPrimary   = Color(0xFFF0F2FF);
  static const textSecondary = Color(0xFF9AA0C0);
  static const textMuted     = Color(0xFF5A618A);

  static const gold    = Color(0xFFF5A623);
  static const saffron = Color(0xFFFF6A00);
  static const crimson = Color(0xFFE53935);
  static const green   = Color(0xFF22C55E);
  static const blue    = Color(0xFF6366F1);
  static const purple  = Color(0xFFA855F7);
  static const amber   = Color(0xFFF59E0B);

  // Pin colours
  static const redPin    = Color(0xFFEF4444);
  static const yellowPin = Color(0xFFF59E0B);
  static const greenPin  = Color(0xFF22C55E);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Dark status bar to match the dark theme
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.bgBase,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Increase ImageCache size for panoramas
  PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 300;

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Ganesh Chanda Tracker',
      debugShowCheckedModeBanner: false,
      theme: _buildDarkTheme(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }

  ThemeData _buildDarkTheme() {
    final base = GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bgBase,
      textTheme: base,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.gold,
        secondary: AppColors.saffron,
        surface: AppColors.bgCard,
        onSurface: AppColors.textPrimary,
        error: AppColors.crimson,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Color(0xF50A0D14), // ~96% opaque
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.outfit(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: AppColors.textSecondary),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: Colors.white,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0x10FFFFFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textMuted),
        prefixIconColor: AppColors.textMuted,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.bgCard,
        foregroundColor: AppColors.gold,
        elevation: 8,
      ),
      cardTheme: CardThemeData(
        color: AppColors.bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.bgCard,
        contentTextStyle: GoogleFonts.inter(color: AppColors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
    );
  }
}
