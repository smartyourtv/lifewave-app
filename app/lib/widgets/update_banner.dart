import 'package:flutter/material.dart';

import '../theme.dart';

/// The ONE subtle update notification surface on Home (M5 standing
/// rule): a dismissible banner. Dismissing records that version as
/// seen in the UpdateService — it never nags again for that version.
/// Tapping Update opens the GitHub release asset in the browser; the
/// user installs it themselves. Never forced, never auto-installed.
class UpdateBanner extends StatelessWidget {
  final String versionName;
  final VoidCallback onUpdate;
  final VoidCallback onDismiss;
  const UpdateBanner({
    super.key,
    required this.versionName,
    required this.onUpdate,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: LwColors.tint,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.system_update_outlined,
                color: LwColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A new version is available (version $versionName)',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Text(
                    'Tap Update to download it from the app\'s GitHub '
                    'page. Nothing is installed without your tap.',
                    style: TextStyle(fontSize: 12),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed: onUpdate,
                        child: const Text('Update'),
                      ),
                      TextButton(
                        onPressed: onDismiss,
                        child: const Text('Dismiss'),
                      ),
                    ],
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
