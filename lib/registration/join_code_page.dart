import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:infinite_sports_flutter/registration/registration_form_page.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

/// Joiner-path code entry: 6 pin boxes, auto-uppercased, checked against
/// this registration's teams on every keystroke (matchJoinCode). An approved
/// match shows "Joining {team}" + Continue; a pending/rejected team's code
/// and unknown codes get friendly errors (spec section 7). Admin-edited
/// codes shorter than 6 characters still match because the check runs on
/// every change, not only on completion.
class JoinCodePage extends StatefulWidget {
  final String regId;
  final RegistrationConfig config;

  const JoinCodePage({super.key, required this.regId, required this.config});

  @override
  State<JoinCodePage> createState() => _JoinCodePageState();
}

class _JoinCodePageState extends State<JoinCodePage> {
  final TextEditingController _controller = TextEditingController();
  Map<String, RegTeam>? _teams; // null while loading
  RegTeam? _match;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    final teams = await RegistrationService.getTeams(widget.regId);
    if (!mounted) return;
    setState(() => _teams = teams);
    _check();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _check() {
    final teams = _teams;
    if (teams == null) return; // still loading
    final entered = _controller.text.trim();
    final result = matchJoinCode(teams, entered);
    setState(() {
      if (result.status == 'ok') {
        _match = result.team;
        _error = null;
      } else if (result.status == 'notApproved') {
        _match = null;
        _error =
            'That team is still awaiting approval — ask your captain to check back soon.';
      } else {
        _match = null;
        // Only complain once all six boxes are filled; partial input just
        // clears the state.
        _error = entered.length >= 6
            ? "That code doesn't match any team in this registration."
            : null;
      }
    });
  }

  void _continue() {
    final team = _match;
    if (team == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) {
      return RegistrationFormPage(
          regId: widget.regId,
          config: widget.config,
          path: 'joiner',
          team: team);
    }));
  }

  @override
  Widget build(BuildContext context) {
    final loading = _teams == null;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(widget.config.label),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(15),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text('Enter your team code',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                textAlign: TextAlign.center),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 15),
            child: Text(
                'Your captain got a 6-character code when the team was approved.',
                textAlign: TextAlign.center),
          ),
          PinCodeTextField(
            appContext: context,
            length: 6,
            controller: _controller,
            autoDisposeControllers: false,
            enabled: !loading,
            keyboardType: TextInputType.visiblePassword,
            textCapitalization: TextCapitalization.characters,
            animationType: AnimationType.fade,
            backgroundColor: Colors.transparent,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
              TextInputFormatter.withFunction((oldV, newV) =>
                  newV.copyWith(text: newV.text.toUpperCase())),
            ],
            textStyle:
                const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            pinTheme: PinTheme(
              shape: PinCodeFieldShape.box,
              borderRadius: BorderRadius.circular(8),
              fieldHeight: 52,
              fieldWidth: 44,
              activeColor: Theme.of(context).colorScheme.primary,
              selectedColor: Theme.of(context).colorScheme.primary,
              inactiveColor: Theme.of(context).dividerColor,
            ),
            onChanged: (_) => _check(),
            onCompleted: (_) => _check(),
          ),
          if (loading)
            Center(
                child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_match != null) ...[
            const SizedBox(height: 10),
            Card(
              elevation: 2,
              child: ListTile(
                leading: const Icon(Icons.verified, color: Colors.green),
                title: Text('Joining ${_match!.name}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(_match!.codeWaivesPayment
                    ? 'Your captain covers the team fee — no payment needed.'
                    : "You'll pay the \$${widget.config.fee} player fee after registering."),
              ),
            ),
            const SizedBox(height: 15),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: _continue,
                child: const Text('Continue', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
