import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/password_recovery_service.dart';
import '../../core/theme/app_theme.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.onBackToLogin});

  final VoidCallback onBackToLogin;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _usernameController = TextEditingController();
  final _captchaController = TextEditingController();
  final _answerController = TextEditingController();
  final _confirmAnswerController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();

  Uint8List? _captchaBytes;
  String? _captchaId;
  String? _ticket;
  String? _proof;
  List<Map<String, dynamic>> _questions = [];
  int? _questionId;

  Timer? _timer;
  int _otpSeconds = 0;
  int _resendSeconds = 0;
  int _step = 0; // Identify, question, OTP, password, success
  bool _busy = false;
  bool _captchaLoading = false;
  bool _showNewPassword = false;
  bool _showConfirmation = false;
  bool _showAnswer = false;
  bool _showConfirmAnswer = false;
  String? _error;
  String? _info;

  static const _gradient = LinearGradient(
    colors: [AppTheme.primaryGreen, Color(0xFF75D69B), AppTheme.accentYellow],
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadCaptcha();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _usernameController.dispose();
    _captchaController.dispose();
    _answerController.dispose();
    _confirmAnswerController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _loadCaptcha() async {
    if (!mounted) return;
    setState(() {
      _captchaLoading = true;
      _captchaId = null;
      _captchaBytes = null;
      _captchaController.clear();
    });
    try {
      final response = await PasswordRecoveryService.getCaptcha();
      if (!mounted) return;
      final image = response['image']?.toString() ?? '';
      final id = response['challenge_id']?.toString() ?? '';
      if (response['status_code'] != 200 || id.isEmpty || image.isEmpty) {
        throw StateError('CAPTCHA unavailable');
      }
      setState(() {
        _captchaId = id;
        _captchaBytes = base64Decode(image.split(',').last);
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'CAPTCHA unavailable. Check FastAPI and refresh.');
      }
    } finally {
      if (mounted) setState(() => _captchaLoading = false);
    }
  }

  String _responseError(Map<String, dynamic> response) {
    final detail = response['detail'];
    if (detail is String && detail.isNotEmpty) return detail;
    return 'The request could not be completed. Please try again.';
  }

  Future<void> _identify() async {
    if (_busy) return;
    if (_usernameController.text.trim().isEmpty) {
      setState(() => _error = 'Enter your username.');
      return;
    }
    if (_captchaId == null || _captchaController.text.trim().length != 6) {
      setState(() => _error = 'Enter the six CAPTCHA characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final result = await PasswordRecoveryService.identify(
        username: _usernameController.text,
        captchaChallengeId: _captchaId!,
        captchaAnswer: _captchaController.text,
      );
      if (!mounted) return;
      if (result['status_code'] != 200 || result['recovery_ticket'] is! String) {
        setState(() => _error = _responseError(result));
        await _loadCaptcha();
        return;
      }
      final raw = result['questions'];
      if (raw is! List) throw StateError('Invalid security questions');
      final questions = raw.whereType<Map<String, dynamic>>().toList();
      if (questions.isEmpty) throw StateError('Security questions unavailable');
      setState(() {
        _ticket = result['recovery_ticket'] as String;
        _questions = questions;
        _questionId = questions.first['id'] as int;
        _step = 1;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to verify details. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _answerQuestion() async {
    if (_busy || _ticket == null || _questionId == null) return;
    if (_answerController.text.trim().isEmpty ||
        _answerController.text.trim().toLowerCase() !=
            _confirmAnswerController.text.trim().toLowerCase()) {
      setState(() => _error = 'Your Answer and Re-enter Answer must match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final answer = await PasswordRecoveryService.answerQuestion(
        recoveryTicket: _ticket!,
        questionId: _questionId!,
        answer: _answerController.text,
        confirmAnswer: _confirmAnswerController.text,
      );
      if (!mounted) return;
      if (answer['status_code'] != 200 || answer['recovery_proof'] is! String) {
        setState(() => _error = _responseError(answer));
        return;
      }
      _proof = answer['recovery_proof'] as String;
      _answerController.clear();
      _confirmAnswerController.clear();
      // Move forward even if the OTP resend cooldown is active; the user can
      // request the code again without re-answering the question.
      setState(() => _step = 2);
      // Send the OTP only after the backend has verified the answer.
      final code = await PasswordRecoveryService.requestCode(
        username: _usernameController.text,
        recoveryProof: _proof!,
      );
      if (!mounted) return;
      if (code['status_code'] != 200) {
        setState(() => _error = _responseError(code));
        return;
      }
      setState(() {
        _step = 2;
        _info = 'Check the registered email for your six-digit reset code.';
      });
      _startTimers();
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to continue recovery. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    final minutes = (total ~/ 60).toString().padLeft(2, '0');
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _resendCode() async {
    if (_busy || _resendSeconds > 0 || _proof == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final result = await PasswordRecoveryService.requestCode(
        username: _usernameController.text,
        recoveryProof: _proof!,
      );
      if (!mounted) return;
      if (result['status_code'] != 200) {
        setState(() => _error = _responseError(result));
        return;
      }
      _otpController.clear();
      setState(() => _info = 'If allowed by the resend limit, a new code was sent.');
      _startTimers();
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to request a new code.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_busy || _proof == null) return;
    if (!RegExp(r'^\d{6}$').hasMatch(_otpController.text.trim())) {
      setState(() => _error = 'Enter your six-digit reset code.');
      return;
    }
    if (_otpSeconds == 0) {
      setState(() => _error = 'Code expired. Request a fresh code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final result = await PasswordRecoveryService.verifyCode(
        username: _usernameController.text,
        recoveryProof: _proof!,
        code: _otpController.text,
      );
      if (!mounted) return;
      if (result['status_code'] != 200 || result['verified'] != true) {
        setState(() => _error = _responseError(result));
        return;
      }
      setState(() {
        _step = 3;
        _info = 'Code verified. Set a new password before it expires.';
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not verify code. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _passwordStrength(String password) {
    if (password.length < 11 || password.length > 64) return 'Weak';
    final types = [
      RegExp(r'[a-z]').hasMatch(password),
      RegExp(r'[A-Z]').hasMatch(password),
      RegExp(r'[0-9]').hasMatch(password),
      RegExp(r'[^a-zA-Z0-9]').hasMatch(password),
    ].where((v) => v).length;
    if (types < 3) return 'Weak';
    if (password.length >= 14 && types == 4) return 'Strong';
    return 'Medium';
  }

  Future<void> _completeReset() async {
    if (_busy || _proof == null) return;
    final password = _passwordController.text;
    if (_passwordStrength(password) == 'Weak') {
      setState(() => _error = 'Use 11–64 characters and at least three character types.');
      return;
    }
    if (password != _confirmationController.text) {
      setState(() => _error = 'Mismatch Password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final result = await PasswordRecoveryService.complete(
        username: _usernameController.text,
        recoveryProof: _proof!,
        code: _otpController.text,
        newPassword: password,
        confirmPassword: _confirmationController.text,
      );
      if (!mounted) return;
      if (result['status_code'] != 200) {
        setState(() => _error = _responseError(result));
        return;
      }
      _passwordController.clear();
      _confirmationController.clear();
      _otpController.clear();
      _proof = null;
      _ticket = null;
      _timer?.cancel();
      setState(() {
        _step = 4;
        _info = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to update password. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startOver() {
    if (_busy) return;
    _timer?.cancel();
    _answerController.clear();
    _confirmAnswerController.clear();
    _otpController.clear();
    _passwordController.clear();
    _confirmationController.clear();
    _proof = null;
    _ticket = null;
    setState(() {
      _step = 0;
      _error = null;
      _info = null;
      _otpSeconds = 0;
      _resendSeconds = 0;
    });
    _loadCaptcha();
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

  Widget _primaryButton(String label, VoidCallback action) => SizedBox(
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.background),
              )
            : Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    ),
  );

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffix,
    List<TextInputFormatter>? inputFormatters,
    int? maxLength,
    ValueChanged<String>? onChanged,
  }) => TextField(
    controller: controller,
    enabled: true,
    keyboardType: keyboardType,
    obscureText: obscure,
    inputFormatters: inputFormatters,
    maxLength: maxLength,
    onChanged: onChanged,
    style: const TextStyle(color: AppTheme.primaryText, fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      counterText: '',
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      suffixIcon: suffix,
    ),
  );

  @override
  Widget build(BuildContext context) {
    const titles = [
      'Forgot Password',
      'Security Question',
      'Verify Your Email',
      'Create New Password',
      'Password Updated',
    ];
    const subtitles = [
      'Enter your username and solve the CAPTCHA.',
      'Choose one of your three registration questions.',
      'Enter the six-digit code sent to your registered email.',
      'Choose a strong password for your account.',
      'Your password has been changed successfully.',
    ];
    final strength = _passwordStrength(_passwordController.text);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Image.asset('assets/logo_peak.png', width: 78, height: 78, fit: BoxFit.contain),
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
          style: const TextStyle(color: AppTheme.secondaryText, fontSize: 12, height: 1.5),
        ),
        const SizedBox(height: 20),
        if (_step < 4) ...[
          Row(
            children: List.generate(4, (index) => Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: index == 3 ? 0 : 7),
                decoration: BoxDecoration(
                  color: index <= _step ? AppTheme.primaryGreen : AppTheme.borderColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            )),
          ),
          const SizedBox(height: 23),
        ],
        if (_step == 0) ...[
          _label('Username'),
          _textField(controller: _usernameController, hint: 'Enter your username', maxLength: 50),
          const SizedBox(height: 17),
          _label('Security verification'),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF181C1F),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF39433F)),
            ),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: Container(
                    height: 82,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F7FA),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _captchaBytes == null
                        ? Center(
                            child: Text(
                              _captchaLoading ? 'Loading CAPTCHA...' : 'CAPTCHA unavailable',
                              style: const TextStyle(color: Colors.black54),
                            ),
                          )
                        : Image.memory(_captchaBytes!, fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  tooltip: 'Refresh CAPTCHA',
                  onPressed: _captchaLoading || _busy ? null : _loadCaptcha,
                  icon: const Icon(Icons.refresh_rounded, color: AppTheme.primaryGreen),
                ),
              ]),
              const SizedBox(height: 10),
              _textField(
                controller: _captchaController,
                hint: 'Enter the 6 characters above',
                maxLength: 6,
              ),
            ]),
          ),
          const SizedBox(height: 18),
          _primaryButton('CONTINUE', _identify),
        ],
        if (_step == 1) ...[
          _label('Choose the following question'),
          DropdownButtonFormField<int>(
            initialValue: _questionId,
            isExpanded: true,
            dropdownColor: AppTheme.cardBackground,
            style: const TextStyle(color: AppTheme.primaryText, fontSize: 13),
            items: _questions.map((q) => DropdownMenuItem<int>(
              value: q['id'] as int,
              child: Text(q['text']?.toString() ?? '', overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: _busy ? null : (value) => setState(() => _questionId = value),
          ),
          const SizedBox(height: 16),

          _label('Your Answer'),
          _textField(
            controller: _answerController,
            hint: 'Enter your registered answer',
            obscure: !_showAnswer,
            maxLength: 50,
            suffix: IconButton(
              tooltip: _showAnswer ? 'Hide answer' : 'Show answer',
              onPressed: () {
                setState(() {
                  _showAnswer = !_showAnswer;
                });
              },
              icon: Icon(
                _showAnswer
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: AppTheme.secondaryText,
              ),
            ),
          ),

          const SizedBox(height: 14),

          _label('Re-enter Answer'),
          _textField(
            controller: _confirmAnswerController,
            hint: 'Re-enter the same answer',
            obscure: !_showConfirmAnswer,
            maxLength: 50,
            suffix: IconButton(
              tooltip: _showConfirmAnswer ? 'Hide answer' : 'Show answer',
              onPressed: () {
                setState(() {
                  _showConfirmAnswer = !_showConfirmAnswer;
                });
              },
              icon: Icon(
                _showConfirmAnswer
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: AppTheme.secondaryText,
              ),
            ),
          ),

          const SizedBox(height: 18),
          _primaryButton('VERIFY SECURITY ANSWER', _answerQuestion),
        ],
        if (_step == 2) ...[
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
                : 'Code expired. Request a new one.',
            style: TextStyle(
              fontSize: 12,
              color: _otpSeconds > 0 ? AppTheme.secondaryText : AppTheme.errorColor,
            ),
          ),
          const SizedBox(height: 18),
          _primaryButton('VERIFY EMAIL OTP', _verifyCode),
          const SizedBox(height: 8),
          Center(child: TextButton(
            onPressed: _busy || _resendSeconds > 0 ? null : _resendCode,
            child: Text(
              _resendSeconds > 0 ? 'Resend code in $_resendSeconds s' : 'Resend verification code',
              style: const TextStyle(fontSize: 12),
            ),
          )),
        ],
        if (_step == 3) ...[
          _label('New password'),
          _textField(
            controller: _passwordController,
            hint: 'Enter a new password',
            obscure: !_showNewPassword,
            maxLength: 64,
            onChanged: (_) => setState(() {}),
            suffix: IconButton(
              tooltip: _showNewPassword ? 'Hide password' : 'Show password',
              onPressed: () => setState(() => _showNewPassword = !_showNewPassword),
              icon: Icon(_showNewPassword
                  ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            const Text('Password strength: ', style: TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
            Text(strength, style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: strength == 'Weak' ? AppTheme.errorColor : AppTheme.primaryGreen,
            )),
          ]),
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
                  ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            ),
          ),
          const SizedBox(height: 9),
          const Text(
            '11–64 characters; use at least three character types '
            '(uppercase, lowercase, numbers, symbols).',
            style: TextStyle(color: AppTheme.secondaryText, fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 18),
          _primaryButton('UPDATE PASSWORD', _completeReset),
        ],
        if (_step == 4) ...[
          const Center(child: Icon(Icons.check_circle_rounded, size: 66, color: AppTheme.primaryGreen)),
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
          Text(_info!, style: const TextStyle(color: AppTheme.primaryGreen, fontSize: 12, height: 1.45)),
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
            child: Text(_error!, style: const TextStyle(color: AppTheme.errorColor, fontSize: 12, height: 1.4)),
          ),
        ],
        if (_step != 4) ...[
          const SizedBox(height: 7),
          Center(child: TextButton(
            onPressed: _busy ? null : _startOver,
            child: const Text('Start over', style: TextStyle(fontSize: 12)),
          )),
          Center(child: TextButton(
            onPressed: _busy ? null : widget.onBackToLogin,
            child: const Text('Back to login', style: TextStyle(fontSize: 12, color: AppTheme.primaryGreen)),
          )),
        ],
      ],
    );
  }
}
