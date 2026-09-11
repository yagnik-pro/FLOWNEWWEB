import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../theme.dart';

/// Meesho's edge returns 403 to plain HTTP clients — even for the login page.
/// A WebView is a real browser, so it is never blocked. Everything therefore
/// runs through one:
///
///   * [login]   — opens the panel login page in a sheet, fills the form, and
///                 hands back that account's cookies once the redirect happens.
///                 If Meesho asks for a captcha or SMS-OTP the sheet is already
///                 on screen, so the person just finishes it.
///   * [apiCall] — runs `fetch()` inside a hidden WebView. The request carries
///                 the real cookies and browser fingerprint, so the WAF leaves
///                 it alone. A fetch is just an XHR — well under a second.
///
/// Android's WebView cookie store is global, so accounts are processed one at a
/// time: clear cookies → inject this account's → do the work → save them back.
class WebSession {
  static const base = 'https://supplier.meesho.com';
  static const loginUrl = '$base/panel/v3/new/root/login';

  /// Set on the MaterialApp so the login sheet can be shown from anywhere.
  static final navigatorKey = GlobalKey<NavigatorState>();

  static final _cookieMgr = CookieManager.instance();
  static final _lock = _Lock();

  /// Transcript of the last operation — Settings → Diagnostics.
  static String? lastDebug;

  static HeadlessInAppWebView? _headless;
  static InAppWebViewController? _ctl;

  // ----------------------------------------------------------------- cookies
  static Future<List<Map<String, String>>> dumpCookies() async {
    final list = await _cookieMgr.getCookies(url: WebUri(base));
    return list.map((c) => {'name': c.name, 'value': '${c.value}'}).toList();
  }

  static Future<void> _installCookies(List<Map<String, String>> cookies) async {
    await _cookieMgr.deleteAllCookies();
    for (final c in cookies) {
      final name = c['name'];
      final value = c['value'];
      if (name == null || value == null) continue;
      await _cookieMgr.setCookie(
        url: WebUri(base),
        name: name,
        value: value,
        domain: '.meesho.com',
        path: '/',
        isSecure: true,
      );
    }
  }

