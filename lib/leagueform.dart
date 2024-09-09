import 'dart:io';

import 'package:email_validator/email_validator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/firebase_auth/firebase_auth_services.dart';
import 'package:infinite_sports_flutter/main.dart';
import 'package:infinite_sports_flutter/misc/navigation_controls.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/misc/web_view_stack.dart';
import 'package:infinite_sports_flutter/model/userinformation.dart';
import 'package:infinite_sports_flutter/navigations/current_livescore_navigation.dart';
import 'package:infinite_sports_flutter/signup.dart';
import 'package:image_picker/image_picker.dart';
import 'package:webview_flutter/webview_flutter.dart';

class LeagueForm extends StatefulWidget {
  const LeagueForm({super.key, required this.sport, required this.season, required this.oldInfo, required this.phoneNumber});

  final String sport;
  final String season;
  final UserInformation oldInfo;
  final String phoneNumber;

  @override
  _LeagueFormState createState() => _LeagueFormState();
}

class _LeagueFormState extends State<LeagueForm> {
  late TextEditingController _heightFeetController;
  late TextEditingController _ageController;
  late TextEditingController _heightInchesController;
  late TextEditingController _phoneController;
  late TextEditingController _positionController;
  late TextEditingController _commentController;
  bool seasonRulesRead = false;
  bool waiverRead = false;
  String? _selectedPosition;
  List<String> basketballPositions = ["Point Guard", "Shooting Guard", "Small Forward", "Power Forward", "Center"];
  List<String> futsalPositions = ["Goal Keeper", "Defender", "Midfielder", "Striker"];

  @override
  void initState() {
    super.initState();
    if (widget.oldInfo.age != 0) {
      _ageController = TextEditingController(text: widget.oldInfo.age.toString());
    } else {
      _ageController = TextEditingController();
    }
    if (widget.oldInfo.height.isNotEmpty) {
      _heightFeetController = TextEditingController(text: widget.oldInfo.height.split("\'")[0]);
      _heightInchesController = TextEditingController(text: widget.oldInfo.height.split("\'")[1]);
    } else {
      _heightFeetController = TextEditingController();
      _heightInchesController = TextEditingController();
    }
    _positionController = TextEditingController();
    _phoneController = TextEditingController(text: widget.phoneNumber);
    _commentController = TextEditingController();
  }

