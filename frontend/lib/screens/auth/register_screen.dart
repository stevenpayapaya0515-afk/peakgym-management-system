import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/registration_service.dart';
import '../../core/security/registration_honeypot.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/recaptcha_v2.dart';
import 'login_screen.dart';
import 'privacy_notice_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    required this.invitationToken,
    this.embedded = false,
    this.onBackToLogin,
  });

  final String invitationToken;
  final bool embedded;
  final VoidCallback? onBackToLogin;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final Map<String, TextEditingController> _fields = {};

  String? _invitedEmail;
  String? _error;
  String? _recaptchaToken;
  int _recaptchaResetCounter = 0;

  bool _loading = true;
  bool _submitting = false;
  bool _consent = false;
  bool _showPassword = false;

  String _position = 'Trainer';
  String _employment = 'Full-time';
  String? _extension;

  int _step = 0;
  bool _otpMode = false;

  String? _registrationToken;
  bool _otpBusy = false;
  bool _otpVerified = false;
  bool _accountActivated = false;

  String? _otpMessage;
  String? _otpError;

  DateTime? _otpExpiresAt;
  DateTime? _resendAllowedAt;
  Timer? _timer;

  int get _otpSeconds {
    if (_otpExpiresAt == null) return 0;

    final milliseconds = _otpExpiresAt!
        .difference(DateTime.now())
        .inMilliseconds;

    if (milliseconds <= 0) return 0;

    return (milliseconds / 1000).ceil();
  }

  int get _resendSeconds {
    if (_resendAllowedAt == null) return 0;

    final milliseconds = _resendAllowedAt!
        .difference(DateTime.now())
        .inMilliseconds;

    if (milliseconds <= 0) return 0;

    return (milliseconds / 1000).ceil();
  }

  TextEditingController _c(String name) {
    return _fields.putIfAbsent(name, TextEditingController.new);
  }

  @override
  void initState() {
    super.initState();

    if (widget.embedded) {
      _initialize();
    }
  }

  Future<void> _initialize() async {
    if (widget.invitationToken.isEmpty) {
      if (!mounted) return;

      setState(() {
        _error = 'A valid invitation link is required.';
        _loading = false;
      });

      return;
    }

    try {
      final result = await RegistrationService.validateInvitation(
        widget.invitationToken,
      );

      if (!mounted) return;

      final email = result['email']?.toString();

      if (email == null || email.isEmpty) {
        throw const RegistrationException(
          'The invitation does not contain a valid email.',
        );
      }

      setState(() {
        _invitedEmail = email;
        _loading = false;
      });

      await _refreshCaptcha();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refreshCaptcha() async {
    if (!mounted) return;
    setState(() {
      _recaptchaToken = null;
      _recaptchaResetCounter++;
    });
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }

    return null;
  }

  bool _validDate(String? value) {
    final text = value?.trim() ?? '';

    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
      return false;
    }

    final date = DateTime.tryParse(text);

    if (date == null) return false;

    final formatted =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

    return formatted == text;
  }

  String? _validateBirthdate(String? value) {
    if (!_validDate(value)) {
      return 'Enter a valid date: YYYY-MM-DD.';
    }

    final birth = DateTime.parse(value!.trim());
    final now = DateTime.now();

    var age = now.year - birth.year;

    if (now.month < birth.month ||
        (now.month == birth.month && now.day < birth.day)) {
      age--;
    }

    if (age < 18) {
      return 'Staff must be at least 18 years old.';
    }

    return null;
  }

  String? _validateDateHired(String? value) {
    if (!_validDate(value)) {
      return 'Enter a valid date: YYYY-MM-DD.';
    }

    final hired = DateTime.parse(value!.trim());
    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);

    if (hired.isAfter(today)) {
      return 'Date hired cannot be in the future.';
    }

    return null;
  }

  String? _validateAddressName(String? value) {
    final text = value?.trim() ?? '';
    if (text.length < 2 || text.length > 50) {
      return 'Use 2–50 characters.';
    }
    if (!RegExp(r'^[A-Za-z]+(?: [A-Za-z]+)*$').hasMatch(text)) {
      return 'Use letters and single spaces only.';
    }
    for (final word in text.split(' ')) {
      if (word.substring(0, 1) != word.substring(0, 1).toUpperCase() ||
          word.substring(1) != word.substring(1).toLowerCase()) {
        return 'Capitalize the first letter of each word.';
      }
    }
    return null;
  }

  String? _validateStreetAddress(String? value) {
    final text = value?.trim() ?? '';
    if (text.length < 3 || text.length > 50) {
      return 'Purok / Street must be 3–50 characters.';
    }
    return RegExp(r'^[A-Za-z0-9]+(?: [A-Za-z0-9]+)*$').hasMatch(text)
        ? null
        : 'Use letters, digits and single spaces only.';
  }

  String? _validatePostalCode(String? value) =>
      RegExp(r'^\d{4}$').hasMatch((value ?? '').trim())
          ? null
          : 'ZIP Code must contain exactly 4 digits.';

  Widget _field(
    String key,
    String label, {
    String? hint,
    bool optional = false,
    bool secret = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: _c(key),
      keyboardType: keyboardType,
      obscureText: secret && !_showPassword,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: const TextStyle(color: AppTheme.primaryText, fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        hintText: hint,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      validator: validator ?? (optional ? null : _required),
    );
  }

  Widget _section(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 17, bottom: 12),
          child: Text(
            title,
            style: const TextStyle(
              color: AppTheme.primaryText,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),

        ...items.map(
          (item) =>
              Padding(padding: const EdgeInsets.only(bottom: 13), child: item),
        ),
      ],
    );
  }

  Widget _logo() {
    return Center(
      child: Image.asset(
        'assets/logo_peak.png',
        width: 96,
        height: 96,
        fit: BoxFit.contain,
        semanticLabel: 'PeakGym logo',
      ),
    );
  }

  Widget _title(String text) {
    const gradient = LinearGradient(
      colors: [AppTheme.primaryGreen, Color(0xFF75D69B), AppTheme.accentYellow],
    );

    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        return gradient.createShader(bounds);
      },
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 27,
          fontWeight: FontWeight.w800,
          height: 1.15,
        ),
      ),
    );
  }

  Widget _primaryButton(
    String text,
    VoidCallback? onPressed, {
    bool loading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              AppTheme.primaryGreen,
              Color(0xFF75D69B),
              AppTheme.accentYellow,
            ],
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            foregroundColor: AppTheme.background,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.background,
                  ),
                )
              : Text(
                  text,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _errorMessage(String message) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0x22FF6B6B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x66FF6B6B)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: AppTheme.errorColor,
          fontSize: 12,
          height: 1.4,
        ),
      ),
    );
  }

  void _backToLogin() {
    if (_submitting || _otpBusy) return;

    if (widget.onBackToLogin != null) {
      widget.onBackToLogin!();
      return;
    }

    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  void _nextStep() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_step == 1 && _c('password').text != _c('confirm_password').text) {
      setState(() {
        _error = 'Passwords do not match.';
      });

      return;
    }

    setState(() {
      _error = null;
      _step++;
    });
  }

  void _previousStep() {
    if (_submitting) return;

    if (_step == 0) {
      _backToLogin();
      return;
    }

    setState(() {
      _error = null;
      _step--;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_consent) {
      setState(() {
        _error = 'You must accept the Privacy Notice.';
      });

      return;
    }

    if (_c('password').text != _c('confirm_password').text) {
      setState(() {
        _error = 'Passwords do not match.';
        _step = 1;
      });

      return;
    }

    if (_recaptchaToken == null || _recaptchaToken!.isEmpty) {
      setState(() => _error = 'Please check the I’m not a robot box.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final payload = <String, dynamic>{
      for (final key in [
        'id_number',
        'first_name',
        'family_name',
        'birthdate',
        'region',
        'province',
        'city_municipality',
        'barangay',
        'street_address',
        'postal_code',
        'username',
        'password',
        'confirm_password',
        'security_answer_q4',
        'security_answer_q7',
        'security_answer_q1',
        'date_hired',
        'emergency_contact_number',
      ])
        key: _c(key).text.trim(),

      'middle_name': _c('middle_name').text.trim().isEmpty
          ? null
          : _c('middle_name').text.trim(),

      'extension_name': _extension,
      'staff_position': _position,
      'employment_type': _employment,

      'country': 'Philippines',
      'privacy_consent': _consent,
      'website': registrationHoneypotValue(),

      'recaptcha_token': _recaptchaToken,
      'invitation_token': widget.invitationToken,
    };

    try {
      final response = await RegistrationService.start(payload);

      if (!mounted) return;

      final token = response['registration_token']?.toString() ?? '';

      if (token.isEmpty) {
        throw const RegistrationException(
          'Missing registration reference from server.',
        );
      }

      setState(() {
        _registrationToken = token;
        _otpMode = true;
        _otpVerified = false;
        _accountActivated = false;
        _otpError = null;
        _otpMessage = null;

        _otpExpiresAt = DateTime.now().add(const Duration(minutes: 3));

        _resendAllowedAt = DateTime.now().add(const Duration(seconds: 60));
      });

      _startOtpTimer();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
      });

      await _refreshCaptcha();
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  void _startOtpTimer() {
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {});
    });
  }

  Future<void> _verifyOtp() async {
    if (_otpBusy || _registrationToken == null) {
      return;
    }

    final code = _c('otp_code').text.trim();

    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _otpError = 'Enter the six-digit OTP from Gmail.';
      });

      return;
    }

    setState(() {
      _otpBusy = true;
      _otpError = null;
    });

    try {
      final response = await RegistrationService.verifyOtp(
        _registrationToken!,
        code,
      );

      if (!mounted) return;

      final verified = response['email_verified'] == true;

      setState(() {
        _otpVerified = verified;
        _otpMessage =
            response['message']?.toString() ??
            (verified
                ? 'Email verification successful.'
                : 'Verification not confirmed.');
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _otpError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _otpBusy = false;
        });
      }
    }
  }

  Future<void> _resendOtp() async {
    if (_otpBusy || _registrationToken == null || _resendSeconds > 0) {
      return;
    }

    setState(() {
      _otpBusy = true;
      _otpError = null;
    });

    try {
      await RegistrationService.resendOtp(_registrationToken!);

      if (!mounted) return;

      setState(() {
        _c('otp_code').clear();

        _otpExpiresAt = DateTime.now().add(const Duration(minutes: 3));

        _resendAllowedAt = DateTime.now().add(const Duration(seconds: 60));

        _otpMessage = 'A new verification code was sent.';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _otpError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _otpBusy = false;
        });
      }
    }
  }

  Future<void> _activateAccount() async {
    if (_otpBusy || _registrationToken == null || !_otpVerified) {
      return;
    }

    setState(() {
      _otpBusy = true;
      _otpError = null;
    });

    try {
      await RegistrationService.activate(_registrationToken!);

      if (!mounted) return;

      _timer?.cancel();

      setState(() {
        _accountActivated = true;
        _otpMessage =
            'Your staff account is active. '
            'You can now log in.';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _otpError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _otpBusy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();

    for (final controller in _fields.values) {
      controller.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // When opened through an existing /register route,
    // use the same login page and its existing modal.
    if (!widget.embedded) {
      return LoginScreen(initialInvitationToken: widget.invitationToken);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(right: 3),
          child: _otpMode ? _buildOtpContent() : _buildRegistrationContent(),
        );
      },
    );
  }

  Widget _buildRegistrationContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _logo(),

        const SizedBox(height: 15),

        _title('Staff Registration'),

        const SizedBox(height: 6),

        const Text(
          'Create your PeakGym staff account.',
          style: TextStyle(
            color: AppTheme.secondaryText,
            fontSize: 12,
            height: 1.5,
          ),
        ),

        const SizedBox(height: 18),

        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_invitedEmail == null) ...[
          _errorMessage(
            _error ?? 'A valid administrator invitation is required.',
          ),

          const Text(
            'Ask your administrator to invite '
            'your email address. Open the '
            'registration link received in Gmail.',
            style: TextStyle(
              color: AppTheme.secondaryText,
              fontSize: 12,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 18),

          _primaryButton('BACK TO LOGIN', _backToLogin),
        ] else ...[
          Text(
            'Invited email: $_invitedEmail',
            style: const TextStyle(
              color: AppTheme.primaryGreen,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 16),

          Row(
            children: List.generate(3, (index) {
              return Expanded(
                child: Container(
                  height: 4,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    color: index <= _step
                        ? AppTheme.primaryGreen
                        : AppTheme.borderColor,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              );
            }),
          ),

          const SizedBox(height: 12),

          Text(
            'Step ${_step + 1} of 3',
            style: const TextStyle(color: AppTheme.secondaryText, fontSize: 12),
          ),

          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_step == 0) _personalStep(),

                if (_step == 1) _accountStep(),

                if (_step == 2) _verificationStep(),

                if (_error != null) _errorMessage(_error!),

                const SizedBox(height: 12),

                if (_step < 2)
                  _primaryButton('CONTINUE', _nextStep)
                else
                  _primaryButton(
                    'SEND REGISTRATION OTP',
                    _submitting ? null : _submit,
                    loading: _submitting,
                  ),

                const SizedBox(height: 10),

                Center(
                  child: TextButton(
                    onPressed: _submitting ? null : _previousStep,
                    child: Text(
                      _step == 0 ? 'Back to Login' : 'Back to previous step',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _personalStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('Personal Information', [
          _field(
            'id_number',
            'Staff ID',
            hint: '2026-0001',
            validator: (v) => RegExp(r'^\d{4}-\d{4}$').hasMatch(v ?? '')
                ? null
                : 'Use xxxx-xxxx format.',
          ),

          _field('first_name', 'First name'),

          _field('middle_name', 'Middle name (optional)', optional: true),

          _field('family_name', 'Family name'),

          DropdownButtonFormField<String?>(
            initialValue: _extension,
            decoration: const InputDecoration(
              labelText: 'Name extension (optional)',
            ),
            items:
                <String?>[
                  null,
                  'Jr.',
                  'Sr.',
                  'I',
                  'II',
                  'III',
                  'IV',
                  'IX',
                  'X',
                ].map((value) {
                  return DropdownMenuItem<String?>(
                    value: value,
                    child: Text(value ?? 'None'),
                  );
                }).toList(),
            onChanged: (value) {
              setState(() {
                _extension = value;
              });
            },
          ),

          _field(
            'birthdate',
            'Birthdate',
            hint: 'YYYY-MM-DD',
            validator: _validateBirthdate,
          ),
        ]),

        _section('Address', [
          _field('region', 'Region', hint: 'Caraga'),

          _field(
            'province',
            'Province',
            hint: 'Agusan Del Norte',
            validator: _validateAddressName,
          ),

          _field(
            'city_municipality',
            'City / Municipality',
            hint: 'Cabadbaran City',
            validator: _validateAddressName,
          ),

          _field('barangay', 'Barangay', validator: _validateAddressName),

          _field(
            'street_address',
            'Purok / Street',
            validator: _validateStreetAddress,
          ),

          _field(
            'postal_code',
            'ZIP Code',
            hint: '8600',
            keyboardType: TextInputType.number,
            validator: _validatePostalCode,
          ),

          TextFormField(
            initialValue: 'Philippines',
            readOnly: true,
            decoration: const InputDecoration(labelText: 'Country'),
          ),
        ]),
      ],
    );
  }

  Widget _accountStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('PeakGym Employment Details', [
          DropdownButtonFormField<String>(
            initialValue: _position,
            decoration: const InputDecoration(labelText: 'Staff position'),
            items: ['Trainer', 'Receptionist', 'Maintenance', 'Manager'].map((
              value,
            ) {
              return DropdownMenuItem(value: value, child: Text(value));
            }).toList(),
            onChanged: (value) {
              setState(() {
                _position = value ?? _position;
              });
            },
          ),

          DropdownButtonFormField<String>(
            initialValue: _employment,
            decoration: const InputDecoration(labelText: 'Employment type'),
            items: ['Full-time', 'Part-time'].map((value) {
              return DropdownMenuItem(value: value, child: Text(value));
            }).toList(),
            onChanged: (value) {
              setState(() {
                _employment = value ?? _employment;
              });
            },
          ),

          _field(
            'date_hired',
            'Date hired',
            hint: 'YYYY-MM-DD',
            validator: _validateDateHired,
          ),

          _field(
            'emergency_contact_number',
            'Emergency mobile',
            hint: '09XXXXXXXXX',
            keyboardType: TextInputType.phone,
            validator: (v) =>
                RegExp(r'^(09\d{9}|\+639\d{9})$').hasMatch(v ?? '')
                ? null
                : 'Use 09XXXXXXXXX or +639XXXXXXXXX.',
          ),
        ]),

        _section('Login Credentials', [
          _field(
            'username',
            'Username',
            hint: '6–19 letters and numbers',
            validator: (v) =>
                RegExp(r'^[A-Za-z][A-Za-z0-9]{5,18}$').hasMatch(v ?? '')
                ? null
                : 'Start with a letter; use 6–19 letters/numbers.',
          ),

          _field(
            'password',
            'Password',
            secret: true,
            validator: (v) {
              final length = (v ?? '').length;

              if (length < 11 || length > 64) {
                return 'Password must contain 11–64 characters.';
              }

              return null;
            },
          ),

          _field(
            'confirm_password',
            'Confirm password',
            secret: true,
            validator: (v) {
              if ((v ?? '').isEmpty) {
                return 'Confirm your password.';
              }

              if (v != _c('password').text) {
                return 'Passwords do not match.';
              }

              return null;
            },
          ),

          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _showPassword,
            title: const Text('Show passwords'),
            onChanged: (value) {
              setState(() {
                _showPassword = value ?? false;
              });
            },
          ),
        ]),

        _section('Security Questions', [
          _field(
            'security_answer_q4',
            "Mother's maiden first name",
            secret: true,
          ),

          _field('security_answer_q7', 'Elementary school name', secret: true),

          _field('security_answer_q1', 'First pet name', secret: true),
        ]),
      ],
    );
  }

  Widget _verificationStep() {
    return _section('Verification', [
      RecaptchaV2(
        resetCounter: _recaptchaResetCounter,
        onTokenChanged: (token) {
          if (mounted) setState(() => _recaptchaToken = token);
        },
      ),
      const SizedBox(height: 12),

      TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const PrivacyNoticeScreen(),
          ),
        ),
        child: const Text('Read Privacy Notice (RA 10173)'),
      ),

      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _consent,
        title: const Text(
          'I agree to the Privacy Notice '
          'and registration data processing.',
          style: TextStyle(fontSize: 12),
        ),
        onChanged: (value) {
          setState(() {
            _consent = value ?? false;
          });
        },
      ),
    ]);
  }

  Widget _buildOtpContent() {
    final remaining = _otpSeconds;
    final minutes = (remaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (remaining % 60).toString().padLeft(2, '0');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _logo(),

        const SizedBox(height: 15),

        _title(
          _accountActivated
              ? 'Registration Complete'
              : _otpVerified
              ? 'Email Verified'
              : 'Verify Your Email',
        ),

        const SizedBox(height: 8),

        Text(
          _invitedEmail ?? '',
          style: const TextStyle(color: AppTheme.primaryGreen, fontSize: 12),
        ),

        const SizedBox(height: 18),

        if (!_otpVerified) ...[
          const Text(
            'Enter the six-digit code '
            'sent to your Gmail inbox.',
            style: TextStyle(
              color: AppTheme.secondaryText,
              fontSize: 12,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 14),

          TextField(
            controller: _c('otp_code'),
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: 'Verification code',
              counterText: '',
            ),
          ),

          const SizedBox(height: 10),

          Text(
            'Code expires in $minutes:$seconds',
            style: const TextStyle(color: AppTheme.secondaryText, fontSize: 12),
          ),

          const SizedBox(height: 18),

          _primaryButton(
            'VERIFY EMAIL OTP',
            (_otpBusy || remaining == 0) ? null : _verifyOtp,
            loading: _otpBusy,
          ),

          const SizedBox(height: 12),

          Center(
            child: TextButton(
              onPressed: (_otpBusy || _resendSeconds > 0) ? null : _resendOtp,
              child: Text(
                _resendSeconds > 0
                    ? 'Resend in $_resendSeconds seconds'
                    : 'Resend OTP',
              ),
            ),
          ),
        ] else if (!_accountActivated) ...[
          const Text(
            'Your email is verified. '
            'Activate your staff account '
            'to complete registration.',
            style: TextStyle(
              color: AppTheme.secondaryText,
              fontSize: 12,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 18),

          _primaryButton(
            'ACTIVATE STAFF ACCOUNT',
            _otpBusy ? null : _activateAccount,
            loading: _otpBusy,
          ),
        ] else ...[
          const Text(
            'Your PeakGym staff account '
            'is now ready to use.',
            style: TextStyle(
              color: AppTheme.secondaryText,
              fontSize: 12,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 18),

          _primaryButton('BACK TO LOGIN', _backToLogin),
        ],

        if (_otpMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _otpMessage!,
              style: const TextStyle(
                color: AppTheme.primaryGreen,
                fontSize: 12,
              ),
            ),
          ),

        if (_otpError != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _errorMessage(_otpError!),
          ),
      ],
    );
  }
}
