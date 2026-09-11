import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';

/// The OTP Flow logo + wordmark.
class BrandMark extends StatelessWidget {
  final double size;
  final bool showTagline;
  final bool light;
  const BrandMark({super.key, this.size = 120, this.showTagline = false, this.light = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/images/logo.png', width: size, height: size, fit: BoxFit.contain),
        if (showTagline) ...[
          const SizedBox(height: 6),
          Text(
            'RECEIVE  ·  MANAGE  ·  STAY AHEAD',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 2.2,
              fontWeight: FontWeight.w800,
              color: light ? Colors.white.withOpacity(.85) : AppColors.ink2,
            ),
          ),
        ],
      ],
    );
  }
}

/// Gradient header used at the top of every screen.
class FlowHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> actions;
  final Widget? bottom;
  const FlowHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions = const [],
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.gradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
      ),
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 14, left: 18, right: 12, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset('assets/images/logo.png', width: 38, height: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -.2)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(.78), fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              ...actions,
            ],
          ),
          if (bottom != null) ...[const SizedBox(height: 14), bottom!],
        ],
      ),
    );
  }
}

/// Pill segment control (Account-wise / Courier-wise).
class FlowSegments extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final bool onDark;
  const FlowSegments({super.key, required this.labels, required this.index, required this.onChanged, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withOpacity(.15) : AppColors.sky,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final on = i == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: on ? [BoxShadow(color: AppColors.navy.withOpacity(.12), blurRadius: 8, offset: const Offset(0, 2))] : null,
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: on ? AppColors.blueDeep : (onDark ? Colors.white.withOpacity(.9) : AppColors.ink2),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// White rounded card.
class FlowCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  const FlowCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.skyLine, width: 1.2),
        boxShadow: [BoxShadow(color: AppColors.navy.withOpacity(.05), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: child,
    );
  }
}

/// Tap-to-copy OTP chip with the brand gradient.
class OtpChip extends StatefulWidget {
  final String otp;
  const OtpChip({super.key, required this.otp});
  @override
  State<OtpChip> createState() => _OtpChipState();
}

class _OtpChipState extends State<OtpChip> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.otp));
    HapticFeedback.mediumImpact();
    setState(() => _copied = true);
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Copied ${widget.otp}'),
          duration: const Duration(milliseconds: 1200),
          margin: const EdgeInsets.all(14),
        ));
    }
    await Future.delayed(const Duration(milliseconds: 1100));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _copy,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: _copied
              ? const LinearGradient(colors: [AppColors.mint, Color(0xFF23A862)])
              : AppColors.otpGradient,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [BoxShadow(color: AppColors.blue.withOpacity(.3), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.otp,
              style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18,
                letterSpacing: 1.6, fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 6),
            Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: 15, color: Colors.white.withOpacity(.9)),
          ],
        ),
      ),
    );
  }
}

/// Small status pill.
class StatusPill extends StatelessWidget {
  final String text;
  final Color bg, fg;
  const StatusPill(this.text, {super.key, this.bg = AppColors.sky, this.fg = AppColors.blueDeep});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}

/// Empty-state block.
class FlowEmpty extends StatelessWidget {
  final IconData icon;
  final String title, body;
  const FlowEmpty({super.key, required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 30),
      child: Column(
        children: [
          Container(
            width: 78, height: 78,
            decoration: BoxDecoration(color: AppColors.sky, shape: BoxShape.circle),
            child: Icon(icon, size: 36, color: AppColors.blue),
          ),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.ink2, fontSize: 14, height: 1.4)),
        ],
      ),
    );
  }
}
