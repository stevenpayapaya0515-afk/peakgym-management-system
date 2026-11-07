import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import '../../core/storage/token_storage.dart';
import '../../core/theme/app_theme.dart';
import '../admin/admin_dashboard.dart';
import '../public/public_navigation.dart';
import '../public/about_screen.dart';
import '../public/security_screen.dart';
import '../public/help_screen.dart';
import '../staff/staff_dashboard.dart';
import 'dart:async';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isContactHovered = false;
  bool _isPasswordVisible = false;
  bool _isLoading = false;
  String? _errorMessage;

  Timer? _lockoutTimer;
  DateTime? _lockoutEndsAt;
  int _lockoutSeconds = 0;

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _startLockoutCountdown(int seconds) {
    _lockoutTimer?.cancel();

    if (seconds <= 0) return;

    _lockoutEndsAt = DateTime.now().add(Duration(seconds: seconds));

    setState(() {
      _lockoutSeconds = seconds;
      _errorMessage =
          'Too many failed attempts. Try again in $seconds seconds.';
    });

    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final milliseconds =
          _lockoutEndsAt!.difference(DateTime.now()).inMilliseconds;
      final remaining = (milliseconds / 1000).ceil();

      if (remaining <= 0) {
        timer.cancel();

        setState(() {
          _lockoutSeconds = 0;
          _lockoutEndsAt = null;
          _errorMessage = null;
        });
        return;
      }

      setState(() {
        _lockoutSeconds = remaining;
        _errorMessage =
            'Too many failed attempts. Try again in $remaining seconds.';
      });
    });
  }

  Future<void> _login() async {
    if (_isLoading || _lockoutSeconds > 0) return;
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await AuthService.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      if (response['status_code'] != 200) {
        final message = response['detail']?.toString() ??
            'Login failed. Please try again.';

        final match = RegExp(
          r'try again in (\d+) seconds?',
          caseSensitive: false,
        ).firstMatch(message);

        final seconds = int.tryParse(match?.group(1) ?? '') ?? 0;

        if (seconds > 0) {
          _startLockoutCountdown(seconds);
        } else {
          setState(() {
            _errorMessage = message;
          });
        }

        return;
      }

      final token = response['access_token'];
      final user = response['user'];

      if (token is! String ||
          token.isEmpty ||
          user is! Map<String, dynamic>) {
        setState(() {
          _errorMessage = 'Invalid response from the server.';
        });
        return;
      }

      final role = user['role']?.toString().trim().toLowerCase();

      final Widget destination;

      if (role == 'admin') {
        destination = const AdminDashboard();
      } else if (role == 'staff') {
        destination = const StaffDashboard();
      } else {
        setState(() {
          _errorMessage =
              'This account does not have a supported role.';
        });
        return;
      }

      await TokenStorage.saveToken(token);

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => destination,
        ),
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _errorMessage =
            'Unable to complete login. Please check your connection '
            'and try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openPage(String page) {
    if (_isLoading) return;

    final Widget screen;

    switch (page) {
      case 'About':
        screen = const AboutScreen();
        break;
      case 'Security':
        screen = const SecurityScreen();
        break;
      case 'Help':
        screen = const HelpScreen();
        break;
      default:
        return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.background,
      drawer: PublicNavigation(
        onSelected: _openPage,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 960;

              return Image.asset(
                'assets/login_dumbbell.jpg',
                fit: BoxFit.cover,
                alignment: isDesktop
                    ? const Alignment(0.7, -0.65)
                    : Alignment.center,
                excludeFromSemantics: true,
                errorBuilder: (context, error, stackTrace) {
                  return const ColoredBox(
                    color: AppTheme.background,
                  );
                },
              );
            },
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xD9080D0B),
                  Color(0x66080D0B),
                  Color(0x99080D0B),
                ],
                stops: [0, 0.55, 1],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.bottomLeft,
                radius: 1.1,
                colors: [
                  Color(0x3300C9A7),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Fade the lower background on mobile.
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 960) {
                return const SizedBox.shrink();
              }

              return const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Color(0x990B0D0F),
                        AppTheme.background,
                      ],
                      stops: [0.55, 0.8, 1.0],
                    ),
                  ),
                  child: SizedBox.expand(),
                ),
              );
            },
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: _buildNavigation(),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isDesktop = constraints.maxWidth >= 960;
                      final sidePadding = isDesktop ? 48.0 : 20.0;

                      return SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              sidePadding,
                              isDesktop ? 8 : 28,
                              sidePadding,
                              12,
                            ),
                            child: Column(
                              mainAxisAlignment: isDesktop
                                  ? MainAxisAlignment.spaceBetween
                                  : MainAxisAlignment.start,
                              children: [
                                Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 1180,
                                    ),
                                    child: _buildContent(isDesktop),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 1180,
                                      ),
                                      child: _buildPageFooter(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(bool isDesktop) {
    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: _buildIntroduction(compact: false),
          ),
          const SizedBox(width: 56),
          SizedBox(
            width: 420,
            child: _buildLoginBox(),
          ),
        ],
      );
    }

    // Mobile: login box only, without the introduction.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: _buildLoginBox(),
      ),
    );
  }

  Widget _buildNavigation() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.borderColor,
          ),
        ),
        child: IconButton(
          tooltip: 'Open navigation menu',
          onPressed: _isLoading
              ? null
              : () => _scaffoldKey.currentState?.openDrawer(),
          icon: const Icon(
            Icons.menu_rounded,
            color: AppTheme.primaryText,
          ),
        ),
      ),
    );
  }

  Widget _buildIntroduction({required bool compact}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PEAKGYM MANAGEMENT',
          style: TextStyle(
            color: AppTheme.primaryGreen,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.5,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Manage your gym.',
          style: TextStyle(
            color: AppTheme.primaryText,
            fontSize: compact ? 34 : 52,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.5,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Keep it moving.',
          style: TextStyle(
            color: const Color(0xFFB7C8BF),
            fontSize: compact ? 34 : 52,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.5,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          width: 80,
          height: 4,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: const LinearGradient(
              colors: [
                AppTheme.primaryGreen,
                AppTheme.accentYellow,
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: const Text(
            'Your space for managing members, attendance, '
            'and everyday gym operations.',
            style: TextStyle(
              color: Color(0xFFD1D9D5),
              fontSize: 15,
              height: 1.8,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xF2131719),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF39433F),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 36,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: _buildLoginForm(),
    );
  }

  Widget _buildLoginForm() {
    const loginGradient = LinearGradient(
      colors: [
        AppTheme.primaryGreen,
        Color(0xFF75D69B),
        AppTheme.accentYellow,
      ],
    );

    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Image.asset(
                'assets/logo_peak.png',
                width: 96,
                height: 96,
                fit: BoxFit.contain,
                semanticLabel: 'PeakGym logo',
              ),
            ),
            const SizedBox(height: 15),

            // Same gradient as the login button.
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) {
                return loginGradient.createShader(bounds);
              },
              child: const Text(
                'Welcome Back',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(height: 4),

            const Text(
              'Access your PeakGym management account.',
              style: TextStyle(
                color: AppTheme.secondaryText,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),

            _buildFieldLabel('Username'),
            TextFormField(
              controller: _usernameController,
              readOnly: _isLoading,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(
                color: AppTheme.primaryText,
                fontSize: 14,
              ),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Enter your username',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                prefixIcon: Icon(
                  Icons.person_outline,
                  size: 20,
                ),
                prefixIconConstraints: BoxConstraints(
                  minWidth: 40,
                  minHeight: 44,
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your username.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),

            _buildFieldLabel('Password'),
            TextFormField(
              controller: _passwordController,
              readOnly: _isLoading,
              obscureText: !_isPasswordVisible,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              autocorrect: false,
              enableSuggestions: false,
              onFieldSubmitted: (_) => _login(),
              style: const TextStyle(
                color: AppTheme.primaryText,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Enter your password',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                prefixIcon: const Icon(
                  Icons.lock_outline,
                  size: 20,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 44,
                ),
                suffixIcon: IconButton(
                  tooltip: _isPasswordVisible
                      ? 'Hide password'
                      : 'Show password',
                  onPressed: _isLoading
                      ? null
                      : () {
                          setState(() {
                            _isPasswordVisible = !_isPasswordVisible;
                          });
                        },
                  icon: Icon(
                    _isPasswordVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your password.';
                }
                return null;
              },
            ),

            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _isLoading ? null : () => _openPage('Help'),
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(
                    color: AppTheme.primaryGreen,
                    fontSize: 12,
                  ),
                ),
              ),
            ),

            if (_errorMessage != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0x22FF6B6B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0x66FF6B6B),
                  ),
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: AppTheme.errorColor,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ),

            SizedBox(
              width: double.infinity,
              height: 46,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: loginGradient,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ElevatedButton(
                  onPressed:
                      (_isLoading || _lockoutSeconds > 0) ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: AppTheme.background,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.background,
                              ),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Logging in...',
                              style: TextStyle(
                                color: AppTheme.background,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        )
                      : const Text(
                          'LOG IN',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  const Text(
                    'Need an account?',
                    style: TextStyle(
                      color: AppTheme.secondaryText,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                  TextButton(
                    onPressed: _isLoading ? null : () => _openPage('Help'),
                    onHover: (hovered) {
                      setState(() {
                        _isContactHovered = hovered;
                      });
                    },
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: Colors.transparent,
                      overlayColor: Colors.transparent,
                      splashFactory: NoSplash.splashFactory,
                    ),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 150),
                      style: TextStyle(
                        color: _isContactHovered && !_isLoading
                            ? AppTheme.primaryGreen
                            : AppTheme.secondaryText,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                        decoration: TextDecoration.none,
                      ),
                      child: const Text('Contact your administrator.'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.primaryText,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPageFooter() {
    final copyright = Text(
      '© ${DateTime.now().year} PeakGym Fitness. All rights reserved.',
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Color(0xFFB0BAB5),
        fontSize: 11,
        height: 1.6,
      ),
    );

    const designCredit = Text(
      'Designed with passion for fitness',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Color(0xFFB0BAB5),
        fontSize: 11,
        height: 1.6,
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 18),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Color(0xFF39433F),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 700) {
            return Column(
              children: [
                copyright,
                const SizedBox(height: 6),
                designCredit,
              ],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              copyright,
              designCredit,
            ],
          );
        },
      ),
    );
  }
}