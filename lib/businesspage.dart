
import 'dart:io';

import 'package:email_validator/email_validator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:infinite_sports_flutter/misc/navigation_controls.dart';
import 'package:infinite_sports_flutter/misc/web_view_stack.dart';
import 'package:infinite_sports_flutter/model/business.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

class BusinessPage extends StatefulWidget {
  const BusinessPage({super.key, required this.business, required this.address});

  final Business business;
  final String address;

  @override
  _BusinessPageState createState() => _BusinessPageState();
}

class _BusinessPageState extends State<BusinessPage> {
  @override
  Widget build(BuildContext context) {
    Business business = widget.business;
    String address = widget.address;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.5,
      child: Scaffold(
      appBar: AppBar(
        title: Text(business.name ?? "")
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(height: 250,child: business.logo,),
            Container(
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: !business.lat.isNaN ? 
                  ListTile(title: Text(address), onTap: () async {
                    String appleUrl = 'https://maps.apple.com/?saddr=&daddr=${business.lat},${business.long}&directionsmode=driving';
                    String googleUrl = 'https://www.google.com/maps/search/?api=1&query=${business.lat},${business.long}';

                    if (Platform.isIOS) {
                      if (await canLaunch(appleUrl)) {
                        await launch(appleUrl);
                      } else {
                        if (await canLaunch(googleUrl)) {
                          await launch(googleUrl);
                        } else {
                          throw 'Could not open the map.';
                        }
                      }
                    } else {
                      if (await canLaunch(googleUrl)) {
                        await launch(googleUrl);
                      } else {
                        throw 'Could not open the map.';
                      }
                    }
                  },) : const Text(""),),
            Container(
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: ListTile(title: const Text("Website"), enabled: business.url?.isNotEmpty ?? false, onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) {
                  WebViewController controller = WebViewController()
                  ..loadRequest(Uri.parse(business.url ?? ""));
                  return Scaffold(
                    appBar: AppBar(
                      title: const Text(""),
                      actions: [
                        NavigationControls(controller: controller)
                      ],
                    ),
                    body: WebViewStack(controller: controller,),
                  );
                },));
              },),
            ),
            Container(
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: ListTile(title: const Text("Call"), onTap: () async {
                var url = Uri.parse("tel:${business.phone ?? ""}");
                bool canCall = await canLaunchUrl(url);
                if (canCall) {
                  await launchUrl(url);
                }
              },),
            ),
            Padding(
              padding: const EdgeInsets.all(15),
              child: Text(business.description ?? ""),
            )
          ],
        )
      ),   
    ),
    );
  }
}
