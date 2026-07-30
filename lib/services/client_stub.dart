import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _CookieClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  String? _cookie;
  bool _loaded = false;

  Future<void> _loadCookie() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _cookie = prefs.getString('session_cookie');
    _loaded = true;
  }

  Future<void> _saveCookie(String cookie) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('session_cookie', cookie);
  }

  Future<void> clearCookie() async {
    _cookie = null;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('session_cookie');
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await _loadCookie();

    if (_cookie != null) {
      request.headers['cookie'] = _cookie!;
    }

    final response = await _inner.send(request);

    final setCookie = response.headers['set-cookie'];
    if (setCookie != null) {
      // Directly pull out JSESSIONID regardless of how many other
      // cookies (like XSRF-TOKEN) are mixed in with it.
      final match = RegExp(r'JSESSIONID=[^;,]+').firstMatch(setCookie);
      if (match != null) {
        _cookie = match.group(0);
        await _saveCookie(_cookie!);
      }
    }

    return response;
  }
}

final _CookieClient _cookieClientInstance = _CookieClient();

http.Client createClient() => _cookieClientInstance;

Future<void> clearStoredCookie() async {
  await _cookieClientInstance.clearCookie();
}