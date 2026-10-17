import 'package:flutter/material.dart';

import '../services/emotion.dart';

import '../services/compliance.dart';
import '../services/compliance_guide.dart';
import '../widgets/social_widgets.dart';
import 'guide_screen.dart';

/// Standalone compliance checker (SPEC §7.9 rider): paste or type ANY
/// text — a post, a message, something you found — and see exactly
/// what the scanner flags, grouped by kind, with a plain-language
/// "why" and a suggested compliant direction for each flag. The same
/// scanner runs inside the post generator, reply drafts and fact
/// cards. It NEVER silently rewrites text.
class ComplianceCheckerScreen extends StatefulWidget {
  final SocialDeps deps;
  const ComplianceCheckerScreen({super.key, required this.deps});

  @override
  State<ComplianceCheckerScreen> createState() =>
      _ComplianceCheckerScreenState();
}

class _ComplianceCheckerScreenState extends State<ComplianceCheckerScreen> {
  late final ComplianceGuide _guide =
      ComplianceGuide.fromDb(widget.deps.db.entries);
  final _controller = TextEditingController();
  ComplianceReport? _report;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _check() {
    setState(() {
      _report = const ComplianceScanner().scan(_controller.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dontEntry = _guide.dontEntry;
    final doEntry = _guide.doEntry;
    return Scaffold(
      appBar: AppBar(title: const Text('Compliance checker'), actions: [HelpButton(screenKey: 'compliance', brand: widget.deps.brand, services: widget.deps.m2, db: widget.deps.db, share: widget.deps.share, emotionLevel: EmotionLevel.warm)],),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Paste any post, reply or message here BEFORE you share it. '
            'The checker looks for medical claims, restricted terms, '
            'promised results and income claims — the wording the '
            'playbook says never to use. It flags and explains; it '
            'never rewrites your words for you.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 8,
            minLines: 4,
            decoration: InputDecoration(
              labelText: 'Text to check',
              hintText: 'Paste or type the text here…',
              border: const OutlineInputBorder(),
              suffixIcon: DictateButton(
                services: widget.deps.m2,
                onText: (t) => setState(() {
                  _controller.text = t;
                  _report = null;
                }),
              ),
            ),
            onChanged: (_) => setState(() => _report = null),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _check,
            icon: const Icon(Icons.fact_check),
            label: const Text('Check this text'),
          ),
          const SizedBox(height: 16),
          if (_report != null)
            ComplianceResultsView(report: _report!, guide: _guide)
          else
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('No check run yet'),
                subtitle: Text(
                    'Results appear here, grouped by kind, with the '
                    'exact phrases flagged.'),
              ),
            ),
          if (dontEntry != null || doEntry != null) ...[
            const Divider(height: 32),
            Text('The playbook rules behind this checker',
                style: Theme.of(context).textTheme.titleMedium),
            if (dontEntry != null)
              ExpansionTile(
                title: Text(dontEntry.title),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(dontEntry.body),
                  ),
                ],
              ),
            if (doEntry != null)
              ExpansionTile(
                title: Text(doEntry.title),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(doEntry.body),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
