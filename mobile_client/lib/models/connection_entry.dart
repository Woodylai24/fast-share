/// Connection history entry
class ConnectionEntry {
  final String ip;
  final int port;
  final int httpPort;
  final String? networkName;
  final DateTime lastConnected;

  ConnectionEntry({
    required this.ip,
    required this.port,
    required this.httpPort,
    this.networkName,
    DateTime? lastConnected,
  }) : lastConnected = lastConnected ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'ip': ip,
    'port': port,
    'httpPort': httpPort,
    'networkName': networkName,
    'lastConnected': lastConnected.toIso8601String(),
  };

  factory ConnectionEntry.fromJson(Map<String, dynamic> json) {
    return ConnectionEntry(
      ip: json['ip'] as String,
      port: json['port'] as int,
      httpPort: json['httpPort'] as int? ?? 8081,
      networkName: json['networkName'] as String?,
      lastConnected: json['lastConnected'] != null
          ? DateTime.parse(json['lastConnected'] as String)
          : null,
    );
  }

  String get displayName => '$ip:$port';
}