  @override
  void dispose() {
    _heightFeetController.dispose();
    _heightInchesController.dispose();
    _positionController.dispose();
    _phoneController.dispose();
    _commentController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    late List<String> positions;

    if (widget.sport == "Futsal") {
      positions = futsalPositions;
    } else {
      positions = basketballPositions;
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Sign Up Form"),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            Text("Please Add or Update the Following Information", style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center,),
            Padding(
              padding: const EdgeInsets.only(
                  left: 15.0, right: 15.0, top: 15, bottom: 0),
              child: TextFormField(
                keyboardType: TextInputType.number,
                controller: _heightFeetController,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Height',
                  hintText: 'Feet'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                  left: 15.0, right: 15.0, top: 15, bottom: 0),
              child: TextFormField(
                keyboardType: TextInputType.number,
                controller: _heightInchesController,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Inches'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                  left: 15.0, right: 15.0, top: 15, bottom: 0),
              child: TextFormField(
                keyboardType: TextInputType.number,
                controller: _ageController,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Age',),
              ),
            ),
            Container(
              margin: const EdgeInsets.all(15.0),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
              height: 55*positions.length.toDouble(),
              child: ListView.builder(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: positions.length,
                itemBuilder: (context, i) {
                  return RadioListTile(title: Text(positions[i]), value: positions[i], groupValue: _selectedPosition, onChanged: (value) {
                    setState(() {
                      _selectedPosition = value;
                    });
                  },);
                }
            ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                  left: 15.0, right: 15.0, top: 0, bottom: 0),
              child: TextFormField(
                keyboardType: TextInputType.phone,
                controller: _phoneController,
                decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Phone Number',
                    hintText: 'Enter phone number'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                  left: 15.0, right: 15.0, top: 15, bottom: 0),
              child: TextField(
                maxLines: 8,
                keyboardType: TextInputType.name,
                controller: _commentController,
                decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Comment'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                  left: 15.0, right: 15.0, top: 15, bottom: 0),
              child: Text("Please Open and Read the Rules and Waivers!", style: TextStyle(fontWeight: FontWeight.bold),)
            ),
            Padding(
              padding: const EdgeInsets.only(
                  left: 15.0, right: 15.0, top: 15, bottom: 0),
              child: Container(
                height: 50,
                width: MediaQuery.sizeOf(context).width,
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.inversePrimary, borderRadius: BorderRadius.circular(20)),
                child: ListTile(
                  title: Text("Season Rules", style: TextStyle(fontWeight: FontWeight.bold),),
                  trailing: Checkbox(value: seasonRulesRead, onChanged: (value) {
                    
                  },),
                  onTap: () async {
                    String rulesUrl = await getSignUpRules();
                    seasonRulesRead = true;
                    Navigator.push(context, MaterialPageRoute(builder:(context) {
                      WebViewController controller = WebViewController()..loadRequest(Uri.parse(rulesUrl));
                      return Scaffold(
                        appBar: AppBar(
                          title: Text("Season Rules"),
                        ),
                        body: WebViewStack(controller: controller,)
                      );
                    },)).then((value) {
                      setState(() {
                        
                      });
                    },);
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                  left: 15.0, right: 15.0, top: 15, bottom: 15),
              child: Container(
              height: 50,
              width: MediaQuery.sizeOf(context).width,
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.inversePrimary, borderRadius: BorderRadius.circular(20)),
              child: ListTile(
                title: Text("Waiver Conditions", style: TextStyle(fontWeight: FontWeight.bold),),
                trailing: Checkbox(value: waiverRead, onChanged: (value) {
                  
                },),
                onTap: () async {
                  String rulesUrl = await getSignUpWaiver();
                  waiverRead = true;
                  Navigator.push(context, MaterialPageRoute(builder:(context) {
                    WebViewController controller = WebViewController()..loadRequest(Uri.parse(rulesUrl));
                    return Scaffold(
                      appBar: AppBar(
                        title: Text("Waiver Conditions"),
                      ),
                      body: WebViewStack(controller: controller,)
                    );
                  },)).then((value) {
                    setState(() {
                      
                    });
                  },);
                },
              ),
            ),
            ),
            Container(
              height: 65,
              width: 250,
              padding: const EdgeInsets.only(bottom: 15),
              child: ElevatedButton(
                onPressed: (!seasonRulesRead || !waiverRead || _heightFeetController.value.text.isEmpty || _heightInchesController.value.text.isEmpty || _ageController.value.text.isEmpty || _positionController.value.text.isEmpty || _phoneController.value.text.isEmpty) ? null : () async {await _register();},
                /*onPressed: () async {
                  await _register();
                },*/
                child: const Text(
                  'Register',
                  style: TextStyle(color: Colors.white, fontSize: 25),
                ),
                style: ButtonStyle(
                    backgroundColor: MaterialStateProperty.resolveWith(
                      (states) {
                        if (states.contains(MaterialState.disabled)) {
                          return Colors.grey;
                        } else {
                          return Theme.of(context).primaryColor;
                        }
                      },
                    ),
                  ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _register() async {
    var alertInfo = await getSignUpInformation();
    showDialog<String>(
      context: context,
      builder: (BuildContext context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text("Before Proceeding, " + alertInfo),
              Text("Proceed?"),
              Row(children: [
                Expanded(
                  child: TextButton(
                    onPressed: () async {
                      try {
                        var userInformation = UserInformation();
                        userInformation.age = int.parse(_ageController.value.text);
                        if (basketballPositions.contains(_selectedPosition)) {
                          userInformation.basketballPosition = _selectedPosition!;
                          userInformation.futsalPosition = widget.oldInfo.futsalPosition;
                        } else {
                          userInformation.futsalPosition = _selectedPosition!;
                          userInformation.basketballPosition = widget.oldInfo.basketballPosition;
                        }
                        userInformation.height = "${_heightFeetController.value.text}\'${_heightInchesController.value.text}";
                        await addUpdateInfo(userInformation, _phoneController.value.text);
                        await signUpToPlay(widget.sport, widget.season);
                        if (_commentController.value.text.isNotEmpty) {
                          await addComment(widget.sport, widget.season, _commentController.value.text);
                        }
                        if (!await isSignedUp(widget.sport, widget.season)) {
                          throw Exception("User is not signed up");
                        }
                        Navigator.pop(context);
                        showDialog<String>(
                          context: context, 
                          builder: (context) => Dialog(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                children: [
                                  Text("Success! You have registered for " + widget.sport + " League Season " + widget.season + "! Make sure to pay by the due date or click Open Venmo to pay now! Thank You!"),
                                  TextButton(child: Text("Open Venmo"), onPressed: () {
                                    Navigator.push(context, MaterialPageRoute(builder:(context) {
                                      WebViewController controller = WebViewController()..loadRequest(Uri.parse("https://venmo.com/infinite-sports"));
                                      return Scaffold(
                                        appBar: AppBar(
                                          title: Text("Venmo"),
                                        ),
                                        body: WebViewStack(controller: controller,)
                                      );
                                    },));
                                  },)
                                ],
                              ),
                            ),
                          )
                        );
                      } catch (e) {
                        Navigator.pop(context);
                        showDialog(
                          context: context, 
                          builder: (context) => Dialog(
                            child: SizedBox(
                              height: 105,
                              child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                children: [
                                  Text("Failed! Something went wrong! Try Again! Contact Us if you keep getting this message!"),
                                  TextButton(child: Text("OK"), onPressed: () {
                                    Navigator.pop(context);
                                  },)
                                ],
                              ),
                            ),
                            )
                          )
                        );
                      }
                    }, 
                    child: Text("Register"),
                  )
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('Close'),
                  )
                ),
              ],),
            ],
          ),
        ),
      ),);
  }
  
}