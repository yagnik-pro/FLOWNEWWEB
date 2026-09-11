import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../theme.dart';

/// What a successful login yields: the session cookies plus the supplier
/// identifier, which Meesho puts straight into the panel URL
/// (`/panel/v3/new/growth/<identifier>/home`).
class LoginResult {
  final List<Map<String, String>> cookies;
  final String identifier;
  const LoginResult({required this.cookies, required this.identifier});
}

class SessionExpired implements Exception {
  @override
  String toString() => 'Session expired';
}

/// Raised when Meesho needs a human (captcha / SMS-OTP).
class _NeedsUser implements Exception {}

/// Meesho's edge returns 403 to plain HTTP clients — even for the login page —
/// so everything runs through a real WebView.
///
///   * [login]   — loads the panel login page in a hidden WebView, fills the
///                 form, and hands back the cookies plus the identifier once
///                 Meesho redirects. Only if a captcha / SMS-OTP step appears
///                 does a visible sheet open for the person to finish it.
///   * [apiCall] — runs `fetch()` inside a hidden WebView, so the request
///                 carries the real cookies and fingerprint. A fetch is just an
///                 XHR, so it returns in well under a second.
///
/// Android's WebView cookie store is global, so accounts are processed one at a
/// time: clear cookies → install this account's → do the work → save them back.
class WebSession {
  static const base = 'https://supplier.meesho.com';
  static const loginUrl = '$base/panel/v3/new/root/login';

  /// Set on the MaterialApp so the login sheet can open from anywhere.
  static final navigatorKey = GlobalKey<NavigatorState>();

  static final _cookieMgr = CookieManager.instance();
  static final _lock = _Lock();

  static const ua = 'Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  /// Rolling transcript of recent calls — Settings → Session diagnostics.
  static String? lastDebug;
  static final List<String> _history = [];

  static void _record(String entry) {
    _history.add(entry.trim());
    while (_history.length > 6) {
      _history.removeAt(0);
    }
    lastDebug = _history.join('\n\n');
  }

  static HeadlessInAppWebView? _headless;
  static InAppWebViewController? _ctl;

  // ================================================================= cookies
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

  // ================================================================ identity
  /// The panel identifies a seller by the short code in its own URLs, e.g.
  /// `/panel/v3/new/growth/wb41m/home` → `wb41m`. Every XHR the panel makes
  /// sends it as the `identifier` header; without it the API answers
  /// `403 {"errorCode":1001,"message":"Identifier not present or invalid"}`.
  static String identifierFromUrl(String url) {
    final m = RegExp(r'/panel/v3/new/(?!root\b)[^/]+/([A-Za-z0-9]{3,16})(?:/|$)')
        .firstMatch(url);
    return m == null ? '' : m.group(1)!;
  }

  /// Loads the panel with [cookies] installed and reads the identifier out of
  /// whatever URL Meesho lands on. Used for accounts saved before we started
  /// capturing it at login.
  static Future<String> discoverIdentifier(List<Map<String, String>> cookies) {
    return _lock.run(() async {
      await _installCookies(cookies);
      final c = await _ensureHeadless();
      await c.loadUrl(urlRequest: URLRequest(url: WebUri('$base/panel/v3/new/root/home')));
      for (var i = 0; i < 12; i++) {
        await Future.delayed(const Duration(milliseconds: 800));
        final url = (await c.getUrl())?.toString() ?? '';
        final ident = identifierFromUrl(url);
        if (ident.isNotEmpty) {
          _record('identifier discovered from $url -> $ident');
          return ident;
        }
      }
      _record('could not discover an identifier from the panel URL');
      return '';
    });
  }

