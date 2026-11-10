import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/password_recovery_service.dart';
import '../../core/theme/app_theme.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({
    super.key,
    required this.onBackToLogin,
  });

  final VoidCallback onBackToLogin;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();

  Timer? _timer;
  int _otpSeconds = 0;
  int _resendSeconds = 0;
  int _step = 0; // 0=email, 1=OTP, 2=new password, 3=complete
  bool _busy = false;
  bool _showNewPassword = false;
  bool _showConfirmation = false;
  String? _error;
  String? _info;

  static const _gradient = LinearGradient(
    colors: [AppTheme.primaryGreen, Color(0xFF75D69B), AppTheme.accentYellow],
  );

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  void _startTimers() {
    _timer?.cancel();
    setState(() {
      _otpSeconds = 180;
      _resendSeconds = 60;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_otpSeconds > 0) _otpSeconds--;
        if (_resendSeconds > 0) _resendSeconds--;
      });
      if (_otpSeconds == 0 && _resendSeconds == 0) timer.cancel();
    });
  }

  String _formatSeconds(int total) {
    final min = (total ~/ 60).toString().padLeft(2, '0');
    final sec = (total % 60).toString().padLeft(2, '0');
    return '$min:$sec';
  }

  String _responseError(Map<String, dynamic> response) {
    final detail = response['detail'];
    if (detail is String && detail.isNotEmpty) return detail;
    return 'Unable to complete the request. Please try again.';
  }

  Future<void> _requestCode() async {
    if (_busy) return;
    final email = _emailController.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final result = await PasswordRecoveryService.requestCode(email);
      if (!mounted) return;
      if (result['status_code'] != 200) {
        setState(() => _error = _responseError(result));
        return;
      }
      _otpController.clear();
      setState(() {
        _step = 1;
        _info = 'If this email belongs to an eligible PeakGym account, '
            'a reset code has been requested. Check your inbox or Spam.';
      });
      _startTimers();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to reach PeakGym. Check the backend connection.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_busy) return;
    if (!RegExp(r'^\d{6}$').hasMatch(_otpController.text.trim())) {
      setState(() => _error = 'Enter the six-digit code from your email.');
      return;
    }
    if (_otpSeconds == 0) {
      setState(() => _error = 'Code expired. Request a new one.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final result = await PasswordRecoveryService.verifyCode(
        email: _emailController.text,
        code: _otpController.text,
      );
      if (!mounted) return;
      if (result['status_code'] != 200 || result['verified'] != true) {
        setState(() => _error = _responseError(result));
        return;
      }
      setState(() {
        _step = 2;
        _info = 'Code verified. Set a new password before the code expires.';
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not verify the code. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completeReset() async {
    if (_busy) return;
    final password = _passwordController.text;
    final confirm = _confirmationController.text;
    if (password.length < 11 || password.length > 64) {
      setState(() => _error = 'Password must contain 11–64 characters.');
      return;
    }
    final types = [
      RegExp(r'[a-z]').hasMatch(password),
      RegExp(r'[A-Z]').hasMatch(password),
      RegExp(r'[0-9]').hasMatch(password),
      RegExp(r'[^a-zA-Z0-9]').hasMatch(password),
    ].where((x) => x).length;
    if (types < 3) {
      setState(() => _error = 'Use at least 3 character types: uppercase, lowercase, numbers or symbols.');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final result = await PasswordRecoveryService.complete(
        email: _emailController.text,
        code: _otpController.text,
        newPassword: password,
        confirmPassword: confirm,
      );
      if (!mounted) return;
      if (result['status_code'] != 200) {
        setState(() => _error = _responseError(result));
        return;
      }
      _passwordController.clear();
      _confirmationController.clear();
      _otpController.clear();
      _timer?.cancel();
      setState(() {
        _step = 3;
        _info = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to update password. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _backToEmail() {
    if (_busy) return;
    _timer?.cancel();
    _otpController.clear();
    _passwordController.clear();
    _confirmationController.clear();
    setState(() {
      _step = 0;
      _error = null;
      _info = null;
      _otpSeconds = 0;
      _resendSeconds = 0;
    });
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        color: AppTheme.primaryText,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _primaryButton(String label, VoidCallback action) {
    return SizedBox(
      height: 46,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: _gradient,
          borderRadius: BorderRadius.circular(10),
        ),
        child: ElevatedButton(
          onPressed: _busy ? null : action,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            foregroundColor: AppTheme.background,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.background,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffix,
    List<TextInputFormatter>? inputFormatters,
    int? maxLength,
  }) {
    return TextField(
      controller: controller,
      enabled: !_busy,
      keyboardType: keyboardType,
      obscureText: obscure,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      style: const TextStyle(color: AppTheme.primaryText, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        suffixIcon: suffix,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const titles = [
      'Forgot Password',
      'Verify Your Email',
      'Create New Password',
      'Password Updated',
    ];
    const subtitles = [
      'Enter the email associated with your PeakGym account.',
      'Enter the six-digit code sent to your email.',
      'Choose a strong password for your account.',
      'Your password has been changed successfully.',
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Image.asset(
            'assets/logo_peak.png',
            width: 78,
            height: 78,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 18),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => _gradient.createShader(bounds),
          child: Text(
            titles[_step],
            style: const TextStyle(
              color: Colors.white,
              fontSize: 27,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitles[_step],
          style: const TextStyle(
            color: AppTheme.secondaryText,
            fontSize: 12,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        if (_step < 3)
          Row(
            children: List.generate(3, (index) {
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: index == 2 ? 0 : 7),
                  decoration: BoxDecoration(
                    color: index <= _step
                        ? AppTheme.primaryGreen
                        : AppTheme.borderColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            }),
          ),
        if (_step < 3) const SizedBox(height: 23),
        if (_step == 0) ...[
          _label('Email address'),
          _textField(
            controller: _emailController,
            hint: 'Enter your registered email',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 22),
          _primaryButton('SEND RESET CODE', () => _requestCode()),
        ],
        if (_step == 1) ...[
          _label('Verification code'),
          _textField(
            controller: _otpController,
            hint: 'Enter 6-digit code',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 6,
          ),
          const SizedBox(height: 9),
          Text(
            _otpSeconds > 0
                ? 'Code expires in ${_formatSeconds(_otpSeconds)}'
                : 'Code expired. Request another code.',
            style: TextStyle(
              fontSize: 12,
              color: _otpSeconds > 0
                  ? AppTheme.secondaryText
                  : AppTheme.errorColor,
            ),
          ),
          const SizedBox(height: 18),
          _primaryButton('VERIFY EMAIL OTP', _verifyCode),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: _busy || _resendSeconds > 0
                  ? null
                  : _requestCode,
              child: Text(
                _resendSeconds > 0
                    ? 'Resend code in $_resendSeconds s'
                    : 'Resend verification code',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: _busy ? null : _backToEmail,
              child: const Text('Change email', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
        if (_step == 2) ...[
          _label('New password'),
          _textField(
            controller: _passwordController,
            hint: 'Enter a new password',
            obscure: !_showNewPassword,
            maxLength: 64,
            suffix: IconButton(
              tooltip: _showNewPassword ? 'Hide password' : 'Show password',
              onPressed: () => setState(() => _showNewPassword = !_showNewPassword),
              icon: Icon(_showNewPassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined),
            ),
          ),
          const SizedBox(height: 14),
          _label('Confirm new password'),
          _textField(
            controller: _confirmationController,
            hint: 'Re-enter the new password',
            obscure: !_showConfirmation,
            maxLength: 64,
            suffix: IconButton(
              tooltip: _showConfirmation ? 'Hide password' : 'Show password',
              onPressed: () => setState(() => _showConfirmation = !_showConfirmation),
              icon: Icon(_showConfirmation
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined),
            ),
          ),
          const SizedBox(height: 9),
          const Text(
            '11–64 characters; use at least three character types '
            '(uppercase, lowercase, numbers, symbols).',
            style: TextStyle(
              color: AppTheme.secondaryText,
              fontSize: 11,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          _primaryButton('UPDATE PASSWORD', _completeReset),
          const SizedBox(height: 7),
          Center(
            child: TextButton(
              onPressed: _busy ? null : _backToEmail,
              child: const Text('Start over', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
        if (_step == 3) ...[
          const Center(
            child: Icon(Icons.check_circle_rounded,
                size: 66, color: AppTheme.primaryGreen),
          ),
          const SizedBox(height: 18),
          const Text(
            'Your password has been updated. Please sign in using your new password.',
            style: TextStyle(color: AppTheme.secondaryText, height: 1.5),
          ),
          const SizedBox(height: 20),
          _primaryButton('BACK TO LOGIN', widget.onBackToLogin),
        ],
        if (_info != null) ...[
          const SizedBox(height: 13),
          Text(
            _info!,
            style: const TextStyle(
              color: AppTheme.primaryGreen,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 13),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0x22FF6B6B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x66FF6B6B)),
            ),
            child: Text(
              _error!,
              style: const TextStyle(
                color: AppTheme.errorColor,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
        if (_step != 3) ...[
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: _busy ? null : widget.onBackToLogin,
              child: const Text(
                'Back to login',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.primaryGreen,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
