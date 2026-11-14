// Way back fix round, Important 1: the ONE way a tap opens a registration.
//
// The home banner, the registration list's "My registrations" rows and its
// "Open for sign-up" rows all come here: the config and "already
// registered?" are confirmed with the server first
// (RegistrationService.checkEntry, server-first, one 8 s bound) and the
// outcome is followed —
//   registered → the status page, with the SERVER config;
//   not registered, open → the path page;
//   not registered, closed → "Registration is closed";
//   deleted → "This registration is no longer available.";
//   cannot check → "couldn't check" with Try again.
// A saved copy never opens the status page (and its pay actions) on its
// own.

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/registration/live_registration_config.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_path_page.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';
import 'package:infinite_sports_flutter/registration/registration_status_page.dart';

class RegistrationOpen {
  RegistrationOpen._();

  /// Test seams: the server check and the pages it leads to.
  @visibleForTesting
  static Future<({RegistrationRoute route, RegistrationConfig? config})>
      Function(String regId)? checkOverride;
  @visibleForTesting
  static Widget Function(String regId, RegistrationConfig config)?
      statusPageOverride;
  @visibleForTesting
  static Widget Function(String regId, RegistrationConfig config)?
      pathPageOverride;

  /// Checks [regId] with the server and follows the outcome. Completes when
  /// the check is done (callers show their spinner until then).
  static Future<void> open(BuildContext context, String regId) async {
    final entry =
        await (checkOverride ?? RegistrationService.checkEntry)(regId);
    if (!context.mounted) return;
    final config = entry.config;
    final messenger = ScaffoldMessenger.of(context);
    switch (entry.route) {
      case RegistrationRoute.status:
        Navigator.push(context, MaterialPageRoute(builder: (_) {
          return statusPageOverride?.call(regId, config!) ??
              RegistrationStatusPage(regId: regId, config: config!);
        }));
      case RegistrationRoute.register:
        Navigator.push(context, MaterialPageRoute(builder: (_) {
          return pathPageOverride?.call(regId, config!) ??
              RegistrationPathPage(regId: regId, config: config!);
        }));
      case RegistrationRoute.closed:
        messenger.showSnackBar(
            const SnackBar(content: Text('Registration is closed')));
      case RegistrationRoute.unavailable:
        messenger.showSnackBar(
            const SnackBar(content: Text(kRegistrationUnavailable)));
      case RegistrationRoute.couldNotCheck:
        messenger.showSnackBar(SnackBar(
          content: const Text(kRegistrationCouldNotCheck),
          action: SnackBarAction(
            label: 'Try again',
            onPressed: () {
              if (context.mounted) open(context, regId);
            },
          ),
        ));
    }
  }
}
