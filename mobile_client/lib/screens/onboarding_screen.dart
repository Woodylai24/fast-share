import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fast_share_mobile/services/settings_service.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const _steps = [
    {
      'icon': Icons.rocket_launch_rounded,
      'title': 'Welcome to Fast Share',
      'description':
          'Share files, text, and clipboard between your PC and phone — fast, private, and over your local network.',
    },
    {
      'icon': Icons.qr_code_scanner,
      'title': 'How to Connect',
      'description':
          'Open Fast Share on your PC. Scan the QR code shown on the screen, or enter the IP address manually.',
    },
    {
      'icon': Icons.share,
      'title': 'What You Can Do',
      'description':
          'Send files of any size, share text messages, sync your clipboard, and more — all encrypted over your local network.',
      'features': true,
    },
    {
      'icon': Icons.laptop,
      'title': 'Get the PC Client',
      'description':
          'You\'ll need Fast Share on your PC to connect. Download it and get started!',
      'download_url': 'https://github.com/Woodylai24/fast-share/releases',
      'download_label': 'Download for PC',
    },
    {
      'icon': Icons.check_circle_outline,
      'title': 'You\'re All Set!',
      'description':
          'Connect to your PC and start sharing. Happy transferring!',
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _complete();
    }
  }

  Future<void> _complete() async {
    await SettingsService.setOnboardingComplete(true);
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isLast = _currentPage == _steps.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton(
                  onPressed: _complete,
                  child: const Text('Skip'),
                ),
              ),
            ),
            // Page content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _steps.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) {
                  final step = _steps[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          step['icon'] as IconData,
                          size: 80,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(height: 32),
                        Text(
                          step['title'] as String,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          step['description'] as String,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.7),
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (step['features'] == true) ...[
                          const SizedBox(height: 24),
                          _FeatureGrid(theme: theme),
                        ],
                        if (step['download_url'] != null) ...[
                          const SizedBox(height: 24),
                          OutlinedButton.icon(
                            onPressed: () {
                              final url = Uri.parse(step['download_url'] as String);
                              launchUrl(url, mode: LaunchMode.externalApplication);
                            },
                            icon: const Icon(Icons.download),
                            label: Text(step['download_label'] as String),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            // Navigation
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Back button
                  if (_currentPage > 0)
                    TextButton(
                      onPressed: () {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                      child: const Text('Back'),
                    )
                  else
                    const SizedBox(width: 70),
                  // Dots
                  Row(
                    children: List.generate(_steps.length, (index) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPage == index ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? colorScheme.primary
                              : colorScheme.onSurface.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  // Next / Get Started
                  ElevatedButton(
                    onPressed: _nextPage,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: Text(isLast ? 'Get Started' : 'Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  final ThemeData theme;

  const _FeatureGrid({required this.theme});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.5,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: [
        _FeatureCard(
          icon: Icons.folder_outlined,
          title: 'File Sharing',
          desc: 'Any size',
          theme: theme,
        ),
        _FeatureCard(
          icon: Icons.message_outlined,
          title: 'Messages',
          desc: 'Quick text',
          theme: theme,
        ),
        _FeatureCard(
          icon: Icons.content_copy,
          title: 'Clipboard',
          desc: 'Copy & paste',
          theme: theme,
        ),
        _FeatureCard(
          icon: Icons.lock_outline,
          title: 'Encrypted',
          desc: 'E2EE built-in',
          theme: theme,
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final ThemeData theme;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 24, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Text(desc, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            ],
          ),
        ],
      ),
    );
  }
}
