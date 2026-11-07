import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class ActionFeedback {
  // Development testing only.
  // When enabled, each action fails once BEFORE contacting the backend.
  static const bool _simulateFailure =
      bool.fromEnvironment('SIMULATE_ACTION_FAILURE');

  static final Set<String> _failedActions = {};

  static Future<bool> run({
    required BuildContext context,
    required String actionKey,
    required String loadingMessage,
    required String successMessage,
    required Future<void> Function() action,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.70),
      builder: (_) => _ActionFeedbackDialog(
        loadingMessage: loadingMessage,
        successMessage: successMessage,
        action: () async {
          if (kDebugMode &&
              _simulateFailure &&
              _failedActions.add(actionKey)) {
            throw Exception(
              'Simulated failure. No request was sent to the server. '
              'Return to the form and submit again to test success.',
            );
          }

          await action();
        },
      ),
    );

    return result ?? false;
  }
}

enum _FeedbackStage {
  loading,
  success,
  error,
}

class _ActionFeedbackDialog extends StatefulWidget {
  const _ActionFeedbackDialog({
    required this.loadingMessage,
    required this.successMessage,
    required this.action,
  });

  final String loadingMessage;
  final String successMessage;
  final Future<void> Function() action;

  @override
  State<_ActionFeedbackDialog> createState() =>
      _ActionFeedbackDialogState();
}

class _ActionFeedbackDialogState
    extends State<_ActionFeedbackDialog> {
  _FeedbackStage _stage = _FeedbackStage.loading;
  String? _error;

  @override
  void initState() {
    super.initState();
    _execute();
  }

  Future<void> _execute() async {
    try {
      await widget.action();

      if (!mounted) return;

      setState(() {
        _stage = _FeedbackStage.success;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _stage = _FeedbackStage.error;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Widget _gradientButton(String label, VoidCallback onPressed) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        gradient: const LinearGradient(
          colors: [
            AppTheme.primaryGreen,
            AppTheme.accentYellow,
          ],
        ),
      ),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Colors.black,
          minimumSize: const Size(double.infinity, 46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loading = _stage == _FeedbackStage.loading;
    final successful = _stage == _FeedbackStage.success;

    final title = loading
        ? 'Please wait'
        : successful
            ? 'Successful!'
            : 'Unable to complete';

    final message = loading
        ? widget.loadingMessage
        : successful
            ? widget.successMessage
            : _error ?? 'Something went wrong. Please try again.';

    return PopScope(
      canPop: !loading,
      child: AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 24,
        ),
        contentPadding: const EdgeInsets.all(28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
          side: const BorderSide(
            color: AppTheme.borderColor,
          ),
        ),
        content: SizedBox(
          width: 384,
          child: SingleChildScrollView(
            child: Semantics(
              liveRegion: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (loading) ...[
                    const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: AppTheme.primaryGreen,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _stage == _FeedbackStage.error
                          ? AppTheme.errorColor
                          : AppTheme.primaryGreen,
                      fontSize: 23,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.secondaryText,
                      fontSize: 13,
                      height: 1.7,
                    ),
                  ),
                  if (!loading) ...[
                    const SizedBox(height: 24),
                    if (successful)
                      _gradientButton(
                        'Okay',
                        () => Navigator.pop(context, true),
                      )
                    else ...[
                      const Text(
                        'Retry returns you to the form. '
                        'If the connection was interrupted, check the '
                        'records before submitting again.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.secondaryText,
                          fontSize: 11,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _gradientButton(
                        'Retry',
                        () => Navigator.pop(context, false),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}