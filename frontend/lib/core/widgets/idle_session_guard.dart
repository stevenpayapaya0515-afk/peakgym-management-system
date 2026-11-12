import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../storage/token_storage.dart';
import '../theme/app_theme.dart';
import '../../screens/auth/login_screen.dart';

/// Tracks real user interaction and keeps a server-side idle session alive.
/// The server independently rejects expired sessions; this is only the UI layer.
class IdleSessionGuard extends StatefulWidget {
  const IdleSessionGuard({
    super.key,
    required this.child,
    required this.idleTimeoutSeconds,
    required this.warningBeforeSeconds,
  });

  final Widget child;
  final int idleTimeoutSeconds;
  final int warningBeforeSeconds;

  @override
  State<IdleSessionGuard> createState() => _IdleSessionGuardState();
}

class _IdleSessionGuardState extends State<IdleSessionGuard>
    with WidgetsBindingObserver {
  late final Timer _timer;
  DateTime _lastInteraction = DateTime.now();
  DateTime _lastServerTouch = DateTime.now();
  bool _warningVisible = false;
  bool _touching = false;
  bool _ending = false;
  int _secondsLeft = 0;

  int get _timeout => widget.idleTimeoutSeconds > 0
      ? widget.idleTimeoutSeconds
      : 480;

  int get _warningAt => (_timeout - widget.warningBeforeSeconds)
      .clamp(1, _timeout).toInt();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _checkIdle());
  }

  @override
  void dispose() {
    _timer.cancel();
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkIdle();
  }

  bool _onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _markInteraction();
    }
    return false; // Never consume keyboard events from form fields.
  }

  void _markInteraction() {
    if (_ending || _warningVisible || !mounted) return;
    final now = DateTime.now();
    // If the browser was suspended for longer than the timeout, expire first.
    if (now.difference(_lastInteraction).inMilliseconds >= _timeout * 1000) {
      unawaited(_endSession());
      return;
    }
    _lastInteraction = now;
    if (!_touching &&
        now.difference(_lastServerTouch) >= const Duration(seconds: 5)) {
      unawaited(_keepServerSessionAlive());
    }
  }

  Future<bool> _checkServerSession() async {
    try {
      final token = await TokenStorage.getToken();
      if (token == null || token.isEmpty) return false;
      final result = await ApiService.get('/auth/me', token: token)
          .timeout(const Duration(seconds: 8));
      if (result['status_code'] == 401 || result['status_code'] == 403) {
        unawaited(_endSession());
        return false;
      }
      return result['status_code'] == 200;
    } catch (_) {
      // Network failures are not an excuse to bypass server-side expiry.
      return false;
    }
  }

  Future<void> _keepServerSessionAlive() async {
    if (_touching || _ending) return;
    _touching = true;
    try {
      if (await _checkServerSession()) {
        _lastServerTouch = DateTime.now();
      }
    } finally {
      _touching = false;
    }
  }

  void _checkIdle() {
    if (_ending || !mounted) return;
    final idleMs = DateTime.now().difference(_lastInteraction).inMilliseconds;
    final left = (_timeout - (idleMs / 1000)).ceil();
    if (left <= 0) {
      unawaited(_endSession());
      return;
    }
    if (idleMs >= _warningAt * 1000) {
      setState(() {
        _warningVisible = true;
        _secondsLeft = left;
      });
    }
  }

  Future<void> _staySignedIn() async {
    if (_touching || _ending) return;
    _touching = true;
    final okay = await _checkServerSession();
    _touching = false;
    if (!mounted || _ending) return;
    if (okay) {
      setState(() {
        _lastInteraction = DateTime.now();
        _lastServerTouch = _lastInteraction;
        _warningVisible = false;
      });
    }
    // Without server confirmation the warning continues; expiry is enforced.
  }

  Future<void> _endSession() async {
    if (_ending) return;
    _ending = true;
    try {
      await TokenStorage.deleteToken();
    } catch (_) {
      // The server still rejects the session after its idle deadline.
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _markInteraction(),
      onPointerMove: (_) => _markInteraction(),
      onPointerHover: (_) => _markInteraction(),
      onPointerSignal: (_) => _markInteraction(),
      child: Stack(
        children: [
          widget.child,
          if (_warningVisible)
            Positioned.fill(
              child: ColoredBox(
                color: const Color(0xCC000000),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: Card(
                      color: AppTheme.cardBackground,
                      margin: const EdgeInsets.all(20),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.timer_outlined,
                                color: AppTheme.primaryGreen, size: 40),
                            const SizedBox(height: 12),
                            const Text('Session expiring',
                                style: TextStyle(
                                  color: AppTheme.primaryText,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                )),
                            const SizedBox(height: 10),
                            Text(
                              'You have been inactive. Automatic logout in '
                              '$_secondsLeft seconds.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: AppTheme.secondaryText),
                            ),
                            const SizedBox(height: 20),

                            SizedBox(
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
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: ElevatedButton(
                                  onPressed: _touching ? null : _staySignedIn,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    disabledBackgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    foregroundColor: AppTheme.background,
                                    overlayColor: const Color(0x26000000),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: Text(
                                    _touching
                                        ? 'Verifying session...'
                                        : 'STAY SIGNED IN',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
