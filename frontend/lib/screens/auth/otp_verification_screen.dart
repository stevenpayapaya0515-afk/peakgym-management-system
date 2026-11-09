import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/registration_service.dart';
import '../../core/theme/app_theme.dart';
import 'login_screen.dart';

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({
    super.key,
    required this.registrationToken,
    required this.invitedEmail,
  });

  final String registrationToken;
  final String invitedEmail;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final _code = TextEditingController();
  Timer? _timer;
  int _secondsLeft = 180;
  int _resendWait = 60;
  bool _busy = false;
  bool _verified = false;
  bool _activated = false;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_secondsLeft > 0) _secondsLeft--;
        if (_resendWait > 0) _resendWait--;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
      setState(() => _error = 'Enter the six-digit code from your email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await RegistrationService.verifyOtp(
        widget.registrationToken,
        _code.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _verified = response['email_verified'] == true;
        _message = response['message']?.toString() ?? 'Email verified.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await RegistrationService.resendOtp(widget.registrationToken);
      if (!mounted) return;
      setState(() {
        _secondsLeft = 180;
        _resendWait = 60;
        _code.clear();
        _message = 'A new code was sent to your email.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _activate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await RegistrationService.activate(widget.registrationToken);
      if (!mounted) return;
      setState(() {
        _activated = true;
        _message = 'Your staff account is active. You can now log in.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PEAKGYM  /  Email Verification')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            width: 460,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderColor),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.mark_email_read_outlined,
                  color: AppTheme.primaryGreen,
                  size: 42,
                ),
                const SizedBox(height: 14),
                Text(
                  _activated
                      ? 'Registration complete'
                      : _verified
                      ? 'Email verified'
                      : 'Check your email',
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.invitedEmail,
                  style: const TextStyle(color: AppTheme.primaryGreen),
                ),
                const SizedBox(height: 20),
                if (!_verified) ...[
                  const Text(
                    'Enter the six-digit verification code sent to your inbox.',
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'Verification code',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Code expires in ${(_secondsLeft ~/ 60).toString().padLeft(2, '0')}:${(_secondsLeft % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(color: AppTheme.secondaryText),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy || _secondsLeft == 0 ? null : _verify,
                      child: const Text('Verify email OTP'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _busy || _resendWait > 0 ? null : _resend,
                    child: Text(
                      _resendWait > 0
                          ? 'Resend available in $_resendWait seconds'
                          : 'Resend OTP',
                    ),
                  ),
                ] else if (!_activated) ...[
                  const Text(
                    'Verification succeeded. Activate your staff account to finish.',
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _activate,
                      child: const Text('Activate staff account'),
                    ),
                  ),
                ] else ...[
                  const Text('Your account is ready.'),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (_) => false,
                      ),
                      child: const Text('Go to login'),
                    ),
                  ),
                ],
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _message!,
                      style: const TextStyle(color: AppTheme.primaryGreen),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppTheme.errorColor),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
