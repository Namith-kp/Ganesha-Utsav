import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../providers/panorama_download_provider.dart';
import '../main.dart';
import 'street_view_screen.dart';

class PanoramaDownloadScreen extends ConsumerStatefulWidget {
  final double lat;
  final double lon;

  const PanoramaDownloadScreen({
    super.key,
    required this.lat,
    required this.lon,
  });

  @override
  ConsumerState<PanoramaDownloadScreen> createState() => _PanoramaDownloadScreenState();
}

class _PanoramaDownloadScreenState extends ConsumerState<PanoramaDownloadScreen>
    with SingleTickerProviderStateMixin {
  bool _downloading = false;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _goToStreetView() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => StreetViewScreen(lat: widget.lat, lon: widget.lon),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // If already downloaded — skip straight to street view
    final downloadComplete = ref.watch(panoramaDownloadCompleteProvider);
    downloadComplete.whenData((done) {
      if (done && !_downloading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _goToStreetView();
        });
      }
    });

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: _downloading
          ? _DownloadingView(onDone: _goToStreetView)
          : _PromptView(
              onDownload: () => setState(() => _downloading = true),
              onSkip: _goToStreetView,
              pulseCtrl: _pulseCtrl,
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Initial prompt screen — Download Now / Skip
// ─────────────────────────────────────────────────────────────────────────────
class _PromptView extends StatelessWidget {
  const _PromptView({
    required this.onDownload,
    required this.onSkip,
    required this.pulseCtrl,
  });
  final VoidCallback onDownload;
  final VoidCallback onSkip;
  final AnimationController pulseCtrl;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon with pulse glow
            AnimatedBuilder(
              animation: pulseCtrl,
              builder: (_, child) => Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.gold.withValues(alpha: 0.15 + pulseCtrl.value * 0.25),
                      blurRadius: 30 + pulseCtrl.value * 20,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: child,
              ),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.bgCard,
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: const Icon(LucideIcons.downloadCloud,
                    size: 52, color: AppColors.accent),
              ),
            ),
            const SizedBox(height: 32),

            // Title
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppColors.accent, AppColors.accentLight],
              ).createShader(bounds),
              child: Text(
                'Download Street View',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 14),

            Text(
              'Download all panorama images to your device for instant, offline access. This only needs to be done once.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 12),

            // Info chips
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _InfoChip(icon: LucideIcons.wifiOff, label: 'Works Offline'),
                _InfoChip(icon: LucideIcons.zap, label: 'Instant Loading'),
                _InfoChip(icon: LucideIcons.refreshCw, label: 'Skips Downloaded'),
              ],
            ),
            const SizedBox(height: 44),

            // Download button
            _GoldButton(
              label: 'Download Now',
              icon: LucideIcons.download,
              onTap: onDownload,
            ),
            const SizedBox(height: 16),

            // Skip button
            TextButton.icon(
              onPressed: onSkip,
              icon: const Icon(LucideIcons.wifi, size: 18, color: AppColors.textMuted),
              label: Text(
                'Skip — Use Online Mode',
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textMuted,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Active downloading view — progress bar
// ─────────────────────────────────────────────────────────────────────────────
class _DownloadingView extends ConsumerWidget {
  const _DownloadingView({required this.onDone});
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressAsync = ref.watch(downloadProgressProvider);

    return progressAsync.when(
      data: (progress) {
        // Navigate when done
        if (progress.isDone) {
          WidgetsBinding.instance.addPostFrameCallback((_) => onDone());
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated icon
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress.fraction),
                  duration: const Duration(milliseconds: 400),
                  builder: (_, value, _) => SizedBox(
                    width: 90,
                    height: 90,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: value,
                          strokeWidth: 5,
                          backgroundColor: AppColors.border,
                          valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                        ),
                        Text(
                          '${(value * 100).toInt()}%',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 36),

                Text(
                  progress.isDone ? 'Download Complete! 🎉' : 'Downloading Panoramas...',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    letterSpacing: -0.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),

                // Progress bar
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress.fraction),
                  duration: const Duration(milliseconds: 400),
                  builder: (_, value, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(100),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 8,
                      backgroundColor: AppColors.bgCard,
                      valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                Text(
                  progress.label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),

                if (progress.error != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    progress.error!,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: AppColors.crimson,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],

                const SizedBox(height: 32),
                Text(
                  'Keep the app open while downloading.\nYou can use offline mode next time.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: AppColors.textMuted,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      ),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(LucideIcons.alertCircle, color: AppColors.crimson, size: 52),
              const SizedBox(height: 16),
              Text('Download failed:\n$err',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary)),
              const SizedBox(height: 24),
              _GoldButton(label: 'Open Online Mode', icon: LucideIcons.wifi, onTap: onDone),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Small reusable widgets ───────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.accent),
          const SizedBox(width: 6),
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _GoldButton extends StatelessWidget {
  const _GoldButton({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.accent, AppColors.accentLight],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(label,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
