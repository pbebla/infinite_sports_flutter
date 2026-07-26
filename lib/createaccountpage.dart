import 'dart:io';

import 'package:email_validator/email_validator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/onboarding/about_you_page.dart';
import 'package:infinite_sports_flutter/onboarding/favorite_sports_page.dart';
import 'package:infinite_sports_flutter/onboarding/signup_validation.dart';
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
  FileImage? profileImage;

  String? _firstNameErrorText;
  String? _lastNameErrorText;
  String? _emailErrorText;
  String? _phoneErrorText;
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
    _phoneErrorText = null;
    _passwordErrorText = null;
    _verifyPasswordErrorText = null;
    super.didChangeDependencies();
  }

  void _nameValidate() {
    _firstNameErrorText =
        validateRequiredName(_firstNameController.value.text, 'First Name');
    _lastNameErrorText =
        validateRequiredName(_lastNameController.value.text, 'Last Name');
  }

  void _emailValidate(String email) {
    _emailErrorText = validateEmailTrimmed(email);
  }

  void _phoneValidate() {
    _phoneErrorText = validatePhone(_phoneController.value.text);
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

  /// Runs every field validator and stores the resulting error text (or
  /// null) on each `_xErrorText` field. Returns true iff every field is
  /// valid. Called synchronously (with a `setState` around it) before the
  /// Register button is allowed to fire the network signup, so field
  /// errors appear immediately instead of only after a failed Firebase
  /// call.
  bool _validateAll() {
    _nameValidate();
    _emailValidate(_emailController.value.text);
    _phoneValidate();
    _passwordValidate();
    _verifyPasswordValidate();
    return _firstNameErrorText == null &&
        _lastNameErrorText == null &&
        _emailErrorText == null &&
        _phoneErrorText == null &&
        _passwordErrorText == null &&
        _verifyPasswordErrorText == null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        centerTitle: true,
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Sign Up"),
            Text(
              "Step 1 of 3",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: appBarBackground(context),
        foregroundColor: appBarForeground(context),
      ),
      body: SingleChildScrollView(
        child: AutofillGroup(
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
                    backgroundImage: profileImage ?? const AssetImage("assets/portraitplaceholder.png") as ImageProvider
                  ),
                )
              ),
            ),
            const Text("Tap Image to Change Profile Picture", style: TextStyle(fontWeight: FontWeight.bold),),
            Padding(
              padding: const EdgeInsets.only(
                  left: 15.0, right: 15.0, top: 15, bottom: 0),
              child: TextField(
                keyboardType: TextInputType.name,
                controller: _firstNameController,
                autofillHints: const [AutofillHints.givenName],
                decoration: InputDecoration(
                  errorText: _firstNameErrorText,
                  border: const OutlineInputBorder(),
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
                autofillHints: const [AutofillHints.familyName],
                decoration: InputDecoration(
                  errorText: _lastNameErrorText,
                  border: const OutlineInputBorder(),
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
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(
                      errorText: (_emailErrorText != null) ? _emailErrorText : null,
                      suffixIcon: (_emailErrorText == null && EmailValidator.validate(_emailController.value.text.trim()))
        ? const Icon(Icons.done, color: Colors.green,) : null,
                      border: const OutlineInputBorder(),
                      labelText: 'Email',
                      hintText: 'Enter valid email id as abc@gmail.com'),
                  ),
                );
              }
            ),
            ValueListenableBuilder(
              valueListenable: _phoneController,
              builder: (_, value, __) {
                return Padding(
                  padding: const EdgeInsets.only(
                      left: 15.0, right: 15.0, top: 15, bottom: 0),
                  child: TextField(
                    keyboardType: TextInputType.phone,
                    controller: _phoneController,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    inputFormatters: [const UsPhoneInputFormatter()],
                    decoration: InputDecoration(
                        errorText: _phoneErrorText,
                        border: const OutlineInputBorder(),
                        labelText: 'Phone Number',
                        hintText: 'Enter phone number'),
                  ),
                );
              },
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
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      errorText: (_passwordErrorText != null) ? _passwordErrorText : null,
                      suffixIcon: (_passwordErrorText == null && _passwordController.value.text.length > 4)
        ? const Icon(Icons.done, color: Colors.green,) : null,
                      border: const OutlineInputBorder(),
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
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      errorText: (_verifyPasswordErrorText != null) ? _verifyPasswordErrorText : null,
                      suffixIcon: (_verifyPasswordErrorText == null && _verifyPasswordController.value.text.length > 4 && _verifyPasswordController.value.text == _passwordController.value.text)
        ? const Icon(Icons.done, color: Colors.green,) : null,
                      border: const OutlineInputBorder(),
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
                onPressed: () {
                  final valid = _validateAll();
                  setState(() {});
                  if (!valid) return;
                  showDialog(
                    context: context,
                    builder: (context) {
                      return FutureBuilder(
                        future: _signUp(), 
                        builder: (context, snapshot) {
                          if(snapshot.connectionState == ConnectionState.waiting) {
                            return Center(
                                child: CircularProgressIndicator(
                                  color: Theme.of(context).colorScheme.primary,
                                )
                              );
                          }
                          if (snapshot.data!) {
                            return AlertDialog(
                              title: const Text("You are registered and logged in. Verify your account using the link sent to your email."),
                              actions: [TextButton(child: const Text("OK"), onPressed: () {
                                    Navigator.pop(context); // dialog
                                    // Step 2 of 3: About You. Email signup
                                    // already collected a phone number in
                                    // Step 1, so askPhone stays false here.
                                    // Its onDone continues to Step 3 (the
                                    // existing favorite-sports picker), which
                                    // pops back to the gate root when done.
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                          builder: (routeContext) => AboutYouPage(
                                                stepIndex: 2,
                                                stepCount: 3,
                                                onDone: () =>
                                                    Navigator.pushReplacement(
                                                  routeContext,
                                                  MaterialPageRoute(
                                                      builder: (_) =>
                                                          const FavoriteSportsPage()),
                                                ),
                                              )),
                                    );
                              },)],
                            );
                          }
                          return AlertDialog(
                            title: const Text("Error Registering. Please validate information and try again."),
                            actions: [TextButton(child: const Text("OK"), onPressed: () {
                                    Navigator.pop(context);
                            },)],
                          );
                        }
                      );
                    },
                  );
                },
                child: Text(
                  'Register',
                  style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 25),
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
  
  Future<bool> _signUp() async {
    // Field-level validation already ran synchronously in the Register
    // button's onPressed (_validateAll(), gating whether this is even
    // called), but re-check defensively in case _signUp is ever invoked
    // directly (e.g. from a future test) without going through the button.
    if (!_validateAll()) {
      return false;
    }
    String firstName = _firstNameController.value.text.trim();
    String lastName = _lastNameController.value.text.trim();
    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();
    // Already formatted as '(408)693-9436' by UsPhoneInputFormatter as the
    // user typed — stored as-is so exports show the formatted display
    // string (owner spec).
    String phoneNumber = _phoneController.value.text;
    User? user = await auth.signUpWithEmailAndPassword(email, password);

    if (user != null) {
      signedIn = true;
      await FirebaseAuth.instance.currentUser!.updateDisplayName('$firstName $lastName');
      await createDatabaseLocation(FirebaseAuth.instance.currentUser!, profileImage, phoneNumber, firstName, lastName);
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await uploadToken(user, token);
      }
      await user.sendEmailVerification();
      return true;
    }
    return false;
  }
  
}
