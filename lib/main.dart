import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';
import 'services/store.dart';
import 'services/notifier.dart';
import 'services/background.dart';
import 'services/web_session.dart';
import 'screens/otp_screen.dart';
import 'screens/accounts_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/brand.dart';

final store = AppStore();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const OtpFlowApp());
}

class OtpFlowApp extends StatelessWidget {
  const OtpFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OTP Flow',
      navigatorKey: WebSession.navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const SplashGate(),
    );
  }
}

/// Brand splash → boots services → main shell.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});
  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final t0 = DateTime.now();
    await Notifier.init();
    await store.load();
    if (store.backgroundEnabled) await Background.enable();
    // keep the splash on screen for at least 1.1s so it doesn't flash
    final elapsed = DateTime.now().difference(t0);
    final wait = const Duration(milliseconds: 1100) - elapsed;
    if (wait > Duration.zero) await Future.delayed(wait);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 350),
          pageBuilder: (_, __, ___) => const Shell(),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.gradient),
        child: const Center(child: BrandMark(size: 190, showTagline: true, light: true)),
      ),
    );
  }
}

/// Bottom-nav shell.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [const OtpScreen(), const AccountsScreen(), const SettingsScreen()];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: AppColors.navy.withOpacity(.08), blurRadius: 16, offset: const Offset(0, -3))],
        ),
        child: SafeArea(
          top: false,
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: Colors.white,
              indicatorColor: AppColors.sky,
              labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: s.contains(WidgetState.selected) ? AppColors.blueDeep : AppColors.ink2,
                  )),
              iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
                    color: s.contains(WidgetState.selected) ? AppColors.blueDeep : AppColors.ink2,
                    size: 24,
                  )),
            ),
            child: NavigationBar(
              height: 64,
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.vpn_key_outlined), selectedIcon: Icon(Icons.vpn_key), label: 'OTPs'),
                NavigationDestination(icon: Icon(Icons.people_alt_outlined), selectedIcon: Icon(Icons.people_alt), label: 'Accounts'),
                NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: 'Settings'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
