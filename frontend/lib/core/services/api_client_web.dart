import 'package:http/http.dart' as http;
import 'package:http/browser_client.dart';

// Required for browser cookies on API requests and Set-Cookie on OTP login.
http.Client createApiClient() => BrowserClient()..withCredentials = true;
