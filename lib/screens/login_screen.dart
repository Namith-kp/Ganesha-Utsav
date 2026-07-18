import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/auth_provider.dart';
import '../main.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController     = TextEditingController();
  final _formKey            = GlobalKey<FormState>();

  bool _isLoading    = false;
  bool _isLogin      = true;
  String? _errorMessage;

  // ── Animation controllers ──────────────────────────────────────────────────
  late AnimationController _blobCtrl;
  late AnimationController _cardCtrl;
  late Animation<double>   _cardSlide;
  late Animation<double>   _cardFade;

  @override
  void initState() {
    super.initState();

    // Blobs — slow, looping float
    _blobCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);

    // Card — one-shot slide-in from below
    _cardCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _cardSlide = Tween<double>(begin: 32, end: 0).animate(
      CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOutQuart),
    );
    _cardFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOut),
    );
    _cardCtrl.forward();
  }

  @override
  void dispose() {
    _blobCtrl.dispose();
    _cardCtrl.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final authService = ref.read(authServiceProvider);
      if (_isLogin) {
        await authService.signIn(
          _emailController.text.trim(),
          _passwordController.text.trim(),
        );
      } else {
        await authService.signUp(
          _emailController.text.trim(),
          _passwordController.text.trim(),
          _nameController.text.trim(),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() { _errorMessage = e.toString(); });
      }
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Stack(
        children: [
          // ── Animated background blobs ──────────────────────────────────────
          _AnimatedBlobs(controller: _blobCtrl),

          // ── Centred login card ─────────────────────────────────────────────
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: AnimatedBuilder(
                animation: _cardCtrl,
                builder: (context, child) => Opacity(
                  opacity: _cardFade.value,
                  child: Transform.translate(
                    offset: Offset(0, _cardSlide.value),
                    child: child,
                  ),
                ),
                child: _LoginCard(
                  formKey:            _formKey,
                  emailController:    _emailController,
                  passwordController: _passwordController,
                  nameController:     _nameController,
                  isLogin:            _isLogin,
                  isLoading:          _isLoading,
                  errorMessage:       _errorMessage,
                  onToggle: () => setState(() {
                    _isLogin = !_isLogin;
                    _errorMessage = null;
                  }),
                  onSubmit: _submit,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated floating blobs  (mirrors CSS .blob keyframes)
// ─────────────────────────────────────────────────────────────────────────────
class _AnimatedBlobs extends StatelessWidget {
  const _AnimatedBlobs({required this.controller});
  final Animation<double> controller;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = controller.value; // 0..1 and back
        return Stack(
          children: [
            // Blob 1 — orange/saffron, top-left
            Positioned(
              top:  -100 + (t * 20),
              left: -120 + (t * 30),
              child: _Blob(
                size: math.min(size.width * 0.7, 420),
                colors: [AppColors.saffron, AppColors.gold],
                opacity: 0.35,
                scale: 1 + t * 0.08,
              ),
            ),
            // Blob 2 — purple/indigo, bottom-right, delayed (offset t by 0.25)
            Positioned(
              bottom: -80 + (_delayed(t, 0.25) * 20),
              right:  -80 + (_delayed(t, 0.25) * 15),
              child: _Blob(
                size: math.min(size.width * 0.55, 320),
                colors: [AppColors.purple, AppColors.blue],
                opacity: 0.35,
                scale: 1 + _delayed(t, 0.25) * 0.08,
              ),
            ),
            // Blob 3 — crimson/amber, mid-right, delayed further
            Positioned(
              top:  size.height * 0.4 + (_delayed(t, 0.5) * 18),
              left: size.width  * 0.6 + (_delayed(t, 0.5) * 12),
              child: _Blob(
                size: math.min(size.width * 0.45, 260),
                colors: [AppColors.crimson, AppColors.amber],
                opacity: 0.30,
                scale: 1 + _delayed(t, 0.5) * 0.08,
              ),
            ),
          ],
        );
      },
    );
  }

  // Simulate CSS animation-delay by phase-shifting the value
  double _delayed(double t, double phase) {
    final v = (t + phase) % 1.0;
    // Mirror (triangle wave) to make it back-and-forth like `alternate`
    return v < 0.5 ? v * 2 : (1 - v) * 2;
  }
}

class _Blob extends StatelessWidget {
  const _Blob({
    required this.size,
    required this.colors,
    required this.opacity,
    required this.scale,
  });
  final double size;
  final List<Color> colors;
  final double opacity;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: opacity,
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 60, sigmaY: 60),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: colors),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Glassmorphism login card
// ─────────────────────────────────────────────────────────────────────────────
class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.nameController,
    required this.isLogin,
    required this.isLoading,
    required this.errorMessage,
    required this.onToggle,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController nameController;
  final bool isLogin;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onToggle;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xE012162B), // ~88% opaque bgCard
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.45),
              blurRadius: 40,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: AppColors.gold.withOpacity(0.08),
              blurRadius: 40,
              spreadRadius: -5,
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 48),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Logo ──────────────────────────────────────────────────────
              Text('🙏', style: GoogleFonts.inter(fontSize: 52)),
              const SizedBox(height: 12),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [AppColors.gold, AppColors.saffron],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ).createShader(bounds),
                child: Text(
                  'Ganesh Chanda Tracker',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isLogin ? 'Sign in to your team account' : 'Create a team account',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 36),

              // ── Name field (sign-up only) ──────────────────────────────────
              if (!isLogin) ...[
                _GlowField(
                  controller: nameController,
                  label: 'FULL NAME',
                  hint: 'Your name',
                  icon: Icons.person_outline,
                  validator: (v) => (v == null || v.isEmpty) ? 'Enter your name' : null,
                ),
                const SizedBox(height: 16),
              ],

              // ── Email ─────────────────────────────────────────────────────
              _GlowField(
                controller: emailController,
                label: 'EMAIL',
                hint: 'you@example.com',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                validator: (v) => (v == null || v.isEmpty) ? 'Enter your email' : null,
              ),
              const SizedBox(height: 16),

              // ── Password ──────────────────────────────────────────────────
              _GlowField(
                controller: passwordController,
                label: 'PASSWORD',
                hint: '••••••••',
                icon: Icons.lock_outline,
                obscureText: true,
                validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
              ),
              const SizedBox(height: 8),

              // ── Error message ─────────────────────────────────────────────
              SizedBox(
                height: 20,
                child: errorMessage != null
                    ? Text(
                        errorMessage!,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFFFF6B6B),
                        ),
                        textAlign: TextAlign.center,
                      )
                    : null,
              ),
              const SizedBox(height: 16),

              // ── Submit button ─────────────────────────────────────────────
              _GradientButton(
                label: isLogin ? 'LOGIN' : 'SIGN UP',
                isLoading: isLoading,
                onTap: onSubmit,
              ),
              const SizedBox(height: 20),

              // ── Toggle ────────────────────────────────────────────────────
              TextButton(
                onPressed: onToggle,
                child: Text(
                  isLogin
                      ? 'Need an account? Sign up'
                      : 'Already have an account? Login',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Input field with gold glow on focus
// ─────────────────────────────────────────────────────────────────────────────
class _GlowField extends StatefulWidget {
  const _GlowField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  @override
  State<_GlowField> createState() => _GlowFieldState();
}

class _GlowFieldState extends State<_GlowField> {
  final _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            letterSpacing: 0.06,
          ),
        ),
        const SizedBox(height: 7),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: _focused
                ? [BoxShadow(
                    color: AppColors.gold.withOpacity(0.2),
                    blurRadius: 12,
                    spreadRadius: 0,
                  )]
                : [],
          ),
          child: TextFormField(
            controller: widget.controller,
            focusNode: _focus,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            validator: widget.validator,
            style: GoogleFonts.inter(
              color: AppColors.textPrimary,
              fontSize: 15,
            ),
            decoration: InputDecoration(
              hintText: widget.hint,
              prefixIcon: Icon(widget.icon, size: 20),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Gold gradient button with press scale animation
// ─────────────────────────────────────────────────────────────────────────────
class _GradientButton extends StatefulWidget {
  const _GradientButton({
    required this.label,
    required this.isLoading,
    required this.onTap,
  });
  final String label;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  State<_GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<_GradientButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    );
    _scale = _pressCtrl;
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTapDown:   (_) => _pressCtrl.reverse(),
        onTapUp:     (_) { _pressCtrl.forward(); widget.onTap(); },
        onTapCancel: ()  => _pressCtrl.forward(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            gradient: widget.isLoading
                ? null
                : const LinearGradient(
                    colors: [AppColors.gold, AppColors.saffron],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
            color: widget.isLoading ? AppColors.bgCard : null,
            borderRadius: BorderRadius.circular(10),
            boxShadow: widget.isLoading
                ? []
                : [
                    BoxShadow(
                      color: AppColors.gold.withOpacity(0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          alignment: Alignment.center,
          child: widget.isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.gold,
                  ),
                )
              : Text(
                  widget.label,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: 0.04,
                  ),
                ),
        ),
      ),
    );
  }
}
