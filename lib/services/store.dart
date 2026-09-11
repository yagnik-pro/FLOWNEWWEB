import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import '../models/otp_entry.dart';
import 'meesho_api.dart';
import 'web_session.dart';
import 'notifier.dart';

/// Single source of truth for the whole app.
class AppStore extends ChangeNotifier {
  static const _kAccounts = 'otpflow.accounts';
  static const _kInterval = 'otpflow.intervalMin';
  static const _kNotify = 'otpflow.notify';
  static const _kBg = 'otpflow.background';

  final List<Account> accounts = [];
  int intervalMin = 5;
  bool notifyOnNew = true;
  bool backgroundEnabled = true;

  bool busy = false;
  String? busyLabel;
  Timer? _timer;

  // ------------------------------------------------------------ lifecycle
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kAccounts);
    if (raw != null) {
      try {
        accounts
          ..clear()
          ..addAll((jsonDecode(raw) as List).map((e) => Account.fromJson(Map<String, dynamic>.from(e))));
      } catch (_) {}
    }
    intervalMin = p.getInt(_kInterval) ?? 5;
    notifyOnNew = p.getBool(_kNotify) ?? true;
    backgroundEnabled = p.getBool(_kBg) ?? true;
    for (final a in accounts) {
      a.status = a.cookies.isNotEmpty ? AccStatus.ok : AccStatus.needsLogin;
    }
    notifyListeners();
    _restartTimer();
    if (accounts.isNotEmpty) refreshAll(silent: true);
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAccounts, jsonEncode(accounts.map((a) => a.toJson()).toList()));
  }

  Future<void> setInterval(int m) async {
    intervalMin = m;
    (await SharedPreferences.getInstance()).setInt(_kInterval, m);
    _restartTimer();
    notifyListeners();
  }

  Future<void> setNotify(bool v) async {
    notifyOnNew = v;
    (await SharedPreferences.getInstance()).setBool(_kNotify, v);
    notifyListeners();
  }

  Future<void> setBackground(bool v) async {
    backgroundEnabled = v;
    (await SharedPreferences.getInstance()).setBool(_kBg, v);
    notifyListeners();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (intervalMin > 0) {
      _timer = Timer.periodic(Duration(minutes: intervalMin), (_) {
        if (!busy) refreshAll(silent: true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------- accounts
  Future<String?> addAccount(String email, String password, {String? name}) async {
    if (accounts.any((a) => a.email.toLowerCase() == email.trim().toLowerCase())) {
      return 'This email is already added';
    }
    final acc = Account(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      email: email.trim(),
      password: password,
      name: (name != null && name.trim().isNotEmpty) ? name.trim() : null,
      autoName: name == null || name.trim().isEmpty,
    );
    accounts.add(acc);
    await _save();
    notifyListeners();
    final err = await _loginOne(acc);
    if (err == null) await _fetchOne(acc, allowRelogin: false);
    await _save();
    notifyListeners();
    return err;
  }

  Future<void> removeAccount(Account a) async {
    a.cookies = [];
    accounts.removeWhere((x) => x.id == a.id);
    await _save();
    notifyListeners();
  }

  Future<void> renameAccount(Account a, String name) async {
    a.name = name.trim();
    a.autoName = name.trim().isEmpty;
    await _save();
    notifyListeners();
  }

  // --------------------------------------------------------------- actions
  /// Re-login the given accounts (or all) and fetch their OTPs.
  Future<void> reloginAll(List<Account> targets) async {
    if (busy) return;
    busy = true;
    busyLabel = 'Logging in…';
    notifyListeners();
    await _parallel(targets, (a) async {
      final err = await _loginOne(a);
      if (err == null) await _fetchOne(a, allowRelogin: false);
    });
    await _save();
    busy = false;
    busyLabel = null;
    notifyListeners();
  }

  /// Fetch OTPs for every account (auto re-login if the session died).
  Future<void> refreshAll({bool silent = false}) async {
    if (busy || accounts.isEmpty) return;
    busy = true;
    busyLabel = 'Refreshing…';
    if (!silent) notifyListeners();
    final before = {for (final a in accounts) a.id: a.otps.map((o) => o.key).toSet()};
    await _parallel(List.of(accounts), (a) => _fetchOne(a));
    await _save();
    busy = false;
    busyLabel = null;
    notifyListeners();
    if (notifyOnNew) _notifyNew(before);
  }

  Future<void> refreshOne(Account a) async {
    if (busy) return;
    busy = true;
    busyLabel = 'Refreshing ${a.name}…';
    notifyListeners();
    final before = {a.id: a.otps.map((o) => o.key).toSet()};
    await _fetchOne(a);
    await _save();
    busy = false;
    busyLabel = null;
    notifyListeners();
    if (notifyOnNew) _notifyNew(before);
  }

  /// Runs [fn] over [items] with a small concurrency window — this is what
  /// makes a 5-account refresh finish in a couple of seconds.
  Future<void> _parallel(List<Account> items, Future<void> Function(Account) fn, {int width = 4}) async {
    final queue = List.of(items);
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final a = queue.removeAt(0);
        try { await fn(a); } catch (_) {}
        notifyListeners();
      }
    }
    await Future.wait(List.generate(width.clamp(1, 6), (_) => worker()));
  }

  Future<String?> _loginOne(Account a) async {
    a.status = AccStatus.working;
    a.lastError = null;
    notifyListeners();
    try {
      // Plain HTTP gets a 403 from Meesho's edge, so the login runs in a real
      // WebView. It also hands back the identifier from the panel URL.
      final r = await WebSession.login(email: a.email, password: a.password);
      a.cookies = r.cookies;
      if (r.identifier.isNotEmpty) a.identifier = r.identifier;
      a.lastLogin = DateTime.now().millisecondsSinceEpoch;
      a.status = AccStatus.ok;
      return null;
    } catch (e) {
      a.status = AccStatus.error;
      a.lastError = e.toString().replaceFirst('Exception: ', '');
      return a.lastError;
    }
  }

  Future<void> _fetchOne(Account a, {bool allowRelogin = true}) async {
    a.status = AccStatus.working;
    notifyListeners();
    try {
      if (a.cookies.isEmpty) throw SessionExpired();

      // Meesho answers 403 / errorCode 1001 without the identifier. Accounts
      // saved before we started capturing it get it recovered here.
      if (a.identifier.isEmpty) {
        a.identifier = await WebSession.discoverIdentifier(a.cookies);
        if (a.identifier.isEmpty) throw SessionExpired();
      }

      final data = await WebSession.apiCall(
        a.cookies,
        '/api/fulfillment/returnRto/fetchDeliveryOTPs',
        identifier: a.identifier,
        onCookies: (c) {
          if (c.isNotEmpty) a.cookies = c;
        },
      );

      a.otps = MeeshoApi.parseOtps(data);
      a.fetchedAt = DateTime.now().millisecondsSinceEpoch;
      a.status = AccStatus.ok;
      a.lastError = null;
      if (a.otps.isEmpty) {
        MeeshoApi.lastRawResponse = WebSession.lastDebug;
        a.lastError = 'Logged in, but no OTPs in the response - see Settings, Session diagnostics';
      }

      if (a.supplierId.isEmpty || (a.autoName && a.name.contains('@'))) {
        unawaited(_fetchDetails(a));
      }
    } on SessionExpired {
      if (allowRelogin) {
        final err = await _loginOne(a);
        if (err == null) {
          await _fetchOne(a, allowRelogin: false);
          return;
        }
        a.status = AccStatus.needsLogin;
      } else {
        a.status = AccStatus.needsLogin;
        a.lastError = 'Session expired - tap relogin';
      }
    } catch (e) {
      a.status = AccStatus.error;
      a.lastError = e.toString().replaceFirst('Exception: ', '');
    }
  }

  /// Store name and supplier id — nice to have, never fatal.
  Future<void> _fetchDetails(Account a) async {
    try {
      final d = await WebSession.apiCall(
        a.cookies,
        '/api/container/supplier/getSupplierDetails',
        identifier: a.identifier,
      );
      final id = MeeshoApi.digInto(d, const ['supplier_id', 'supplierId', 'id']);
      final nm = MeeshoApi.digInto(d, const [
        'name', 'supplier_name', 'business_name', 'shop_name', 'display_name', 'store_name',
      ]);
      if (id != null && id.isNotEmpty) a.supplierId = id;
      if (nm != null && nm.isNotEmpty && a.autoName) a.name = nm;
      notifyListeners();
    } catch (_) {}
  }

  void _notifyNew(Map<String, Set<String>> before) {
    for (final a in accounts) {
      final old = before[a.id] ?? {};
      final fresh = a.otps.where((o) => !old.contains(o.key)).toList();
      for (final o in fresh) {
        Notifier.show(
          title: '${o.carrier} · ${o.otp}',
          body: '${a.name} · ${o.count} parcel(s) ready for handover',
        );
      }
    }
  }

  // --------------------------------------------------------------- getters
  int get totalReturns => accounts.fold(0, (s, a) => s + a.totalReturns);
  int get totalOtps => accounts.fold(0, (s, a) => s + a.otps.length);

  List<CarrierGroup> get byCarrier {
    final map = <String, CarrierGroup>{};
    for (final a in accounts) {
      for (final o in a.otps) {
        final g = map.putIfAbsent(o.carrier, () => CarrierGroup(o.carrier));
        g.total += o.count;
        g.rows.add(CarrierRow(
          accountId: a.id, accountName: a.name, otp: o.otp, count: o.count, time: o.time,
        ));
      }
    }
    final list = map.values.toList()..sort((x, y) => y.total.compareTo(x.total));
    for (final g in list) { g.rows.sort((x, y) => y.count.compareTo(x.count)); }
    return list;
  }
}
