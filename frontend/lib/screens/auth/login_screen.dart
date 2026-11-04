import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import '../../core/storage/token_storage.dart';
import '../../core/theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  bool _rememberMe = false;

  String? _errorMessage;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

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

      if (response['status_code'] == 200) {
        final token = response['access_token'];

        if (token == null) {
          setState(() {
            _errorMessage = 'Invalid server response.';
          });
          return;
        }

        await TokenStorage.saveToken(token.toString());

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Login successful!'),
            backgroundColor: AppTheme.primaryGreen,
          ),
        );

        // Dashboard navigation will be added next.
      } else {
        setState(() {
          _errorMessage =
              response['detail']?.toString() ??
              'Login failed. Please try again.';
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage =
            'Unable to connect to the server. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.9, 0.7),
            radius: 1.3,
            colors: [
              Color(0x3325A98D),
              AppTheme.background,
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 850;

              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: Column(
                    children: [
                      _buildNavbar(),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 24 : 60,
                          vertical: isMobile ? 40 : 70,
                        ),
                        child: isMobile
                            ? Column(
                                children: [
                                  _buildIntroduction(isMobile),
                                  const SizedBox(height: 40),
                                  _buildLoginCard(),
                                ],
                              )
                            : Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: _buildIntroduction(isMobile),
                                  ),
                                  const SizedBox(width: 50),
                                  Expanded(
                                    child: Center(
                                      child: _buildLoginCard(),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      _buildFooter(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildNavbar() {
    return Container(
      height: 85,
      padding: const EdgeInsets.symmetric(horizontal: 35),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppTheme.borderColor,
          ),
        ),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/logo_peak.png',
            width: 55,
            height: 55,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 12),
          const Text(
            'PEAKGYM',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: AppTheme.primaryText,
            ),
          ),
          const Spacer(),
          if (MediaQuery.of(context).size.width > 500) ...[
            _navItem('About'),
            const SizedBox(width: 25),
            _navItem('Security'),
            const SizedBox(width: 25),
            _navItem('Help'),
          ],
        ],
      ),
    );
  }

  Widget _navItem(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: AppTheme.secondaryText,
        fontSize: 13,
      ),
    );
  }

  Widget _buildIntroduction(bool isMobile) {
    return Column(
      crossAxisAlignment: isMobile
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        const Text(
          'PEAKGYM MANAGEMENT',
          style: TextStyle(
            color: AppTheme.primaryGreen,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Manage your gym.\nKeep it moving.',
          textAlign: isMobile ? TextAlign.center : TextAlign.left,
          style: TextStyle(
            color: AppTheme.primaryText,
            fontSize: isMobile ? 40 : 58,
            fontWeight: FontWeight.w900,
            height: 1.05,
            letterSpacing: -2,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Your space for managing members, attendance, '
          'and everyday gym operations.',
          textAlign: isMobile ? TextAlign.center : TextAlign.left,
          style: const TextStyle(
            color: AppTheme.secondaryText,
            fontSize: 16,
            height: 1.7,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(
        maxWidth: 450,
      ),
      padding: const EdgeInsets.all(35),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        border: Border.all(
          color: AppTheme.borderColor,
        ),
        borderRadius: BorderRadius.circular(7),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Log In',
              style: TextStyle(
                color: AppTheme.primaryText,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Access your PeakGym management account.',
              style: TextStyle(
                color: AppTheme.secondaryText,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 30),

            const Text(
              'Username',
              style: TextStyle(
                color: AppTheme.primaryText,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 9),
            TextFormField(
              controller: _usernameController,
              style: const TextStyle(
                color: AppTheme.primaryText,
              ),
              decoration: const InputDecoration(
                hintText: 'Enter your username',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your username.';
                }
                return null;
              },
            ),

            const SizedBox(height: 20),

            const Text(
              'Password',
              style: TextStyle(
                color: AppTheme.primaryText,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 9),
            TextFormField(
              controller: _passwordController,
              obscureText: !_isPasswordVisible,
              style: const TextStyle(
                color: AppTheme.primaryText,
              ),
              decoration: InputDecoration(
                hintText: 'Enter your password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      _isPasswordVisible = !_isPasswordVisible;
                    });
                  },
                  icon: Icon(
                    _isPasswordVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
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

            const SizedBox(height: 12),

            Row(
              children: [
                SizedBox(
                  height: 35,
                  child: Checkbox(
                    value: _rememberMe,
                    activeColor: AppTheme.primaryGreen,
                    onChanged: (value) {
                      setState(() {
                        _rememberMe = value ?? false;
                      });
                    },
                  ),
                ),
                const Text(
                  'Remember me',
                  style: TextStyle(
                    color: AppTheme.secondaryText,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Please contact your gym administrator '
                          'for password assistance.',
                        ),
                      ),
                    );
                  },
                  child: const Text(
                    'Forgot password?',
                    style: TextStyle(
                      color: AppTheme.primaryGreen,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                style: const TextStyle(
                  color: AppTheme.errorColor,
                  fontSize: 12,
                ),
              ),
            ],

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      AppTheme.primaryGreen,
                      Color(0xFF75D69B),
                      AppTheme.accentYellow,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: AppTheme.background,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 21,
                          width: 21,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.background,
                          ),
                        )
                      : const Text(
                          'LOG IN',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                ),
              ),
            ),

            const SizedBox(height: 25),

            const Center(
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    color: AppTheme.secondaryText,
                    fontSize: 12,
                  ),
                  children: [
                    TextSpan(text: 'Need an account? '),
                    TextSpan(
                      text: 'Contact your gym administrator.',
                      style: TextStyle(
                        color: AppTheme.primaryGreen,
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 25,
        vertical: 25,
      ),
      child: const Column(
        children: [
          Text(
            '© 2026 PeakGym Fitness. All rights reserved.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.secondaryText,
              fontSize: 11,
            ),
          ),
          SizedBox(height: 7),
          Text(
            'Designed with passion for fitness.',
            style: TextStyle(
              color: AppTheme.secondaryText,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}