import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/security_questions_service.dart';
import '../../core/theme/app_theme.dart';

/// Staff-only Settings card. Answers are never saved in local storage.
class SecurityQuestionsCard extends StatefulWidget {
  const SecurityQuestionsCard({super.key});

  @override
  State<SecurityQuestionsCard> createState() => _SecurityQuestionsCardState();
}

class _SecurityQuestionsCardState extends State<SecurityQuestionsCard> {
  final _password = TextEditingController();
  final _otp = TextEditingController();
  final _q4 = TextEditingController();
  final _q7 = TextEditingController();
  final _q1 = TextEditingController();

  bool _busy = false;
  bool _codeSent = false;
  bool _showPassword = false;
  final _showAnswer = <bool>[false, false, false];
  String? _error;
  String? _success;

  @override
  void dispose() {
    _password.dispose();
    _otp.dispose();
    _q4.dispose();
    _q7.dispose();
    _q1.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_busy) return;
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your current password.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      await SecurityQuestionsService.requestCode(_password.text);
      if (!mounted) return;
      _password.clear();
      setState(() {
        _codeSent = true;
        _success = 'A 6-digit verification code was sent to your Gmail. '
            'It expires after 3 minutes.';
      });
    } on SecurityQuestionsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to request code. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _validateAnswers() {
    for (final answer in [_q4.text, _q7.text, _q1.text]) {
      final normalized = answer.trim();
      if (normalized.length < 2 || normalized.length > 50 ||
          !RegExp(r'^[A-Za-z]+(?: [A-Za-z]+)*$').hasMatch(normalized)) {
        return 'Each answer must have 2–50 letters, with single spaces only.';
      }
    }
    return null;
  }

  Future<void> _updateAnswers() async {
    if (_busy) return;
    if (!RegExp(r'^\d{6}$').hasMatch(_otp.text.trim())) {
      setState(() => _error = 'Enter your 6-digit Gmail verification code.');
      return;
    }
    final validation = _validateAnswers();
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      final response = await SecurityQuestionsService.updateAnswers(
        otpCode: _otp.text.trim(),
        q4: _q4.text.trim(),
        q7: _q7.text.trim(),
        q1: _q1.text.trim(),
      );
      if (!mounted) return;
      _otp.clear();
      _q4.clear();
      _q7.clear();
      _q1.clear();
      setState(() {
        _codeSent = false;
        _showAnswer.fillRange(0, _showAnswer.length, false);
        _success = response['message']?.toString() ??
            'Security questions updated successfully.';
      });
    } on SecurityQuestionsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Update could not be confirmed. '
            'Do not resubmit until you check the account.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _answerField(
    String label,
    TextEditingController controller,
    int index,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        obscureText: !_showAnswer[index],
        autocorrect: false,
        enableSuggestions: false,
        maxLength: 50,
        decoration: InputDecoration(
          labelText: label,
          counterText: '',
          suffixIcon: IconButton(
            tooltip: _showAnswer[index] ? 'Hide answer' : 'Show answer',
            onPressed: () => setState(() {
              _showAnswer[index] = !_showAnswer[index];
            }),
            icon: Icon(_showAnswer[index]
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Change security questions',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Divider(color: AppTheme.borderColor),
          const SizedBox(height: 14),
          const Text(
            'Forgot one of your registered answers? Verify your current '
            'password and a Gmail code to replace all three answers. '
            'Your existing account and password stay unchanged.',
            style: TextStyle(color: AppTheme.secondaryText, height: 1.5),
          ),
          const SizedBox(height: 22),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_codeSent) ...[
                  TextField(
                    controller: _password,
                    obscureText: !_showPassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Current password',
                      suffixIcon: IconButton(
                        tooltip: _showPassword ? 'Hide password' : 'Show password',
                        onPressed: () => setState(() => _showPassword = !_showPassword),
                        icon: Icon(_showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  TextField(
                    controller: _otp,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'Gmail verification code',
                      hintText: '6-digit OTP',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 16),
                  _answerField('Q4 — Mother\'s maiden first name', _q4, 0),
                  _answerField('Q7 — Elementary school name', _q7, 1),
                  _answerField('Q1 — First pet name', _q1, 2),
                  const Text(
                    'Use 2–50 letters and single spaces only. '
                    'Answers are hashed before storage.',
                    style: TextStyle(fontSize: 12, color: AppTheme.secondaryText),
                  ),
                  const SizedBox(height: 14),
                ],
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: AppTheme.errorColor)),
                  const SizedBox(height: 14),
                ],
                if (_success != null) ...[
                  Text(_success!,
                      style: const TextStyle(color: AppTheme.primaryGreen)),
                  const SizedBox(height: 14),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _busy
                        ? null
                        : _codeSent ? _updateAnswers : _sendCode,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_codeSent
                            ? 'UPDATE SECURITY ANSWERS'
                            : 'SEND GMAIL VERIFICATION CODE'),
                  ),
                ),
                if (_codeSent)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _codeSent = false;
                                _otp.clear();
                                _error = null;
                                _success = null;
                              }),
                      child: const Text('Start over / Request new code'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
