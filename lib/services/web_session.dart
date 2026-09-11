import 'dart:async';
import 'dart:collection';
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

/// What one pass over the panel's Returns page yields.
class PanelResult {
  final dynamic otpData;
  final String storeName;
  const PanelResult({required this.otpData, required this.storeName});
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
            final err = raw?.error;
            final extra = err == null ? '' : ' (bridge error: $err)';
            log.writeln('  POST ${pl.key} ct=$ct -> no value from JS$extra');
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
          final len = env['len'] ?? text.length;
          final short = text.length > 500 ? '${text.substring(0, 500)}...' : text;
          log.writeln('  POST ${pl.key} ct=$ct -> HTTP $status  [$len bytes]  $short');

          final rejectedType = status == 400 && text.contains('client type');
          // Anything other than "Invalid client type" means the server accepted
          // this value, so stop cycling through the rest on later calls.
          if (!rejectedType && status != -1) goodClientType = ct;

          if (status == 200) {
            try {
              good = jsonDecode(text);
            } catch (_) {
              good = text;
            }
            break outer;
          }
          if (rejectedType) continue outer;
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
    // Wrapped in try/catch: a rejected fetch used to come back as a bare null,
    // which told us nothing. Long bodies are trimmed so the JS bridge can
    // always marshal the result back.
    return "try {"
        "var res = await fetch($url, {"
        "method: 'POST',"
        "credentials: 'include',"
        "headers: $h,"
        "body: $b"
        "});"
        "var text = await res.text();"
        "var full = text.length;"
        "if (text.length > 120000) { text = text.slice(0, 120000); }"
        "return JSON.stringify({ status: res.status, len: full, body: text });"
        "} catch (e) {"
        "return JSON.stringify({ status: -1, len: 0, body: 'JS error: ' + (e && e.message ? e.message : String(e)) });"
        "}";
  }

  /// True when a decoded payload actually carries courier/OTP pairs, so we
  /// don't latch onto some unrelated 200 the page happened to make.
  static bool _looksLikeOtps(dynamic node, [int depth = 0]) {
    if (depth > 8 || node == null) return false;
    if (node is List) {
      for (final v in node) {
        if (_looksLikeOtps(v, depth + 1)) return true;
      }
      return false;
    }
    if (node is! Map) return false;
    final keys = node.keys.map((k) => k.toString().toLowerCase()).toSet();
    const otpKeys = {
      'otp_code', 'supplier_delivery_otp', 'delivery_otp', 'otp',
      'admin_lock_otp', 'end_otp', 'return_otp',
    };
    if (keys.any(otpKeys.contains)) return true;
    for (final v in node.values) {
      if (_looksLikeOtps(v, depth + 1)) return true;
    }
    return false;
  }

  /// Reads the store name straight off the panel. The API route for this keeps
  /// returning 403, but the page has the name in plain sight — in the sidebar
  /// header and in the "Welcome back, X" greeting.
  static const _storeNameJs = "(function(){try{"
      "var t=document.body.innerText||'';"
      "var m=t.match(/Welcome back,\\s*([^\\n]{2,60})/i);"
      "if(m&&m[1])return m[1].trim();"
      "var side=document.querySelector('aside,nav,[class*=\"sidebar\" i],[class*=\"Sidebar\" i]');"
      "if(side){var lines=(side.innerText||'').split('\\n').map(function(x){return x.trim();})"
      ".filter(function(x){return x&&x.length>1&&x.length<60&&!/notice|support|home|order|return|pricing|claim|inventory|catalog|quality|payment|warehouse|service|menu/i.test(x);});"
      "if(lines.length)return lines[0];}"
      "for(var i=0;i<localStorage.length;i++){var k=localStorage.key(i);var v=localStorage.getItem(k)||'';"
      "var n=v.match(/\"(?:supplier_name|business_name|shop_name|store_name)\"\\s*:\\s*\"([^\"]{2,60})\"/);"
      "if(n)return n[1];}"
      "return '';"
      "}catch(e){return '';}})();";

  // ======================================================= panel interception
  /// Injected before any page script runs. It wraps `fetch` and `XMLHttpRequest`
  /// so every returns-related call the panel makes — request body and response —
  /// lands in `window.__otpflow`.
  static const _hookJs = "(function(){"
      "if(window.__otpflow)return;"
      "window.__otpflow=[];"
      "function keep(u){return /fetchDeliveryOTPs|returnRto|fetchOverview/i.test(u||'');}"
      "var of=window.fetch;"
      "window.fetch=function(){"
      "var a=arguments;"
      "var u=(a[0]&&a[0].url)?a[0].url:String(a[0]);"
      "var rb='';try{rb=(a[1]&&a[1].body)?String(a[1].body):'';}catch(e){}"
      "return of.apply(this,a).then(function(res){"
      "try{if(keep(u)){res.clone().text().then(function(t){"
      "window.__otpflow.push({url:u,status:res.status,req:rb,body:t});"
      "}).catch(function(){});}}catch(e){}"
      "return res;});};"
      "var oo=XMLHttpRequest.prototype.open,os=XMLHttpRequest.prototype.send;"
      "XMLHttpRequest.prototype.open=function(m,u){this.__u=u;this.__m=m;return oo.apply(this,arguments);};"
      "XMLHttpRequest.prototype.send=function(b){var s=this;"
      "this.addEventListener('load',function(){try{if(keep(s.__u)){"
      "window.__otpflow.push({url:s.__u,status:s.status,req:b?String(b):'',body:s.responseText});"
      "}}catch(e){}});"
      "return os.apply(this,arguments);};"
      "})();";

  /// Opens the panel's own Returns page and returns whatever its OTP call
  /// received. No payload guessing — the panel builds the request itself.
  static Future<PanelResult> fetchOtpsViaPanel(
    List<Map<String, String>> cookies,
    String identifier, {
    void Function(List<Map<String, String>>)? onCookies,
  }) {
    return _lock.run(() async {
      await _installCookies(cookies);

      final log = StringBuffer();
      log.writeln('panel returns page  identifier=$identifier');

      InAppWebViewController? ctl;
      final hw = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri('$base/panel/v3/new/fulfillment/$identifier/returns/overview'),
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          thirdPartyCookiesEnabled: true,
          userAgent: ua,
        ),
        initialUserScripts: UnmodifiableListView<UserScript>([
          UserScript(source: _hookJs, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START),
        ]),
        onWebViewCreated: (c) => ctl = c,
      );

      try {
        await hw.run();
        dynamic captured;
        var storeName = '';

        for (var i = 0; i < 25; i++) {
          await Future.delayed(const Duration(milliseconds: 800));
          final c = ctl;
          if (c == null) continue;

          final url = (await c.getUrl())?.toString() ?? '';
          if (isLoginUrl(url)) {
            log.writeln('bounced to the login page - session is dead');
            _record(log.toString());
            throw SessionExpired();
          }

          if (storeName.isEmpty) {
            final n = await c.evaluateJavascript(source: _storeNameJs);
            final v = '${n ?? ''}'.trim();
            if (v.isNotEmpty && v != 'null') {
              storeName = v;
              log.writeln('  store name from page: $storeName');
            }
          }

          final raw = await c.evaluateJavascript(
              source: "JSON.stringify(window.__otpflow || [])");
          if (raw == null) continue;
          List<dynamic> entries;
          try {
            entries = jsonDecode('$raw') as List<dynamic>;
          } catch (_) {
            continue;
          }
          if (entries.isEmpty) continue;

          for (final e in entries) {
            final m = Map<String, dynamic>.from(e as Map);
            final status = m['status'];
            final body = '${m['body'] ?? ''}';
            final req = '${m['req'] ?? ''}';
            final shortReq = req.length > 200 ? '${req.substring(0, 200)}...' : req;
            final shortBody = body.length > 400 ? '${body.substring(0, 400)}...' : body;
            log.writeln('  ${m['url']} -> HTTP $status');
            if (shortReq.isNotEmpty) log.writeln('    request: $shortReq');
            log.writeln('    response: $shortBody');

            if (status == 200 && body.isNotEmpty) {
              try {
                final decoded = jsonDecode(body);
                if (_looksLikeOtps(decoded)) {
                  captured = decoded;
                }
              } catch (_) {}
            }
          }
          if (captured != null) break;
        }

        // Nudge the page: the OTP list sometimes only loads when opened.
        if (captured == null && ctl != null) {
          await ctl!.evaluateJavascript(source: _clickMoreOtps);
          await Future.delayed(const Duration(seconds: 3));
          final raw = await ctl!.evaluateJavascript(
              source: "JSON.stringify(window.__otpflow || [])");
          try {
            for (final e in (jsonDecode('$raw') as List<dynamic>)) {
              final m = Map<String, dynamic>.from(e as Map);
              final body = '${m['body'] ?? ''}';
              if (m['status'] == 200 && body.isNotEmpty) {
                final decoded = jsonDecode(body);
                if (_looksLikeOtps(decoded)) {
                  captured = decoded;
                  log.writeln('  captured after opening "More OTPs"');
                  break;
                }
              }
            }
          } catch (_) {}
        }

        _record(log.toString());
        onCookies?.call(await dumpCookies());

        if (captured == null) {
          throw Exception('Panel did not return OTP data - see Settings, Session diagnostics');
        }
        return PanelResult(otpData: captured, storeName: storeName);
      } finally {
        await hw.dispose();
      }
    });
  }

  static const _clickMoreOtps = "(function(){try{"
      "var els=Array.prototype.slice.call(document.querySelectorAll('span,div,p,a,button'));"
      "var m=els.filter(function(e){return /More OTPs/i.test(e.textContent)&&e.offsetParent!==null;})[0];"
      "if(m){m.click();return 'clicked';}return 'not-found';"
      "}catch(e){return 'err';}})();";

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
