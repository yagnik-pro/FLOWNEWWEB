import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../theme.dart';
import '../services/background.dart';
import '../services/meesho_api.dart';
import '../services/web_session.dart';
import '../widgets/brand.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        return Column(
          children: [
            const FlowHeader(title: 'Settings', subtitle: 'Schedule · Alerts · Background'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
                children: [
                  _section('Auto-refresh'),
                  FlowCard(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Fetch new OTPs every',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8, runSpacing: 8,
                          children: [0, 2, 5, 10, 15, 30, 60].map((m) {
                            final on = store.intervalMin == m;
                            return GestureDetector(
                              onTap: () => store.setInterval(m),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  gradient: on ? AppColors.otpGradient : null,
                                  color: on ? null : AppColors.sky,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  m == 0 ? 'Off' : (m == 60 ? '1 hour' : '$m min'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 13.5,
                                    color: on ? Colors.white : AppColors.ink2,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'OTP Flow checks every account on this schedule and refreshes the list automatically.',
                          style: TextStyle(color: AppColors.ink2, fontSize: 12.5, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  _section('Alerts & background'),
                  FlowCard(
                    child: Column(
                      children: [
                        SwitchListTile(
                          value: store.notifyOnNew,
                          activeColor: AppColors.blue,
                          onChanged: store.setNotify,
                          title: const Text('Notify on new OTP', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          subtitle: const Text('Get a push the moment a courier OTP appears',
                              style: TextStyle(fontSize: 12.4, color: AppColors.ink2)),
                          contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
                        ),
                        const Divider(height: 1, color: AppColors.skyLine),
                        SwitchListTile(
                          value: store.backgroundEnabled,
                          activeColor: AppColors.blue,
                          onChanged: (v) async {
                            await store.setBackground(v);
                            if (v) {
                              final ok = await Background.enable();
                              if (!ok && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                  content: Text('Android denied background permission'),
                                  margin: EdgeInsets.all(14),
                                ));
                              }
                            } else {
                              await Background.disable();
                            }
                          },
                          title: const Text('Keep running 24/7', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          subtitle: const Text('Keeps refreshing even when the app is closed',
                              style: TextStyle(fontSize: 12.4, color: AppColors.ink2)),
                          contentPadding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
                        ),
                      ],
                    ),
                  ),
                  _section('Troubleshooting'),
                  FlowCard(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.login_rounded, color: AppColors.blueDeep),
                          title: const Text('Session diagnostics', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                          subtitle: const Text('What Meesho replied to the last request', style: TextStyle(fontSize: 12.3, color: AppColors.ink2)),
                          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.ink2),
                          onTap: () => _showText(context, 'Session diagnostics', WebSession.lastDebug,
                              'Nothing yet in this session.\n\nTap Relogin or Refresh on an account, then come back here.'),
                        ),
                        const Divider(height: 1, color: AppColors.skyLine),
                        ListTile(
                          leading: const Icon(Icons.bug_report_outlined, color: AppColors.blueDeep),
                          title: const Text('Last raw API response', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                          subtitle: const Text('Only useful if OTPs stop showing up', style: TextStyle(fontSize: 12.3, color: AppColors.ink2)),
                          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.ink2),
                          onTap: () => _showRaw(context),
                        ),
                        const Divider(height: 1, color: AppColors.skyLine),
                        ListTile(
                          leading: const Icon(Icons.logout_rounded, color: AppColors.warn),
                          title: const Text('Relogin every account', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                          subtitle: const Text('Clears sessions and signs in fresh', style: TextStyle(fontSize: 12.3, color: AppColors.ink2)),
                          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.ink2),
                          onTap: store.busy ? null : () => store.reloginAll(List.of(store.accounts)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  const Center(child: BrandMark(size: 92, showTagline: true)),
                  const SizedBox(height: 10),
                  const Center(
                    child: Text('Version 1.0.0', style: TextStyle(color: AppColors.ink2, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E8),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFF3DC8A)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 18, color: AppColors.warn),
                        SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'Your email, password and OTPs never leave this phone — there is no server. '
                            'Automating the supplier panel may go against Meesho\'s Terms of Service; use at your own risk.',
                            style: TextStyle(fontSize: 12.2, color: Color(0xFF6B4F00), height: 1.45, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 0, 10),
        child: Text(t.toUpperCase(),
            style: const TextStyle(fontSize: 11.5, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: AppColors.ink2)),
      );

  void _showRaw(BuildContext context) => _showText(
        context,
        'Raw OTP response',
        MeeshoApi.lastRawResponse,
        'Nothing captured yet.\n\nThis only fills in when a refresh returns no OTPs — '
            'so an empty box here usually means everything is working.',
      );

  void _showText(BuildContext context, String title, String? content, String emptyMsg) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => DraggableScrollableSheet(
        expand: false, initialChildSize: .7, maxChildSize: .92,
        builder: (_, ctl) => Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 42, height: 4,
              decoration: BoxDecoration(color: AppColors.skyLine, borderRadius: BorderRadius.circular(999)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                  if (content != null)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: content));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied — paste it in the chat'), margin: EdgeInsets.all(14)),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: SingleChildScrollView(
                controller: ctl,
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                child: SelectableText(
                  content ?? emptyMsg,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace', height: 1.5, color: AppColors.ink),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
