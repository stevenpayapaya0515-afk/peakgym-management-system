import 'dart:js_interop';

@JS('peakgymRegistrationHoneypotValue')
external JSString? _getRegistrationHoneypot();

/// Reads the genuine offscreen HTML field at submission time.
String registrationHoneypotValue() => _getRegistrationHoneypot()?.toDart ?? '';
