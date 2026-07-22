import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';
import 'router/app_router.dart';

// ─── Design Tokens (mirrors web-app/style.css) ────────────────────────────────
class AppColors {
  // Modern Zinc/Charcoal Palette
  static const bgBase = Color(0xFF09090B); // Zinc 950
  static const bgCard = Color(0xFF18181B); // Zinc 900
  static const bgGlass = Color(0xD018181B);
  static const border = Color(0xFF27272A); // Zinc 800
  static const borderLight = Color(0xFF3F3F46); // Zinc 700

  static const textPrimary = Color(0xFFFAFAFA); // Zinc 50
  static const textSecondary = Color(0xFFA1A1AA); // Zinc 400
  static const textMuted = Color(0xFF71717A); // Zinc 500

  // Modern Accents
  static const accent = Color(0xFF6366F1); // Indigo 500
  static const accentLight = Color(0xFF818CF8); // Indigo 400

  // Aliases for old colors to prevent immediate breakage during refactoring
  static const gold = accent;
  static const saffron = accentLight;

  static const crimson = Color(0xFFEF4444);
  static const green = Color(0xFF10B981);
  static const blue = Color(0xFF3B82F6);
  static const purple = Color(0xFF8B5CF6);
  static const amber = Color(0xFFF59E0B);

  // Pin colours
  static const redPin = Color(0xFFEF4444);
  static const yellowPin = Color(0xFFF59E0B);
  static const greenPin = Color(0xFF10B981);
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
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.bgBase,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize dotenv
  await dotenv.load(fileName: ".env");

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Increase ImageCache size for panoramas
  PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 300;

  runApp(const ProviderScope(child: MyApp()));
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
    final base =
        GoogleFonts.plusJakartaSansTextTheme(ThemeData.dark().textTheme).apply(
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bgBase,
      textTheme: base,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accent,
        secondary: AppColors.accentLight,
        surface: AppColors.bgCard,
        onSurface: AppColors.textPrimary,
        error: AppColors.crimson,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bgBase.withValues(alpha: 0.95),
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: AppColors.textSecondary),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          textStyle: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textMuted),
        prefixIconColor: AppColors.textMuted,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 0.5,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.bgCard,
        contentTextStyle: GoogleFonts.plusJakartaSans(
          color: AppColors.textPrimary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border, width: 0.5),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
  }
}
