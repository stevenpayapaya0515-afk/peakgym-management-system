import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/services/api_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/storage/token_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/action_feedback.dart';

class StaffSettings extends StatefulWidget {
  const StaffSettings({super.key});

  @override
  State<StaffSettings> createState() => _StaffSettingsState();
}

class _StaffSettingsState extends State<StaffSettings> {
  final _formKey = GlobalKey<FormState>();

  final _current = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirm = TextEditingController();

  final List<bool> _visible = [false, false, false];

  Map<String, dynamic>? _account;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  Timer? _timer;
  DateTime? _lockedUntil;
  int _remaining = 0;

  @override
  void initState() {
    super.initState();
    _loadAccount();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _current.dispose();
    _newPassword.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _loadAccount() async {
    setState(() {
      _loading = true;
      _error = null;
      _account = null;
    });

    try {
      final token = await TokenStorage.getToken();

      if (token == null || token.isEmpty) {
        throw Exception('Your session has expired. Please log in again.');
      }

      final response = await ApiService.get(
        '/auth/me',
        token: token,
      );

      if (response['status_code'] != 200) {
        throw Exception(
          response['detail']?.toString() ?? 'Unable to load your account.',
        );
      }

      if (response['role'] != 'staff') {
        throw Exception('This Settings page is for staff accounts.');
      }

      if (!mounted) return;

      setState(() {
        _account = response;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _startCooldown(int seconds) {
    if (!mounted || seconds <= 0) return;

    _timer?.cancel();
    _lockedUntil = DateTime.now().add(Duration(seconds: seconds));

    setState(() => _remaining = seconds);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final milliseconds =
          _lockedUntil!.difference(DateTime.now()).inMilliseconds;

      final remaining =
          milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();

      setState(() => _remaining = remaining);

      if (remaining == 0) timer.cancel();
    });
  }

  String? _validateNewPassword(String? value) {
    final password = value ?? '';
    final bytes = utf8.encode(password).length;

    if (bytes < 12 || bytes > 64) {
      return 'Use between 12 and 64 bytes.';
    }

    if (password.contains('\u0000')) {
      return 'Password contains an invalid character.';
    }

    if (!RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password) ||
        !RegExp(r'[^a-zA-Z0-9\s]').hasMatch(password)) {
      return 'Include uppercase, lowercase, a number, and a symbol.';
    }

    if (password == _current.text) {
      return 'Choose a password different from your current password.';
    }

    return null;
  }

  Future<void> _save() async {
    if (_saving || _remaining > 0) return;
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    final success = await ActionFeedback.run(
      context: context,
      actionKey: 'staff-change-password',
      loadingMessage: 'Updating your password...',
      successMessage: 'Password changed successfully. '
          'Use your new password the next time you log in.',
      action: () async {
        try {
          await SettingsService.changePassword(
            currentPassword: _current.text,
            newPassword: _newPassword.text,
            confirmPassword: _confirm.text,
          );
        } on PasswordChangeException catch (error) {
          if (error.retryAfter > 0) {
            _startCooldown(error.retryAfter);
          }
          rethrow;
        } catch (_) {
          throw Exception(
            'The password-change result could not be confirmed. '
            'If the connection was interrupted, try logging in with '
            'the new password before submitting again.',
          );
        }
      },
    );

    if (!mounted) return;

    if (success) {
      _formKey.currentState?.reset();
      _current.clear();
      _newPassword.clear();
      _confirm.clear();

      _timer?.cancel();
      _lockedUntil = null;

      setState(() {
        _remaining = 0;
        _visible.fillRange(0, _visible.length, false);
      });
    }

    setState(() => _saving = false);
  }

  BoxDecoration _decoration() {
    return BoxDecoration(
      color: AppTheme.cardBackground,
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: AppTheme.borderColor),
    );
  }

  Widget _accountDetail(String label, String value) {
    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.secondaryText,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _passwordField({
    required String label,
    required TextEditingController controller,
    required int index,
    required String? Function(String?) validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 9),
        TextFormField(
          controller: controller,
          enabled: !_saving,
          obscureText: !_visible[index],
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: [
            index == 0
                ? AutofillHints.password
                : AutofillHints.newPassword,
          ],
          textInputAction:
              index == 2 ? TextInputAction.done : TextInputAction.next,
          onFieldSubmitted: index == 2 ? (_) => _save() : null,
          validator: validator,
          decoration: InputDecoration(
            errorMaxLines: 3,
            suffixIcon: IconButton(
              tooltip: _visible[index] ? 'Hide password' : 'Show password',
              onPressed: _saving
                  ? null
                  : () {
                      setState(() {
                        _visible[index] = !_visible[index];
                      });
                    },
              icon: Icon(
                _visible[index]
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _passwordCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: _decoration(),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Change password',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 18),
              const Divider(color: AppTheme.borderColor),
              const SizedBox(height: 18),
              const Text(
                'Enter your current password to choose a new one.',
                style: TextStyle(
                  color: AppTheme.secondaryText,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: Column(
                  children: [
                    _passwordField(
                      label: 'Current password',
                      controller: _current,
                      index: 0,
                      validator: (value) {
                        return value == null || value.isEmpty
                            ? 'Enter your current password.'
                            : null;
                      },
                    ),
                    const SizedBox(height: 20),
                    _passwordField(
                      label: 'New password',
                      controller: _newPassword,
                      index: 1,
                      validator: _validateNewPassword,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Use 12–64 bytes with an uppercase letter, lowercase '
                      'letter, number, and symbol. Common English letters '
                      'and symbols use one byte each.',
                      style: TextStyle(
                        color: AppTheme.secondaryText,
                        fontSize: 11,
                        height: 1.7,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _passwordField(
                      label: 'Confirm new password',
                      controller: _confirm,
                      index: 2,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Confirm your new password.';
                        }

                        return value != _newPassword.text
                            ? 'The new passwords do not match.'
                            : null;
                      },
                    ),
                  ],
                ),
              ),
              if (_remaining > 0) ...[
                const SizedBox(height: 18),
                Text(
                  'Too many incorrect attempts. '
                  'Try again in $_remaining seconds.',
                  style: const TextStyle(color: AppTheme.errorColor),
                ),
              ],
              const SizedBox(height: 26),
              Align(
                alignment: Alignment.centerRight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: const LinearGradient(
                      colors: [
                        AppTheme.primaryGreen,
                        AppTheme.accentYellow,
                      ],
                    ),
                  ),
                  child: TextButton(
                    onPressed: _saving || _remaining > 0 ? null : _save,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.black,
                      disabledForegroundColor: Colors.black54,
                      minimumSize: const Size(160, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                    child: Text(
                      _remaining > 0
                          ? 'Wait ${_remaining}s'
                          : 'Change password',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;

        return SingleChildScrollView(
          padding: EdgeInsets.all(compact ? 22 : 42),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Settings',
                style: TextStyle(
                  fontSize: compact ? 30 : 40,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'View your account details and change your password.',
                style: TextStyle(
                  color: AppTheme.secondaryText,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 28),
              const Divider(color: AppTheme.borderColor),
              const SizedBox(height: 24),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_error != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _error!,
                      style: const TextStyle(color: AppTheme.errorColor),
                    ),
                    TextButton.icon(
                      onPressed: _loadAccount,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                )
              else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(26),
                  decoration: _decoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'My account',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryGreen.withValues(
                                alpha: 0.10,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Active',
                              style: TextStyle(
                                color: AppTheme.primaryGreen,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Divider(color: AppTheme.borderColor),
                      const SizedBox(height: 22),
                      Wrap(
                        spacing: 24,
                        runSpacing: 24,
                        children: [
                          _accountDetail(
                            'Username',
                            _account?['username']?.toString() ?? '',
                          ),
                          _accountDetail(
                            'Email',
                            _account?['email']?.toString() ?? '',
                          ),
                          _accountDetail('Role', 'Staff'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _passwordCard(),
              ],
            ],
          ),
        );
      },
    );
  }
}