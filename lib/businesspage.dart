
import 'dart:io';

import 'package:flutter/material.dart';
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
        centerTitle: true,
        title: Text(business.name ?? ""),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Row(children: [
              Expanded(child: SizedBox(height: 200,child: business.logo,),),
              Expanded(child: SizedBox(
                height: 200,
                child: ListView(
                  children: [
                    Visibility(
                      visible: business.lat.isFinite,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                        ),),
                        onPressed: () async {
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
                      }, 
                        child: Text(address),
                      ),),
                    Visibility(
                      visible: business.url?.isNotEmpty ?? false,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) {
                            WebViewController controller = WebViewController()
                            ..loadRequest(Uri.parse(business.url ?? ""));
                            return Scaffold(
                              appBar: AppBar(
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                foregroundColor: Colors.white,
                                title: const Text(""),
                                actions: [
                                  NavigationControls(controller: controller)
                                ],
                              ),
                              body: WebViewStack(controller: controller,),
                            );
                          },));
                        },
                        child: const Text("Website")
                      ),
                    ),
                    Visibility(
                      visible: business.phone?.isNotEmpty ?? false,
                      child: ElevatedButton(
                        onPressed: () async {
                        var url = Uri.parse("tel:${business.phone ?? ""}");
                        bool canCall = await canLaunchUrl(url);
                        if (canCall) {
                          await launchUrl(url);
                        }
                      }, 
                      child: const Text("Call")
                    ),)
                  ],
                )
              ),)
            ],),
            
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
