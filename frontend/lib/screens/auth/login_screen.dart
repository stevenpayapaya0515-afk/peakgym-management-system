import 'dart:async';

import 'package:flutter/material.dart';

import 'register_screen.dart';
import 'forgot_password_screen.dart';
import '../../core/services/auth_service.dart';
import '../../core/widgets/recaptcha_v2.dart';
import '../../core/storage/token_storage.dart';
import '../../core/theme/app_theme.dart';
import '../admin/admin_dashboard.dart';
import '../public/public_navigation.dart';
import '../public/about_screen.dart';
import '../public/security_screen.dart';
import '../public/help_screen.dart';
import '../staff/staff_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.initialInvitationToken});

  final String? initialInvitationToken;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final FocusNode _passwordFocusNode = FocusNode();
  final _otpController = TextEditingController();

  String? _recaptchaToken;
  int _recaptchaResetCounter = 0;
  bool _otpMode = false;

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  String? _errorMessage;

  bool _showRegistration = false;
  bool _showForgotPassword = false;
  String _invitationToken = '';

  Timer? _lockoutTimer;
  DateTime? _lockoutEndsAt;
  int _lockoutSeconds = 0;

  @override
  void initState() {
    super.initState();

    final uri = Uri.base;

    if (widget.initialInvitationToken != null) {
      _invitationToken = widget.initialInvitationToken!;
      _showRegistration = true;
    } else if (uri.path == '/register') {
      _invitationToken = uri.queryParameters['invite'] ?? '';
      _showRegistration = true;
    }

    if (!_showRegistration) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshLoginCaptcha();
      });
    }
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _openRegistration() {
    if (_isLoading) return;

    setState(() {
      _showRegistration = true;
    });
  }

  void _returnToLogin() {
    if (!mounted) return;

    setState(() {
      _showRegistration = false;
      _otpMode = false;
      _errorMessage = null;
    });
    _refreshLoginCaptcha();
  }

  Future<void> _refreshLoginCaptcha() async {
    if (!mounted) return;
    setState(() {
      _recaptchaToken = null;
      _recaptchaResetCounter++;
    });
  }

  void _backFromLoginOtp() {
    if (_isLoading) return;
    setState(() {
      _otpMode = false;
      _errorMessage = null;
      _otpController.clear();
    });
    _refreshLoginCaptcha();
  }

  void _openForgotPassword() {
    if (_isLoading) return;
    setState(() {
      _showForgotPassword = true;
      _errorMessage = null;
    });
  }

  void _returnFromForgotPassword() {
    if (!mounted) return;
    setState(() {
      _showForgotPassword = false;
      _errorMessage = null;
      _passwordController.clear();
    });
    _refreshLoginCaptcha();
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

      final milliseconds = _lockoutEndsAt!
          .difference(DateTime.now())
          .inMilliseconds;

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

    final captchaToken = _recaptchaToken;
    if (captchaToken == null || captchaToken.isEmpty) {
      setState(() => _errorMessage = 'Please check the I’m not a robot box.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    bool refreshCaptcha = false;
    try {
      final response = await AuthService.startLogin(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        recaptchaToken: captchaToken,
      );
      if (!mounted) return;
      refreshCaptcha = true; // A CAPTCHA is single-use on every login attempt.

      if (response['status_code'] != 200) {
        final message = response['detail']?.toString() ?? 'Login failed.';
        final match = RegExp(
          r'(?:try again in|locked for) (\d+) seconds?',
          caseSensitive: false,
        ).firstMatch(message);
        final seconds = int.tryParse(match?.group(1) ?? '') ?? 0;
        if (seconds > 0) {
          _startLockoutCountdown(seconds);
        } else {
          setState(() => _errorMessage = message);
        }
        return;
      }

      if (response['otp_required'] != true) {
        setState(() => _errorMessage = 'Unexpected login response.');
        return;
      }
      refreshCaptcha = false; // OTP is now the active step.
      _passwordController.clear();
      _otpController.clear();
      setState(() {
        _otpMode = true;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      refreshCaptcha = true;
      setState(() {
        _errorMessage = 'Unable to complete login. Check your connection.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }

      if (refreshCaptcha && mounted) {
        await _refreshLoginCaptcha();
      }

      if (mounted &&
          !_otpMode &&
          !_showRegistration &&
          !_showForgotPassword) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_otpMode) {
            _passwordFocusNode.requestFocus();
          }
        });
      }
    }
  }

  Future<void> _verifyLoginOtp() async {
    if (_isLoading || !_otpMode) return;
    if (!RegExp(r'^\d{6}$').hasMatch(_otpController.text.trim())) {
      setState(() => _errorMessage = 'Enter the six-digit email code.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await AuthService.verifyLoginOtp(
        username: _usernameController.text.trim(),
        otpCode: _otpController.text.trim(),
      );
      if (!mounted) return;
      if (response['status_code'] != 200) {
        setState(() => _errorMessage = response['detail']?.toString() ??
            'Invalid or expired verification code.');
        return;
      }

      final token = response['access_token'];
      final user = response['user'];
      if (token is! String || token.isEmpty || user is! Map<String, dynamic>) {
        setState(() => _errorMessage = 'Invalid server response.');
        return;
      }

      final role = user['role']?.toString().trim().toLowerCase();
      final Widget destination;
      if (role == 'admin') {
        destination = const AdminDashboard();
      } else if (role == 'staff') {
        destination = const StaffDashboard();
      } else {
        setState(() => _errorMessage = 'Unsupported account role.');
        return;
      }

      await TokenStorage.saveToken(token);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => destination),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Unable to verify OTP. Try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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

    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.background,
      drawer: PublicNavigation(onSelected: _openPage),
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
                  return const ColoredBox(color: AppTheme.background);
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
                colors: [Color(0x3300C9A7), Colors.transparent],
              ),
            ),
          ),

          // Original mobile background fade.
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
          Expanded(child: _buildIntroduction(compact: false)),
          const SizedBox(width: 56),
          SizedBox(width: 420, child: _buildLoginBox()),
        ],
      );
    }

    // Original mobile layout: card only.
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
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: IconButton(
          tooltip: 'Open navigation menu',
          onPressed: _isLoading
              ? null
              : () => _scaffoldKey.currentState?.openDrawer(),
          icon: const Icon(Icons.menu_rounded, color: AppTheme.primaryText),
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
              colors: [AppTheme.primaryGreen, AppTheme.accentYellow],
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
      decoration: BoxDecoration(
        color: const Color(0xF2131719),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF39433F)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 36,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: _showRegistration
            ? ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: (MediaQuery.sizeOf(context).height * 0.74).clamp(
                    300.0,
                    700.0,
                  ),
                ),
                child: RegisterScreen(
                  key: ValueKey(_invitationToken),
                  invitationToken: _invitationToken,
                  embedded: true,
                  onBackToLogin: _returnToLogin,
                ),
              )
            : _showForgotPassword
                ? ForgotPasswordScreen(
                    onBackToLogin: _returnFromForgotPassword,
                  )
                : _otpMode
                    ? _buildLoginOtpForm()
                    : _buildLoginForm(),
      ),
    );
  }

  Widget _buildLoginOtpForm() {
    const loginGradient = LinearGradient(
      colors: [AppTheme.primaryGreen, Color(0xFF75D69B), AppTheme.accentYellow],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Image.asset(
              'assets/logo_peak.png',
              width: 78,
              height: 78,
              fit: BoxFit.contain,
            ),
          ),
        ),

        const SizedBox(height: 18),

        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => loginGradient.createShader(bounds),
          child: const Text(
            'Verify Your Login',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ),

        const SizedBox(height: 8),

        const Text(
          'Enter the six-digit code sent to your account email. '
          'It expires after 3 minutes.',
          style: TextStyle(
            color: AppTheme.secondaryText,
            fontSize: 12,
            height: 1.5,
          ),
        ),

        const SizedBox(height: 18),

        _buildFieldLabel('Email verification code'),

        TextField(
          controller: _otpController,
          enabled: !_isLoading,
          keyboardType: TextInputType.number,
          maxLength: 6,
          style: const TextStyle(
            color: AppTheme.primaryText,
            fontSize: 14,
          ),
          decoration: const InputDecoration(
            counterText: '',
            hintText: 'Enter the 6-digit OTP code',
            contentPadding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
          ),
        ),

        const SizedBox(height: 10),

        if (_errorMessage != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0x22FF6B6B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x66FF6B6B)),
            ),
            child: Text(
              _errorMessage!,
              style: const TextStyle(
                color: AppTheme.errorColor,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),

        SizedBox(
          width: double.infinity,
          height: 46,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: loginGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: ElevatedButton(
              onPressed: _isLoading ? null : _verifyLoginOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                disabledBackgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: AppTheme.background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
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
                          'Verifying...',
                          style: TextStyle(
                            color: AppTheme.background,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    )
                  : const Text(
                      'VERIFY OTP',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
            ),
          ),
        ),

        const SizedBox(height: 10),

        Center(
          child: TextButton(
            onPressed: _isLoading ? null : _backFromLoginOtp,
            child: const Text(
              'Back to login',
              style: TextStyle(
                color: AppTheme.primaryGreen,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCaptcha() {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFieldLabel('Security verification'),
          const SizedBox(height: 8),
          RecaptchaV2(
            resetCounter: _recaptchaResetCounter,
            onTokenChanged: (token) {
              if (mounted) setState(() => _recaptchaToken = token);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLoginForm() {
    const loginGradient = LinearGradient(
      colors: [AppTheme.primaryGreen, Color(0xFF75D69B), AppTheme.accentYellow],
    );

    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Image.asset(
                  'assets/logo_peak.png',
                  width: 78,
                  height: 78,
                  fit: BoxFit.contain,
                  semanticLabel: 'PeakGym logo',
                ),
              ),
            ),

            const SizedBox(height: 18),

            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) {
                return loginGradient.createShader(bounds);
              },
              child: const Text(
                'Welcome Back',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Access your PeakGym management account.',
              style: TextStyle(
                color: AppTheme.secondaryText,
                fontSize: 12,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 20),

            _buildFieldLabel('Username'),
            TextFormField(
              controller: _usernameController,
              readOnly: false,
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
                  vertical: 14,
                ),
                prefixIcon: Icon(Icons.person_outline, size: 20),
                prefixIconConstraints: BoxConstraints(
                  minWidth: 42,
                  minHeight: 46,
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your username.';
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            _buildFieldLabel('Password'),
            TextFormField(
              controller: _passwordController,
              focusNode: _passwordFocusNode,
              readOnly: false,
              onTap: () {
                if (!_passwordFocusNode.hasFocus) {
                  _passwordFocusNode.requestFocus();
                }
              },
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
                  vertical: 14,
                ),
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 42,
                  minHeight: 46,
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

            _buildLoginCaptcha(),

            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isLoading ? null : _openForgotPassword,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 0),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Forgot password?',
                    style: TextStyle(
                      color: AppTheme.primaryGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),

            if (_errorMessage != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0x22FF6B6B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x66FF6B6B)),
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: AppTheme.errorColor,
                      fontSize: 12,
                      height: 1.45,
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
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ElevatedButton(
                  onPressed: (_isLoading || _lockoutSeconds > 0)
                      ? null
                      : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: AppTheme.background,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
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

            const SizedBox(height: 18),

            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                runSpacing: 2,
                children: [
                  const Text(
                    'Invited by your administrator?',
                    style: TextStyle(
                      color: AppTheme.secondaryText,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                  TextButton(
                    onPressed: _isLoading ? null : _openRegistration,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: Colors.transparent,
                      overlayColor: Colors.transparent,
                      splashFactory: NoSplash.splashFactory,
                    ),
                    child: const Text(
                      'Register here',
                      style: TextStyle(
                        color: AppTheme.primaryGreen,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.none,
                      ),
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
      style: TextStyle(color: Color(0xFFB0BAB5), fontSize: 11, height: 1.6),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF39433F))),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 700) {
            return Column(
              children: [copyright, const SizedBox(height: 6), designCredit],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [copyright, designCredit],
          );
        },
      ),
    );
  }
}
