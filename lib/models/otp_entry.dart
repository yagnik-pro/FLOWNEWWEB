class OtpEntry {
  final String carrier;
  final String otp;
  final int count;
  final String time;

  const OtpEntry({required this.carrier, required this.otp, this.count = 0, this.time = ''});

  Map<String, dynamic> toJson() => {'carrier': carrier, 'otp': otp, 'count': count, 'time': time};

  factory OtpEntry.fromJson(Map<String, dynamic> j) => OtpEntry(
        carrier: j['carrier'] ?? '',
        otp: j['otp'] ?? '',
        count: j['count'] ?? 0,
        time: j['time'] ?? '',
      );

  String get key => '$carrier|$otp';
}