  // ------------------------------------------------------- headless instance
  static Future<InAppWebViewController> _ensureHeadless() async {
    if (_ctl != null) return _ctl!;
    final ready = Completer<InAppWebViewController>();
    _headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(loginUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        thirdPartyCookiesEnabled: true,
        userAgent: 'Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
      ),
      onWebViewCreated: (c) => _ctl = c,
      onLoadStop: (c, url) {
        if (!ready.isCompleted) ready.complete(c);
      },
    );
    await _headless!.run();
    return ready.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => _ctl ?? (throw Exception('WebView did not start')),
    );
  }

  /// Calls a Meesho API path from inside the hidden WebView, with [cookies]
  /// installed for the duration. Tries the request shapes Meesho is known to
  /// accept and returns the first decoded JSON body that comes back 200.
  static Future<dynamic> apiCall(
    List<Map<String, String>> cookies,
    String path, {
    Map<String, dynamic>? body,
    void Function(List<Map<String, String>>)? onCookies,
  }) {
    return _lock.run(() async {
      await _installCookies(cookies);
      final c = await _ensureHeadless();

      // fetch() must run from a document on the Meesho origin.
      final current = (await c.getUrl())?.toString() ?? '';
      if (!current.startsWith(base)) {
        await c.loadUrl(urlRequest: URLRequest(url: WebUri(loginUrl)));
        await Future.delayed(const Duration(milliseconds: 1800));
      }

      final attempts = <String, String>{
        if (body != null) 'POST+body': _fetchJs(path, 'POST', jsonEncode(body)),
        'POST+empty': _fetchJs(path, 'POST', '{}'),
        'GET': _fetchJs(path, 'GET', null),
      };

      final log = StringBuffer();
      log.writeln(path);
      dynamic good;

      for (final a in attempts.entries) {
        final raw = await c.callAsyncJavaScript(functionBody: a.value);
        final value = raw?.value;
        if (value == null) {
          log.writeln('  ${a.key} -> no response');
          continue;
        }
        Map<String, dynamic> env;
        try {
          env = jsonDecode('$value') as Map<String, dynamic>;
        } catch (_) {
          log.writeln('  ${a.key} -> unreadable: $value');
          continue;
        }
        final status = env['status'];
        final text = '${env['body'] ?? ''}';
        final short = text.length > 700 ? '${text.substring(0, 700)}...' : text;
        log.writeln('  ${a.key} -> HTTP $status  $short');

        if (status == 200) {
          try {
            good = jsonDecode(text);
          } catch (_) {
            good = text;
          }
          break;
        }
      }

      lastDebug = log.toString();
      onCookies?.call(await dumpCookies());

      if (good == null) {
        final t = log.toString();
        if (t.contains('HTTP 401') || t.contains('HTTP 403')) throw SessionExpired();
        throw Exception('No usable response - see Settings, Session diagnostics');
      }
      return good;
    });
  }

  static String _fetchJs(String path, String method, String? body) {
    final url = jsonEncode(base + path);
    final m = jsonEncode(method);
    final bodyPart = body == null ? '' : ', body: ${jsonEncode(body)}';
    return "var res = await fetch($url, {"
        "method: $m,"
        "credentials: 'include',"
        "headers: {'Content-Type': 'application/json', 'Accept': 'application/json, text/plain, */*'}"
        "$bodyPart"
        "});"
        "var text = await res.text();"
        "return JSON.stringify({ status: res.status, body: text });";
  }

  // ------------------------------------------------------------------- login
  /// Logs in and returns that account's cookies.
  ///
  /// Runs hidden first. Only if Meesho throws up a captcha / SMS-OTP step does
  /// the visible sheet open, so the person can finish it.
  static Future<List<Map<String, String>>> login({
    required String email,
    required String password,
  }) async {
    try {
      return await _lock.run(() => _headlessLogin(email, password));
    } on _NeedsUser {
      return _sheetLogin(email, password);
    }
  }

  /// Silent login in a throwaway headless WebView.
  static Future<List<Map<String, String>>> _headlessLogin(String email, String password) async {
    await _cookieMgr.deleteAllCookies();
    final log = StringBuffer();
    log.writeln('hidden login for $email');

    InAppWebViewController? ctl;
    final started = Completer<void>();
    final hw = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(loginUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        thirdPartyCookiesEnabled: true,
        userAgent: _ua,
      ),
      onWebViewCreated: (c) => ctl = c,
      onLoadStop: (c, url) {
        log.writeln('loaded $url');
        if (!started.isCompleted) started.complete();
      },
    );

    try {
      await hw.run();
      await started.future.timeout(const Duration(seconds: 30));

      var filled = false;
      for (var elapsed = 0; elapsed < 75000; elapsed += 1200) {
        await Future.delayed(const Duration(milliseconds: 1200));
        final c = ctl;
        if (c == null) continue;

        final url = (await c.getUrl())?.toString() ?? '';
        if (url.isNotEmpty && !_isLoginUrl(url)) {
          await Future.delayed(const Duration(milliseconds: 1600));
          final cookies = await dumpCookies();
          log.writeln('landed on $url with ${cookies.length} cookie(s)');
          lastDebug = log.toString();
          if (cookies.isEmpty) throw Exception('Logged in but no cookies were set');
          return cookies;
        }

        if (!filled) {
          final r = await c.evaluateJavascript(source: fillScript(email, password));
          log.writeln('fill -> $r');
          if ('$r'.contains('submitted')) filled = true;
          continue;
        }

        final state = await c.evaluateJavascript(source: stateScript);
        final st = '$state';
        if (st.contains('wrong')) {
          log.writeln('Meesho rejected the credentials');
          lastDebug = log.toString();
          throw Exception('Wrong email or password');
        }
        if (st.contains('challenge')) {
          log.writeln('captcha / SMS-OTP step - handing over to the visible sheet');
          lastDebug = log.toString();
          throw _NeedsUser();
        }
      }
      log.writeln('timed out on the login page');
      lastDebug = log.toString();
      throw _NeedsUser();
    } finally {
      await hw.dispose();
    }
  }

  /// Visible fallback — used only when Meesho asks for something a human must do.
  static Future<List<Map<String, String>>> _sheetLogin(String email, String password) {
    return _lock.run(() async {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) throw Exception('App is not ready yet');
      final cookies = await showModalBottomSheet<List<Map<String, String>>>(
        context: ctx,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (_) => _LoginSheet(email: email, password: password),
      );
      if (cookies == null || cookies.isEmpty) {
        throw Exception('Login did not complete - see Settings, Session diagnostics');
      }
      return cookies;
    });
  }

  static bool _isLoginUrl(String url) =>
      url.contains('/login') ||
      url.contains('/signin') ||
      RegExp(r'/root/?$').hasMatch(url);

  static const _ua = 'Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  /// JS that fills the Meesho login form and presses the button.
  static String fillScript(String email, String password) {
    final e = jsonEncode(email);
    final p = jsonEncode(password);
    return "(function(){try{"
        "var pass=document.querySelector('input[type=\"password\"]');"
        "var mail=document.querySelector('input[name=\"emailOrPhone\"]')||document.querySelector('input[type=\"email\"]')||document.querySelector('input[type=\"text\"]');"
        "if(!pass||!mail)return 'no-form';"
        "function setVal(el,v){var s=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;"
        "s.call(el,v);el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));}"
        "mail.focus();setVal(mail,$e);pass.focus();setVal(pass,$p);"
        "var btn=document.querySelector('button[type=\"submit\"]');"
        "if(!btn){var all=Array.prototype.slice.call(document.querySelectorAll('button'));"
        "btn=all.filter(function(b){return /log ?in|sign ?in/i.test(b.textContent);})[0];}"
        "if(!btn)return 'no-button';"
        "if(btn.disabled)return 'button-disabled';"
        "btn.click();return 'submitted';"
        "}catch(err){return 'error: '+err.message;}})();";
  }

  /// JS that reports what the login page is currently showing.
  static const stateScript = "(function(){var t=(document.body.innerText||'').toLowerCase();"
      "if(/invalid|incorrect|wrong password|not registered/.test(t))return 'wrong';"
      "if(/enter otp|verification code|otp sent|captcha|verify/.test(t))return 'challenge';"
      "return 'waiting';})();";
}