  // ======================================================= headless instance
  static Future<InAppWebViewController> _ensureHeadless() async {
    if (_ctl != null) return _ctl!;
    final ready = Completer<InAppWebViewController>();
    _headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(loginUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        thirdPartyCookiesEnabled: true,
        userAgent: ua,
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

  // ================================================================ API call
  /// Values Meesho accepts for `client-type`. Anything else gets
  /// `400 {"message":"Bad Request. Invalid client type."}`.
  static const _clientTypes = ['web', 'supplier-web', 'supplier', 'android'];

  /// Remembered once we learn which value works, so later calls are one shot.
  static String? goodClientType;

  /// Calls a Meesho API path from inside the hidden WebView with [cookies]
  /// installed, and returns the first decoded body that comes back 200.
  static Future<dynamic> apiCall(
    List<Map<String, String>> cookies,
    String path, {
    Map<String, dynamic>? body,
    String identifier = '',
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

      final types = <String>[
        if (goodClientType != null) goodClientType!,
        ..._clientTypes.where((t) => t != goodClientType),
      ];

      final shownId = identifier.isEmpty ? '(none)' : identifier;
      final log = StringBuffer();
      log.writeln('$path  identifier=$shownId');
      dynamic good;

      outer:
      for (final ct in types) {
        final payloads = <String, String>{
          if (body != null) 'body': jsonEncode(body),
          'empty': '{}',
        };
        for (final pl in payloads.entries) {
          final js = _fetchJs(path, pl.value, ct, identifier);
          final raw = await c.callAsyncJavaScript(functionBody: js);
          final value = raw?.value;
          if (value == null) {
            log.writeln('  POST ${pl.key} ct=$ct -> no response');
            continue;
          }
          Map<String, dynamic> env;
          try {
            env = jsonDecode('$value') as Map<String, dynamic>;
          } catch (_) {
            log.writeln('  POST ${pl.key} ct=$ct -> unreadable: $value');
            continue;
          }
          final status = env['status'];
          final text = '${env['body'] ?? ''}';
          final short = text.length > 500 ? '${text.substring(0, 500)}...' : text;
          log.writeln('  POST ${pl.key} ct=$ct -> HTTP $status  $short');

          if (status == 200) {
            goodClientType = ct;
            try {
              good = jsonDecode(text);
            } catch (_) {
              good = text;
            }
            break outer;
          }
          // "Invalid client type" means this value is simply wrong — move on.
          if (status == 400 && text.contains('client type')) continue outer;
        }
      }

      _record(log.toString());
      onCookies?.call(await dumpCookies());

      if (good == null) {
        final t = log.toString();
        // errorCode 1001 means a required header is missing, not a dead session.
        final missingHeader = t.contains('1001') || t.contains('Identifier not present');
        if (!missingHeader && (t.contains('HTTP 401') || t.contains('HTTP 403'))) {
          throw SessionExpired();
        }
        throw Exception('No usable response - see Settings, Session diagnostics');
      }
      return good;
    });
  }

  static String _fetchJs(String path, String body, String clientType, String identifier) {
    final url = jsonEncode(base + path);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/plain, */*',
      'client-type': clientType,
      if (identifier.isNotEmpty) 'identifier': identifier,
    };
    final h = jsonEncode(headers);
    final b = jsonEncode(body);
    return "var res = await fetch($url, {"
        "method: 'POST',"
        "credentials: 'include',"
        "headers: $h,"
        "body: $b"
        "});"
        "var text = await res.text();"
        "return JSON.stringify({ status: res.status, body: text });";
  }

  // =================================================================== login
  /// Logs in and returns the account's cookies plus its identifier.
  static Future<LoginResult> login({
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
  static Future<LoginResult> _headlessLogin(String email, String password) async {
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
        userAgent: ua,
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
        if (url.isNotEmpty && !isLoginUrl(url)) {
          await Future.delayed(const Duration(milliseconds: 1600));
          final cookies = await dumpCookies();
          final ident = identifierFromUrl(url);
          log.writeln('landed on $url with ${cookies.length} cookie(s), identifier=$ident');
          _record(log.toString());
          if (cookies.isEmpty) throw Exception('Logged in but no cookies were set');
          return LoginResult(cookies: cookies, identifier: ident);
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
          _record(log.toString());
          throw Exception('Wrong email or password');
        }
        if (st.contains('challenge')) {
          log.writeln('captcha / SMS-OTP step - handing over to the visible sheet');
          _record(log.toString());
          throw _NeedsUser();
        }
      }
      log.writeln('timed out on the login page');
      _record(log.toString());
      throw _NeedsUser();
    } finally {
      await hw.dispose();
    }
  }

  /// Visible fallback — only when Meesho asks for something a human must do.
  static Future<LoginResult> _sheetLogin(String email, String password) {
    return _lock.run(() async {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) throw Exception('App is not ready yet');
      final result = await showModalBottomSheet<LoginResult>(
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
      if (result == null || result.cookies.isEmpty) {
        throw Exception('Login did not complete - see Settings, Session diagnostics');
      }
      return result;
    });
  }

  static bool isLoginUrl(String url) =>
      url.contains('/login') ||
      url.contains('/signin') ||
      RegExp(r'/root/?$').hasMatch(url);

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

// ============================================================== login sheet
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
      if (!mounted) {
        t.cancel();
        return;
      }
      _elapsed += 1200;
      final c = _c;
      if (c == null) return;

      if (_elapsed > 180000) {
        t.cancel();
        _finish(null, 'timed out');
        return;
      }

      final url = (await c.getUrl())?.toString() ?? '';
      if (url.isNotEmpty && !WebSession.isLoginUrl(url)) {
        t.cancel();
        setState(() => _status = 'Logged in — saving session…');
        await Future.delayed(const Duration(milliseconds: 1600));
        final cookies = await WebSession.dumpCookies();
        final ident = WebSession.identifierFromUrl(url);
        _log.writeln('landed on $url with ${cookies.length} cookie(s), identifier=$ident');
        _finish(LoginResult(cookies: cookies, identifier: ident), 'done');
        return;
      }

      if (!_filled) {
        final r = await c.evaluateJavascript(
            source: WebSession.fillScript(widget.email, widget.password));
        _log.writeln('fill -> $r');
        if ('$r'.contains('submitted')) _filled = true;
        return;
      }

      final state = await c.evaluateJavascript(source: WebSession.stateScript);
      if ('$state'.contains('wrong')) {
        t.cancel();
        _log.writeln('Meesho rejected the credentials');
        _finish(null, 'wrong email or password');
      }
    });
  }

  void _finish(LoginResult? result, String note) {
    WebSession.lastDebug = '${_log.toString()}\n$note';
    if (mounted) Navigator.of(context).pop(result);
  }

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
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(WebSession.loginUrl)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                thirdPartyCookiesEnabled: true,
                userAgent: WebSession.ua,
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
