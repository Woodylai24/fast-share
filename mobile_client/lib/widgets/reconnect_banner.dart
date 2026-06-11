import 'package:flutter/material.dart';

class ReconnectBanner extends StatelessWidget {
  final bool isReconnecting;
  final bool isDisconnected;
  final int reconnectAttempt;
  final String? disconnectReason;
  final VoidCallback onConnectPressed;
  final VoidCallback onDisconnectPressed;

  const ReconnectBanner({
    super.key,
    required this.isReconnecting,
    required this.isDisconnected,
    required this.reconnectAttempt,
    this.disconnectReason,
    required this.onConnectPressed,
    required this.onDisconnectPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (!isDisconnected && !isReconnecting) return const SizedBox.shrink();

    final bgColor = isReconnecting ? Colors.orange.shade700 : Colors.red.shade700;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: bgColor,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (isReconnecting)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isReconnecting
                    ? 'Reconnecting... (attempt $reconnectAttempt)'
                    : (disconnectReason ?? 'Disconnected'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
            if (isReconnecting)
              TextButton(
                onPressed: onDisconnectPressed,
                child: const Text('Cancel', style: TextStyle(color: Colors.white)),
              ),
            if (!isReconnecting)
              TextButton(
                onPressed: onConnectPressed,
                child: const Text('Connect', style: TextStyle(color: Colors.white)),
              ),
          ],
        ),
      ),
    );
  }
}
