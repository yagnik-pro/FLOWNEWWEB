import 'dart:convert';

import '../models/otp_entry.dart';

/// Pure parsing helpers for whatever JSON Meesho's API returns.
///
/// Transport lives in [WebSession] — Meesho's edge 403s plain HTTP clients, so
/// every request goes through a real WebView. This class only makes sense of
/// the payload that comes back.
class MeeshoApi {
  /// Last raw response we could not parse — shown in Settings → Diagnostics.
  static String? lastRawResponse;

  /// Walks any JSON shape and pulls out every {carrier, otp, count} it can find.
  static List<OtpEntry> parseOtps(dynamic data) {
    final out = <OtpEntry>[];

    void walk(dynamic node, int depth) {
      if (depth > 10 || node == null) return;
      if (node is List) {
        for (final v in node) {
          walk(v, depth + 1);
        }
        return;
      }
      if (node is! Map) return;
      final map = node.map((k, v) => MapEntry(k.toString(), v));

      final otp = _pick(map, const [
        'otp_code', 'supplier_delivery_otp', 'delivery_otp', 'otp', 'end_otp',
        'return_otp', 'admin_lock_otp',
      ]);
      final carrier = _pick(map, const [
        'carrier', 'courier', 'carrier_name', 'courier_name', 'logistics_name',
        'logistics_partner', 'sp_name', 'name',
      ]);

      if (otp != null && carrier != null) {
        final otpStr = otp.toString().trim();
        final carrierStr = _cleanCarrier(carrier.toString());
        if (RegExp(r'^\d{3,8}$').hasMatch(otpStr) && carrierStr.isNotEmpty) {
          final count = _pick(map, const [
            'count', 'total_count', 'handover_count', 'total_handover_count',
            'shipment_count', 'shipments', 'awb_count',
          ]);
          final time = _pick(map, const [
            'otp_generated_at', 'created_at', 'generated_at', 'updated_at', 'time', 'date',
          ]);
          final already = out.any((e) => e.carrier == carrierStr && e.otp == otpStr);
          if (!already) {
            out.add(OtpEntry(
              carrier: carrierStr,
              otp: otpStr,
              count: _toInt(count),
              time: formatTime(time),
            ));
          }
        }
      }

      for (final v in map.values) {
        walk(v, depth + 1);
      }
    }

    walk(data, 0);
    out.sort((a, b) => b.count.compareTo(a.count));
    return out;
  }

  /// Finds the first string value stored under any of [keys], at any depth.
  static String? digInto(dynamic node, List<String> keys, [int depth = 0]) {
    if (depth > 6 || node == null) return null;
    if (node is List) {
      for (final v in node) {
        final r = digInto(v, keys, depth + 1);
        if (r != null) return r;
      }
      return null;
    }
    if (node is! Map) return null;
    for (final k in keys) {
      for (final e in node.entries) {
        if (e.key.toString().toLowerCase() == k.toLowerCase()) {
          final v = e.value;
          if (v != null && v is! Map && v is! List && v.toString().trim().isNotEmpty) {
            return v.toString().trim();
          }
        }
      }
    }
    for (final v in node.values) {
      final r = digInto(v, keys, depth + 1);
      if (r != null) return r;
    }
    return null;
  }

  static String _cleanCarrier(String s) {
    final v = s.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (v.isEmpty || v.length > 30) return '';
    if (RegExp(r'^\d+$').hasMatch(v)) return '';
    const fix = {
      'xpress bees': 'Xpressbees',
      'xpressbees': 'Xpressbees',
      'delhivery': 'Delhivery',
      'shadowfax': 'Shadowfax',
      'valmo': 'Valmo',
      'ecom express': 'Ecom Express',
      'ekart': 'Ekart',
    };
    final lower = v.toLowerCase().replaceAll('_', ' ');
    final mapped = fix[lower];
    if (mapped != null) return mapped;
    return v
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  /// Turns whatever timestamp shape Meesho sends into "4 Sept, 01:57 PM".
  static String formatTime(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    final asInt = int.tryParse(s);
    DateTime? dt;
    if (asInt != null && s.length >= 10) {
      dt = DateTime.fromMillisecondsSinceEpoch(s.length > 11 ? asInt : asInt * 1000);
    } else {
      dt = DateTime.tryParse(s);
    }
    if (dt == null) return s.length > 24 ? '' : s;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final local = dt.toLocal();
    var h = local.hour % 12;
    if (h == 0) h = 12;
    final ap = local.hour < 12 ? 'AM' : 'PM';
    final hh = h.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month - 1]}, $hh:$mm $ap';
  }

  static dynamic _pick(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      for (final entry in m.entries) {
        if (entry.key.toLowerCase() == k) {
          final v = entry.value;
          if (v != null && v is! Map && v is! List) return v;
        }
      }
    }
    return null;
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse(v.toString()) ?? 0;
  }

  /// Compact one-line preview of any payload, for the diagnostics sheet.
  static String preview(dynamic d, [int cap = 2500]) {
    try {
      final s = d is String ? d : jsonEncode(d);
      final one = s.replaceAll(RegExp(r'\s+'), ' ').trim();
      return one.length > cap ? '${one.substring(0, cap)}…' : one;
    } catch (_) {
      return d.toString();
    }
  }
}
