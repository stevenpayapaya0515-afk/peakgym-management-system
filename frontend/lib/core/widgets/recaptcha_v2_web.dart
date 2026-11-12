import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

@JS('peakgymRecaptchaMount')
external void _mountRecaptcha(
  web.HTMLElement host,
  JSString siteKey,
  JSFunction onSuccess,
  JSFunction onExpired,
  JSFunction onError,
);

@JS('peakgymRecaptchaReset')
external void _resetRecaptcha(web.HTMLElement host);

class RecaptchaV2 extends StatefulWidget {
  const RecaptchaV2({
    super.key,
    required this.onTokenChanged,
    this.resetCounter = 0,
  });

  final ValueChanged<String?> onTokenChanged;
  final int resetCounter;

  @override
  State<RecaptchaV2> createState() => _RecaptchaV2State();
}

class _RecaptchaV2State extends State<RecaptchaV2> {
  static const _siteKey = String.fromEnvironment(
    'RECAPTCHA_SITE_KEY',
    defaultValue: '6LcAoBwuAAAAADlW21aiWjZT1ItkwuFGNkbfpPBy',
  );
  web.HTMLElement? _host;
  late final Widget _embeddedView;

  @override
  void initState() {
    super.initState();
    // Keep the same HTML view across parent setState calls (token changes).
    _embeddedView = HtmlElementView.fromTagName(
      tagName: 'div',
      onElementCreated: _attach,
    );
  }

  @override
  void didUpdateWidget(covariant RecaptchaV2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetCounter != widget.resetCounter && _host != null) {
      _resetRecaptcha(_host!);
    }
  }

  void _attach(Object element) {
    final host = element as web.HTMLElement;
    _host = host;
    _mountRecaptcha(
      host,
      _siteKey.toJS,
      ((JSString value) {
        if (mounted) widget.onTokenChanged(value.toDart);
      }).toJS,
      (() {
        if (mounted) widget.onTokenChanged(null);
      }).toJS,
      (() {
        if (mounted) widget.onTokenChanged(null);
      }).toJS,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_siteKey.isEmpty) {
      return const Text(
        'reCAPTCHA site key not configured. See setup instructions.',
        style: TextStyle(color: Colors.redAccent, fontSize: 12),
      );
    }
    // Fill the form field width. Google's iframe itself uses its supported
    // normal (304px) or compact (164px) width; the JS bridge chooses based on
    // the real available width, so the checkbox is not stretched or clipped.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF181C1F),
        border: Border.all(color: const Color(0xFF39433F)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 80,
        child: _embeddedView,
      ),
    );
  }
}
