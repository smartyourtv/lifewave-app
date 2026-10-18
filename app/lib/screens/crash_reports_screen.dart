import 'package:flutter/material.dart';

import '../services/crash_reporter.dart';
import '../services/share_service.dart';
import '../theme.dart';

/// Crash & error reports — the in-app half of the standing crash-report
/// rule. Lists the reports the app saved on this device (newest first),
/// and lets the user read, share, or delete each one. Reports are never
/// sent anywhere from here unless the user taps Share.
class CrashReportsScreen extends StatefulWidget {
  final CrashReporter reporter;
  final ShareGateway share;
  const CrashReportsScreen({
    super.key,
    required this.reporter,
    required this.share,
  });

  @override
  State<CrashReportsScreen> createState() => _CrashReportsScreenState();
}

class _CrashReportsScreenState extends State<CrashReportsScreen> {
  late Future<List<CrashReportHeader>> _reportsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _reportsFuture = widget.reporter.listReports();
  }

  Future<void> _delete(CrashReportHeader header) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this report?'),
        content: const Text(
          'The copy saved in this app will be deleted. A copy may also '
          'be in your Downloads folder — deleting here does not delete '
          'that one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.reporter.deleteReport(header.fileName);
    if (mounted) setState(_reload);
  }

  void _openDetail(CrashReportHeader header) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => _CrashReportDetailScreen(
            reporter: widget.reporter,
            share: widget.share,
            header: header,
          ),
        ))
        .then((_) {
          if (mounted) setState(_reload);
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crash & error reports')),
      body: FutureBuilder<List<CrashReportHeader>>(
        future: _reportsFuture,
        builder: (context, snapshot) {
          final reports = snapshot.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'If the app ever stops working or hits a problem, it '
                'saves a report here and a copy goes to your Downloads '
                'folder. Nothing is ever sent anywhere unless you '
                'share a report yourself.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator())
              else if (reports == null || reports.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No problem reports saved — the app has not hit '
                      'a problem worth reporting on this device.',
                    ),
                  ),
                )
              else
                for (final r in reports)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        r.fatal
                            ? Icons.error_outline
                            : Icons.warning_amber_outlined,
                        color: r.fatal ? Colors.red : LwColors.deepNavy,
                      ),
                      title: Text(r.summaryLine),
                      subtitle: Text(
                        [
                          if (r.whenLabel.isNotEmpty) r.whenLabel,
                          r.kindLabel,
                        ].join(' · '),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Delete this report',
                        onPressed: () => _delete(r),
                      ),
                      onTap: () => _openDetail(r),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// One report, read in full, with Share and Delete.
class _CrashReportDetailScreen extends StatefulWidget {
  final CrashReporter reporter;
  final ShareGateway share;
  final CrashReportHeader header;
  const _CrashReportDetailScreen({
    required this.reporter,
    required this.share,
    required this.header,
  });

  @override
  State<_CrashReportDetailScreen> createState() =>
      _CrashReportDetailScreenState();
}

class _CrashReportDetailScreenState
    extends State<_CrashReportDetailScreen> {
  late Future<String?> _textFuture;
  String _shareNote = '';

  @override
  void initState() {
    super.initState();
    _textFuture = widget.reporter.readReport(widget.header.fileName);
  }

  Future<void> _share() async {
    final path = await widget.reporter.reportPath(widget.header.fileName);
    var ok = false;
    if (path != null) {
      ok = await widget.share.shareFile(path, text: 'LifeWave AI problem report');
    }
    if (!ok) {
      final text = await widget.reporter.readReport(widget.header.fileName);
      if (text != null) ok = await widget.share.shareText(text);
    }
    if (mounted) {
      setState(() => _shareNote = ok
          ? 'The share sheet opened — the report goes only where you send it.'
          : 'Sharing could not open on this device.');
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this report?'),
        content: const Text(
          'The copy saved in this app will be deleted. A copy may also '
          'be in your Downloads folder — deleting here does not delete '
          'that one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.reporter.deleteReport(widget.header.fileName);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Problem report')),
      body: FutureBuilder<String?>(
        future: _textFuture,
        builder: (context, snapshot) {
          final text = snapshot.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator())
              else if (text == null)
                const Text('This report could not be read any more.')
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(text),
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _share,
                    icon: const Icon(Icons.share, size: 16),
                    label: const Text('Share this report'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Delete'),
                  ),
                ],
              ),
              if (_shareNote.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_shareNote, style: const TextStyle(fontSize: 12)),
              ],
            ],
          );
        },
      ),
    );
  }
}