/// Raised when Meesho needs a human (captcha / SMS-OTP).
class _NeedsUser implements Exception {}

class SessionExpired implements Exception {
  @override
  String toString() => 'Session expired';
}

// =========================================================== the login sheet
class _LoginSheet extends StatefulWidget {
  final String email, password;
  const _LoginSheet({required this.email, required this.password});

  @override
  State<_LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<_LoginSheet> {
  InAppWebViewController? _c;
  Timer? _poll;
  bool _filled = false;
  bool _needsUser = false;
  int _elapsed = 0;
  String _status = 'Meesho needs a quick check — please finish it below';
  final _log = StringBuffer();

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 1200), (t) async {
      if (!mounted) { t.cancel(); return; }
      _elapsed += 1200;
      final c = _c;
      if (c == null) return;

      if (_elapsed > 120000) {
        t.cancel();
        _finish(null, 'Timed out');
        return;
      }

      final url = (await c.getUrl())?.toString() ?? '';
      if (url.isNotEmpty && !_isLogin(url)) {
        t.cancel();
        setState(() => _status = 'Logged in — saving session…');
        await Future.delayed(const Duration(milliseconds: 1600));
        final cookies = await WebSession.dumpCookies();
        _log.writeln('landed on $url with ${cookies.length} cookie(s)');
        _finish(cookies, 'done');
        return;
      }

      if (!_filled) {
        final r = await c.evaluateJavascript(source: WebSession.fillScript(widget.email, widget.password));
        _log.writeln('fill → $r');
        if ('$r'.contains('submitted')) {
          _filled = true;
          if (mounted) setState(() => _status = 'Signing in…');
        }
        return;
      }

      final state = await c.evaluateJavascript(source: WebSession.stateScript);
      final s = '$state';
      if (s.contains('wrong')) {
        t.cancel();
        _log.writeln('Meesho rejected the credentials');
        _finish(null, 'Wrong email or password');
      } else if (s.contains('challenge') && !_needsUser) {
        setState(() {
          _needsUser = true;
          _status = 'Meesho needs a quick check — please finish it below';
        });
      }
    });
  }

  void _finish(List<Map<String, String>>? cookies, String note) {
    WebSession.lastDebug = '${_log.toString()}\n$note';
    if (mounted) Navigator.of(context).pop(cookies);
  }

  bool _isLogin(String url) =>
      url.contains('/login') || url.contains('/signin') || RegExp(r'/root/?$').hasMatch(url);

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return SizedBox(
      height: h * .9,
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.skyLine,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                const Icon(Icons.touch_app_rounded, size: 20, color: AppColors.warn),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _status,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                  ),
                ),
                TextButton(
                  onPressed: () => _finish(null, 'cancelled by user'),
                  child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ClipRRect(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(WebSession.loginUrl)),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  thirdPartyCookiesEnabled: true,
                  userAgent:
                      'Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 '
                      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
                ),
                onWebViewCreated: (c) => _c = c,
                onLoadStop: (c, url) {
                  _log.writeln('loaded $url');
                  if (_poll == null) _startPolling();
                },
                onReceivedError: (c, req, err) {
                  _log.writeln('load error: ${err.description}');
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Minimal mutex so cookie swaps never overlap between accounts.
class _Lock {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}
