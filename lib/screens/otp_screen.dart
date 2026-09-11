import 'package:flutter/material.dart';

import '../main.dart';
import '../theme.dart';
import '../models/account.dart';
import '../widgets/brand.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  int _view = 0; // 0 = account-wise, 1 = courier-wise
  String _q = '';
  final _searchCtl = TextEditingController();

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  bool _hit(List<String> fields) {
    if (_q.isEmpty) return true;
    return fields.join(' ').toLowerCase().contains(_q);
  }

  String _ago(int? ms) {
    if (ms == null) return 'not refreshed';
    final m = ((DateTime.now().millisecondsSinceEpoch - ms) / 60000).round();
    if (m <= 0) return 'just now';
    if (m < 60) return '$m min ago';
    return '${(m / 60).floor()} hr ago';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final accounts = store.accounts;
        final carriers = store.byCarrier;

        return Column(
          children: [
            FlowHeader(
              title: 'OTP Flow',
              subtitle: '${accounts.length} account(s) · ${store.totalReturns} returns pending',
              actions: [
                IconButton(
                  onPressed: store.busy ? null : () => store.refreshAll(),
                  icon: store.busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : const Icon(Icons.refresh_rounded, color: Colors.white),
                  tooltip: 'Refresh all',
                ),
              ],
              bottom: Column(
                children: [
                  Container(
                    height: 44,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(.17), borderRadius: BorderRadius.circular(999)),
                    child: TextField(
                      controller: _searchCtl,
                      onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                      style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600),
                      cursorColor: Colors.white,
                      decoration: InputDecoration(
                        filled: false,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withOpacity(.85), size: 21),
                        suffixIcon: _q.isEmpty
                            ? null
                            : IconButton(
                                icon: Icon(Icons.close_rounded, color: Colors.white.withOpacity(.85), size: 19),
                                onPressed: () { _searchCtl.clear(); setState(() => _q = ''); },
                              ),
                        hintText: 'Search store or courier',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(.7), fontSize: 14.5, fontWeight: FontWeight.w500),
                        border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FlowSegments(
                    labels: const ['Account-wise', 'Courier-wise'],
                    index: _view,
                    onDark: true,
                    onChanged: (i) => setState(() => _view = i),
                  ),
                ],
              ),
            ),
            Expanded(
              child: accounts.isEmpty
                  ? const SingleChildScrollView(
                      child: FlowEmpty(
                        icon: Icons.add_business_outlined,
                        title: 'No accounts yet',
                        body: 'Go to the Accounts tab and log in your first Meesho seller account to start tracking return OTPs.',
                      ),
                    )
                  : RefreshIndicator(
                      color: AppColors.blue,
                      onRefresh: () => store.refreshAll(),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                        children: [
                          _statStrip(accounts.length, carriers.length, store.totalReturns),
                          const SizedBox(height: 14),
                          if (_view == 0) ..._accountCards(accounts) else ..._carrierCards(carriers),
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _statStrip(int accs, int couriers, int returns) {
    Widget item(String label, String value, IconData icon) => Expanded(
          child: Column(
            children: [
              Icon(icon, size: 18, color: AppColors.blue),
              const SizedBox(height: 5),
              Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.navy)),
              Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.ink2, fontWeight: FontWeight.w600)),
            ],
          ),
        );
    return FlowCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(children: [
        item('Accounts', '$accs', Icons.storefront_outlined),
        Container(width: 1, height: 34, color: AppColors.skyLine),
        item('Couriers', '$couriers', Icons.local_shipping_outlined),
        Container(width: 1, height: 34, color: AppColors.skyLine),
        item('Returns', '$returns', Icons.assignment_return_outlined),
      ]),
    );
  }

  List<Widget> _accountCards(List<Account> accounts) {
    final list = accounts.where((a) => _hit([a.name, a.email, a.supplierId, ...a.otps.map((o) => o.carrier)])).toList();
    if (list.isEmpty) {
      return [FlowEmpty(icon: Icons.search_off_rounded, title: 'No matches', body: 'Nothing matched "$_q".')];
    }
    return list.map((a) {
      return FlowCard(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 8, 11),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.name, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (a.supplierId.isNotEmpty) 'ID: ${a.supplierId}',
                            a.email,
                            _ago(a.fetchedAt),
                          ].join(' · '),
                          style: const TextStyle(fontSize: 11.8, color: AppColors.ink2, fontWeight: FontWeight.w600),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _accStatus(a),
                  IconButton(
                    onPressed: store.busy ? null : () => store.refreshOne(a),
                    icon: a.status == AccStatus.working
                        ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.blue))
                        : const Icon(Icons.refresh_rounded, size: 21, color: AppColors.blueDeep),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            if (a.lastError != null && a.otps.isEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(color: const Color(0xFFFDECEA), borderRadius: BorderRadius.circular(10)),
                child: Text(a.lastError!, style: const TextStyle(color: AppColors.danger, fontSize: 12.3, fontWeight: FontWeight.w600)),
              ),
            ...a.otps.map((o) => _otpRow(o.carrier, o.time, o.otp, o.count)),
          ],
        ),
      );
    }).toList();
  }

  List<Widget> _carrierCards(List<CarrierGroup> carriers) {
    final list = carriers.where((g) => _hit([g.carrier, ...g.rows.map((r) => r.accountName)])).toList();
    if (list.isEmpty) {
      return [
        FlowEmpty(
          icon: carriers.isEmpty ? Icons.local_shipping_outlined : Icons.search_off_rounded,
          title: carriers.isEmpty ? 'No OTPs yet' : 'No matches',
          body: carriers.isEmpty ? 'Pull down to refresh and fetch the latest return OTPs.' : 'Nothing matched "$_q".',
        )
      ];
    }
    return list.map((g) {
      return FlowCard(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 11),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: AppColors.sky, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.local_shipping_rounded, size: 19, color: AppColors.blueDeep),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.carrier, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                        Text('${g.rows.length} account(s)', style: const TextStyle(fontSize: 11.8, color: AppColors.ink2, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  StatusPill('Returns: ${g.total}'),
                ],
              ),
            ),
            ...g.rows.map((r) => _otpRow(r.accountName, r.time, r.otp, r.count)),
          ],
        ),
      );
    }).toList();
  }

  Widget _otpRow(String title, String sub, String otp, int count) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.skyLine, width: 1))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppColors.navy)),
                if (sub.isNotEmpty)
                  Text(sub, style: const TextStyle(fontSize: 11.3, color: AppColors.ink2, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          OtpChip(otp: otp),
          const SizedBox(width: 10),
          SizedBox(
            width: 54,
            child: Text('Count\n$count',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11.5, color: AppColors.ink2, fontWeight: FontWeight.w700, height: 1.25)),
          ),
        ],
      ),
    );
  }

  Widget _accStatus(Account a) {
    if (a.otps.isNotEmpty) return StatusPill('${a.otps.length} OTP');
    switch (a.status) {
      case AccStatus.working:
        return const StatusPill('Working…', bg: AppColors.sky, fg: AppColors.blueDeep);
      case AccStatus.needsLogin:
        return const StatusPill('Login needed', bg: Color(0xFFFFF3D6), fg: AppColors.warn);
      case AccStatus.error:
        return const StatusPill('Error', bg: Color(0xFFFDECEA), fg: AppColors.danger);
      default:
        return const StatusPill('No OTPs', bg: AppColors.mintSoft, fg: Color(0xFF1E7A4A));
    }
  }
}
