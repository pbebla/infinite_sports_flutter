import 'dart:ffi';
import 'dart:io';

import 'package:email_validator/email_validator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/firebase_auth/firebase_auth_services.dart';
import 'package:infinite_sports_flutter/main.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/signup.dart';
import 'package:image_picker/image_picker.dart';

class CreateAccountPage extends StatefulWidget {
  const CreateAccountPage({super.key});

  @override
  _CreateAccountPageState createState() => _CreateAccountPageState();
}

class _CreateAccountPageState extends State<CreateAccountPage> {
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _passwordController;
  late TextEditingController _verifyPasswordController;
  var profileImage = null;

  String? _firstNameErrorText;
  String? _lastNameErrorText;
  String? _emailErrorText;
  String? _passwordErrorText;
  String? _verifyPasswordErrorText;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController();
    _lastNameController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _passwordController = TextEditingController();
    _verifyPasswordController = TextEditingController();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _verifyPasswordController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    /*
    every time we navigate to another TextField
    the build method called and can causing some UX issue
    to prevent that issue, we reassign the errorTexts to null.
    */
    _firstNameErrorText = null;
    _lastNameErrorText = null;
    _emailErrorText = null;
    _passwordErrorText = null;
    _verifyPasswordErrorText = null;
    super.didChangeDependencies();
  }

  void _nameValidate() {
    if (_firstNameController.value.text.length == 0) {
      _firstNameErrorText = "First Name Required";
    } else {
      _firstNameErrorText = null;
    }
    if (_lastNameController.value.text.length == 0) {
      _lastNameErrorText = "Last Name Required";
    } else {
      _lastNameErrorText = null;
    }
  }

  void _emailValidate(String email) {
    if (!EmailValidator.validate(email)) {
      _emailErrorText = 'Not a valid email address. Should be your@email.com';
    } else {
      _emailErrorText = null;
    }
  }

  void _passwordValidate() {
    if (_passwordController.value.text.isEmpty) {
      _passwordErrorText = 'Can\'t be empty';
    } else if (_passwordController.value.text.length < 4) {
      _passwordErrorText = 'Too short';
    } else {
      _passwordErrorText = null;
    }
  }

  void _verifyPasswordValidate() {
    if (_passwordController.value.text != _verifyPasswordController.value.text) {
      _verifyPasswordErrorText = 'Passwords must match';
    } else {
      _verifyPasswordErrorText = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Sign Up"),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 10.0, bottom: 5.0),
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    showCupertinoModalPopup(
                      context: context, 
                      builder: (context) => CupertinoActionSheet(
                        title: const Text('Image from...'),
                        cancelButton: CupertinoActionSheetAction(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            child: const Text('Cancel'),
                          ),
                        actions: <CupertinoActionSheetAction>[
                          CupertinoActionSheetAction(
                            onPressed: () async {
                              final ImagePicker picker = ImagePicker();
                              final XFile? file = await picker.pickImage(source: ImageSource.gallery);
                              setState(() {
                                
                              });
                            },
                            child: const Text('Photos'),
                          ),
                          CupertinoActionSheetAction(
                            onPressed: () async {
                              final ImagePicker picker = ImagePicker();
                              final XFile? file = await picker.pickImage(source: ImageSource.camera);
                              Navigator.pop(context);
                              setState(() {
                                profileImage = FileImage(File(file!.path));
                              });
                            },
                            child: const Text('Camera'),
                          ),
                        ],
                      ));
                  },
                  child: CircleAvatar(
                    radius: 100,
                    backgroundImage: (profileImage != null) ? profileImage : AssetImage('assets/portraitplaceholder.png')
                  ),
                )
              ),
            ),
            Text("Tap Image to Change Profile Picture", style: TextStyle(fontWeight: FontWeight.bold),),
            Padding(
              padding: const EdgeInsets.only(
                  left: 15.0, right: 15.0, top: 15, bottom: 0),
              child: TextField(
                keyboardType: TextInputType.name,
                controller: _firstNameController,
                decoration: InputDecoration(
                  errorText: _firstNameErrorText,
                  border: OutlineInputBorder(),
                  labelText: 'First Name',
                  hintText: 'Enter First Name'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                  left: 15.0, right: 15.0, top: 15, bottom: 0),
              child: TextField(
                keyboardType: TextInputType.name,
                controller: _lastNameController,
                decoration: InputDecoration(
                  errorText: _lastNameErrorText,
                  border: OutlineInputBorder(),
                  labelText: 'Last Name',
                  hintText: 'Enter Last Name'),
              ),
            ),
            ValueListenableBuilder(
              valueListenable: _emailController, 
              builder: (_, value, __) {
                return Padding(
                  padding: const EdgeInsets.only(
                      left: 15.0, right: 15.0, top: 15, bottom: 0),
                  child: TextField(
                    keyboardType: TextInputType.emailAddress,
                    controller: _emailController,
                    decoration: InputDecoration(
                      errorText: (_emailErrorText != null) ? _emailErrorText : null,
                      suffixIcon: (_emailErrorText == null && EmailValidator.validate(_emailController.value.text))
        ? const Icon(Icons.done, color: Colors.green,) : null,
                      border: OutlineInputBorder(),
                      labelText: 'Email',
                      hintText: 'Enter valid email id as abc@gmail.com'),
                  ),
                );
              }
            ),
            Padding(
              padding: const EdgeInsets.only(
                  left: 15.0, right: 15.0, top: 15, bottom: 0),
              child: TextField(
                keyboardType: TextInputType.phone,
                controller: _phoneController,
                decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Phone Number',
                    hintText: 'Enter phone number'),
              ),
            ),
            ValueListenableBuilder(
              valueListenable: _passwordController, 
              builder: (_, value, __) {
                return Padding(
                  padding: const EdgeInsets.only(
                      left: 15.0, right: 15.0, top: 15, bottom: 0),
                  //padding: EdgeInsets.symmetric(horizontal: 15),
                  child: TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      errorText: (_passwordErrorText != null) ? _passwordErrorText : null,
                      suffixIcon: (_passwordErrorText == null && _passwordController.value.text.length > 4)
        ? const Icon(Icons.done, color: Colors.green,) : null,
                      border: OutlineInputBorder(),
                      labelText: 'Password',
                      hintText: 'Enter secure password'),
                  ),
                );
              }
            ),
            ValueListenableBuilder(
              valueListenable: _verifyPasswordController, 
              builder: (_, value, __) {
                return Padding(
                  padding: const EdgeInsets.only(
                      left: 15.0, right: 15.0, top: 15, bottom: 15),
                  //padding: EdgeInsets.symmetric(horizontal: 15),
                  child: TextField(
                    controller: _verifyPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      errorText: (_verifyPasswordErrorText != null) ? _verifyPasswordErrorText : null,
                      suffixIcon: (_verifyPasswordErrorText == null && _verifyPasswordController.value.text.length > 4 && _verifyPasswordController.value.text == _passwordController.value.text)
        ? const Icon(Icons.done, color: Colors.green,) : null,
                      border: OutlineInputBorder(),
                      labelText: 'Verify Password',
                      hintText: 'Reenter password',
                    ),
                  ),
                );
              }
            ),
            Container(
              height: 50,
              width: 250,
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(20)),
              child: TextButton(
                onPressed: () {_signUp();},
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
  
  void _signUp() async {
    setState(() {});
    _nameValidate();
    _emailValidate(_emailController.value.text);
    _passwordValidate();
    _verifyPasswordValidate();
    if (_firstNameErrorText != null || _lastNameErrorText != null || _emailErrorText != null || _passwordErrorText != null || _verifyPasswordErrorText != null) {
      return;
    }
    String email = _emailController.text;
    String password = _passwordController.text;
    User? user = await auth.signUpWithEmailAndPassword(email, password);

    if (user != null) {
      signedIn = true;
      auth.password = password;
      if (autoSignIn) {
        await secureStorage.write(key: "Email", value: email);
        await secureStorage.write(key: "Password", value: password);
      }

      auth.credential!.additionalUserInfo!.profile!["FirstName"] = _firstNameController.value.text;
      auth.credential!.additionalUserInfo!.profile!["LastName"] = _lastNameController.value.text;

      if (profileImage != null) {
        await createDatabaseLocation(profileImage, _phoneController.value.text);
      } else {
        await createDatabaseLocation(null, _phoneController.value.text);
      }
      //await uploadToken();
      showDialog<String>(
        context: context, 
        builder: (context) => Dialog(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Text("You are registered and logged in. Verify your account using the link sent to your email."),
                TextButton(child: Text("OK"), onPressed: () {
                  Navigator.pop(context);
                },)
              ],
            ),
          ),
        )
      );
      Navigator.pop(context);
      Navigator.pop(context);
    } else {
      print("Error for signup");
    }
  }
  
}