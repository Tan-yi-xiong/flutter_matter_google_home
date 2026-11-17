import 'package:flutter/material.dart';
import 'package:flutter_matter_google_home/flutter_matter_google_home.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Google Home Matter Example',
      home: CommissioningExamplePage(),
    );
  }
}

class CommissioningExamplePage extends StatefulWidget {
  const CommissioningExamplePage({super.key});

  @override
  State<CommissioningExamplePage> createState() =>
      _CommissioningExamplePageState();
}

class _CommissioningExamplePageState extends State<CommissioningExamplePage> {
  final GoogleHomeMatterCommissioner _commissioner =
      GoogleHomeMatterCommissioner();
  final TextEditingController _payloadController = TextEditingController();

  GoogleHomeMatterTarget? _target;
  GoogleHomeMatterSession? _session;
  String _status = 'Enter a Matter onboarding payload to begin.';
  bool _busy = false;
  bool _handoffReady = false;

  @override
  void dispose() {
    _payloadController.dispose();
    super.dispose();
  }

  Future<void> _checkAvailability() async {
    await _run(() async {
      final availability = await _commissioner.checkAvailability();
      _setStatus(
        '${availability.status.wireName}: ${availability.message}'
        '${availability.playServicesVersion == null ? '' : '\nPlay Services ${availability.playServicesVersion}'}',
      );
    });
  }

  Future<void> _commissionOnly() async {
    final target = _target;
    if (target == null) {
      _setStatus('Select a Google target first.');
      return;
    }
    await _run(() async {
      final result = await _commissioner.commission(
        onboardingPayload: _payloadController.text.trim(),
        target: target,
      );
      _setStatus(
        'Google commissioning completed for ${result.target.wireName}.'
        '${result.deviceName == null ? '' : '\nDevice: ${result.deviceName}'}',
      );
    });
  }

  Future<void> _requestModuleInstall() async {
    await _run(() async {
      final response = await _commissioner.requestModuleInstall();
      _setStatus(
        'Home module install requested: '
        'alreadyInstalled=${response.alreadyInstalled}'
        '${response.sessionId == null ? '' : ', sessionId=${response.sessionId}'}',
      );
    });
  }

  Future<void> _startHandoffSession() async {
    final target = _target;
    if (target == null) {
      _setStatus('Select a Google target first.');
      return;
    }
    _session = null;
    _handoffReady = false;
    await _run(() async {
      final session = await _commissioner.startHandoffSession(
        onboardingPayload: _payloadController.text.trim(),
        target: target,
      );
      _session = session;
      final handoff = await session.handoff;
      if (!mounted) {
        return;
      }
      setState(() {
        _handoffReady = true;
        _status =
            'Handoff ready. Continue the second fabric externally.\n'
            'port=${handoff.port}, vendor=${handoff.vendorId}, '
            'product=${handoff.productId}';
      });
    });
  }

  Future<void> _reportHandoff({required bool succeeded}) async {
    final session = _session;
    if (session == null) {
      return;
    }
    await _run(() async {
      await session.completeHandoff(
        succeeded: succeeded,
        errorCode: succeeded ? null : 1,
      );
      final result = await session.result;
      _setStatus(
        'Session completed: ${result.target.wireName}; '
        'secondFabric=${succeeded ? 'success' : 'failure'}',
      );
    });
    if (mounted) {
      setState(() {
        _session = null;
        _handoffReady = false;
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
    });
    try {
      await action();
    } on GoogleHomeMatterException catch (error) {
      _setStatus(
        'Failure at ${error.stage.wireName}: ${error.message}'
        '${error.googleFabricSucceeded ? '\nGoogle fabric had already succeeded.' : ''}',
      );
    } on ArgumentError catch (error) {
      _setStatus('Input error: ${error.message}');
    } catch (error) {
      _setStatus('Unexpected error: $error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _setStatus(String value) {
    if (!mounted) {
      return;
    }
    setState(() {
      _status = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Google Home Matter Example')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          const Text(
            'The onboarding payload stays in memory only. '
            'Do not paste it into logs or reports.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _payloadController,
            enableSuggestions: false,
            autocorrect: false,
            maxLines: 1,
            decoration: const InputDecoration(
              labelText: 'Matter onboarding payload',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<GoogleHomeMatterTarget>(
            initialValue: _target,
            decoration: const InputDecoration(
              labelText: 'Google target',
              border: OutlineInputBorder(),
            ),
            hint: const Text('Select an explicit target'),
            items: GoogleHomeMatterTarget.values
                .map(
                  (target) => DropdownMenuItem<GoogleHomeMatterTarget>(
                    value: target,
                    child: Text(target.wireName),
                  ),
                )
                .toList(growable: false),
            onChanged: _busy
                ? null
                : (target) {
                    if (target != null) {
                      setState(() {
                        _target = target;
                      });
                    }
                  },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.tonal(
                onPressed: _busy ? null : _checkAvailability,
                child: const Text('Check availability'),
              ),
              FilledButton.tonal(
                onPressed: _busy ? null : _requestModuleInstall,
                child: const Text('Prepare Home module'),
              ),
              FilledButton(
                onPressed: _busy || _target == null ? null : _commissionOnly,
                child: const Text('Commission only'),
              ),
              FilledButton(
                onPressed: _busy || _target == null
                    ? null
                    : _startHandoffSession,
                child: const Text('Start handoff session'),
              ),
              FilledButton(
                onPressed: _busy || !_handoffReady
                    ? null
                    : () => _reportHandoff(succeeded: true),
                child: const Text('Report second fabric success'),
              ),
              OutlinedButton(
                onPressed: _busy || !_handoffReady
                    ? null
                    : () => _reportHandoff(succeeded: false),
                child: const Text('Report second fabric failure'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 12),
          SelectableText(_status),
        ],
      ),
    );
  }
}
