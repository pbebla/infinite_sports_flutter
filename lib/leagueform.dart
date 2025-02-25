
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/misc/web_view_stack.dart';
import 'package:infinite_sports_flutter/model/userinformation.dart';
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
  late TextEditingController _commentController;
  bool seasonRulesRead = false;
  bool waiverRead = false;
  List<String> basketballPositions = ["Point Guard", "Shooting Guard", "Small Forward", "Power Forward", "Center"];
  List<String> futsalPositions = ["Goal Keeper", "Defender", "Midfielder", "Striker"];
  List<bool> isSelected = List.empty(growable: true);
  List<String> positions = List.empty();

  @override
  void initState() {
    super.initState();
    if (widget.oldInfo.age != 0) {
      _ageController = TextEditingController(text: widget.oldInfo.age.toString());
    } else {
      _ageController = TextEditingController();
    }
    if (widget.oldInfo.height.isNotEmpty) {
      _heightFeetController = TextEditingController(text: widget.oldInfo.height.split("'")[0]);
      _heightInchesController = TextEditingController(text: widget.oldInfo.height.split("'")[1]);
    } else {
      _heightFeetController = TextEditingController();
      _heightInchesController = TextEditingController();
    }
    _phoneController = TextEditingController(text: widget.phoneNumber);
    _commentController = TextEditingController();
    late List<String> oldPositions;
    if (widget.sport == "Futsal") {
      positions = futsalPositions;
      oldPositions = widget.oldInfo.futsalPosition.split(';');
    } else {
      positions = basketballPositions;
      oldPositions = widget.oldInfo.basketballPosition.split(';');
    }
    for (var position in positions) {
      if (oldPositions.contains(position)) {
        isSelected.add(true);
      } else {
        isSelected.add(false);
      }
    }
  }

  @override
  void dispose() {
    _heightFeetController.dispose();
    _heightInchesController.dispose();
    _phoneController.dispose();
    _commentController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        centerTitle: true,
        title: const Text("Sign Up Form"),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            const Text("Please Add or Update the Following Information", style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center,),
            Padding(
              padding: const EdgeInsets.only(
                  left: 15.0, right: 15.0, top: 15, bottom: 0),
              child: TextFormField(
                keyboardType: TextInputType.number,
                controller: _heightFeetController,
                decoration: const InputDecoration(
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
                decoration: const InputDecoration(
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
                decoration: const InputDecoration(
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
                  return CheckboxListTile(
                    title: Text(positions[i]),
                    value: isSelected[i], 
                    onChanged: (newValue) {
                      isSelected[i] = newValue!;
                      setState(() {
                      });
                    }
                  );
                }
            ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                  left: 15.0, right: 15.0, top: 0, bottom: 0),
              child: TextFormField(
                keyboardType: TextInputType.phone,
                controller: _phoneController,
                decoration: const InputDecoration(
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
                decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Comment'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(
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
                    color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
                child: ListTile(
                  title: const Text("Season Rules", style: TextStyle(fontWeight: FontWeight.bold),),
                  trailing: Checkbox(value: seasonRulesRead, onChanged: (value) {
                    
                  },),
                  onTap: () async {
                    String rulesUrl = await getSignUpRules();
                    seasonRulesRead = true;
                    Navigator.push(context, MaterialPageRoute(builder:(context) {
                      WebViewController controller = WebViewController()..loadRequest(Uri.parse(rulesUrl));
                      return Scaffold(
                        appBar: AppBar(
                          centerTitle: true,
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          title: const Text("Season Rules"),
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
                  color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
              child: ListTile(
                title: const Text("Waiver Conditions", style: TextStyle(fontWeight: FontWeight.bold),),
                trailing: Checkbox(value: waiverRead, onChanged: (value) {
                  
                },),
                onTap: () async {
                  String rulesUrl = await getSignUpWaiver();
                  waiverRead = true;
                  Navigator.push(context, MaterialPageRoute(builder:(context) {
                    WebViewController controller = WebViewController()..loadRequest(Uri.parse(rulesUrl));
                    return Scaffold(
                      appBar: AppBar(
                        centerTitle: true,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        title: const Text("Waiver Conditions"),
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
                onPressed: 
                (!seasonRulesRead || !waiverRead || _heightFeetController.value.text.isEmpty || 
                _heightInchesController.value.text.isEmpty || !isSelected.contains(true) || _ageController.value.text.isEmpty
                 || _phoneController.value.text.isEmpty) ? null : () async => await _register(),
                style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) {
                        if (states.contains(WidgetState.disabled)) {
                          return Colors.grey;
                        } else {
                          return Theme.of(context).primaryColor;
                        }
                      },
                    ),
                  ),
                /*onPressed: () async {
                  await _register();
                },*/
                child: const Text(
                  'Register',
                  style: TextStyle(color: Colors.white, fontSize: 25),
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
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text("Before Proceeding, $alertInfo", style: const TextStyle(fontSize: 16),),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              showDialog(
                context: context, 
                builder: (context) {
                 return FutureBuilder(
                  future: _processRegristration(),
                  builder: (context, snapshot) {
                    if(snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                          child: CircularProgressIndicator(
                            color: Theme.of(context).colorScheme.primary,
                          )
                        );
                    }
                    if (snapshot.hasData && snapshot.data! == true) {
                      return AlertDialog(
                        title: Text("Success! You have registered for ${widget.sport} League Season ${widget.season}! Make sure to pay by the due date or click Open Venmo to pay now! Thank You!", style: const TextStyle(fontSize: 16),),
                        actions: [
                          TextButton(child: const Text("Open Venmo"), onPressed: () {
                            Navigator.push(context, MaterialPageRoute(builder:(context) {
                              WebViewController controller = WebViewController()..loadRequest(Uri.parse("https://venmo.com/infinite-sports"));
                              return Scaffold(
                                appBar: AppBar(
                                  centerTitle: true,
                                  backgroundColor: Theme.of(context).colorScheme.primary,
                                  foregroundColor: Colors.white,
                                  title: const Text("Venmo"),
                                ),
                                body: WebViewStack(controller: controller,)
                              );
                            },)).then((value) {
                              Navigator.pop(context);
                              Navigator.pop(context);
                              Navigator.pop(context);
                              setState(() {});
                            });
                          },)
                        ],
                      );
                    }
                    return AlertDialog(
                      title: const Text("Failed! Something went wrong! Try Again! Contact Us if you keep getting this message!"),
                      actions: [TextButton(child: const Text("OK"), onPressed: () {
                              Navigator.pop(context);
                      },)],
                    );
                  },); 
                }
              );
            }, 
            child: const Text("Register"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Close'),
          )
        ],
      ),);
  }
  
  Future<bool> _processRegristration() async {
    try {
      var userInformation = UserInformation();
      userInformation.age = int.parse(_ageController.value.text);
      String _selectedPositions = "";
      if (widget.sport == "Basketball") {
        for (var i = 0; i < basketballPositions.length ; i++) {
          if (isSelected[i]) {
            if (_selectedPositions.isEmpty) {
              _selectedPositions+=basketballPositions[i];
            } else {
              _selectedPositions+=';${basketballPositions[i]}';
            }
          }
        }
        userInformation.basketballPosition = _selectedPositions;
        userInformation.futsalPosition = widget.oldInfo.futsalPosition;
      } else {
        for (var i = 0; i < futsalPositions.length ; i++) {
          if (isSelected[i]) {
            if (_selectedPositions.isEmpty) {
              _selectedPositions+=futsalPositions[i];
            } else {
              _selectedPositions+=';${futsalPositions[i]}';
            }
          }
        }
        userInformation.futsalPosition = _selectedPositions;
        userInformation.basketballPosition = widget.oldInfo.basketballPosition;
      }
      userInformation.height = "${_heightFeetController.value.text.trim()}'${_heightInchesController.value.text.trim()}";
      await addUpdateInfo(userInformation, _phoneController.value.text.trim());
      await signUpToPlay(widget.sport, widget.season);
      if (_commentController.value.text.isNotEmpty) {
        await addComment(widget.sport, widget.season, _commentController.value.text);
      }
      if (!await isSignedUp(FirebaseAuth.instance.currentUser!, widget.sport, widget.season)) {
        throw Exception("User is not signed up");
      }
      return true;
      
    } catch (e) {
      return false;
    }
  }
}
