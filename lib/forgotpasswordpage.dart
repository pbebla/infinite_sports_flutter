
import 'package:email_validator/email_validator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  _ForgotPasswordPageState createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  late TextEditingController _emailController;
  FileImage? profileImage;

  String? _emailErrorText;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    /*
    every time we navigate to another TextField
    the build method called and can causing some UX issue
    to prevent that issue, we reassign the errorTexts to null.
    */
    _emailErrorText = null;
    super.didChangeDependencies();
  }

  void _emailValidate(String email) {
    if (!EmailValidator.validate(email)) {
      _emailErrorText = 'Not a valid email address. Should be your@email.com';
    } else {
      _emailErrorText = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Forgot Password"),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            ValueListenableBuilder(
              valueListenable: _emailController, 
              builder: (_, value, __) {
                return Padding(
                  padding: const EdgeInsets.only(
                      left: 15.0, right: 15.0, top: 15, bottom: 15),
                  child: TextField(
                    keyboardType: TextInputType.emailAddress,
                    controller: _emailController,
                    decoration: InputDecoration(
                      errorText: (_emailErrorText != null) ? _emailErrorText : null,
                      suffixIcon: (_emailErrorText == null && EmailValidator.validate(_emailController.value.text))
        ? const Icon(Icons.done, color: Colors.green,) : null,
                      border: const OutlineInputBorder(),
                      labelText: 'Email',
                      hintText: 'Enter valid email id as abc@gmail.com'),
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
                onPressed: () async {
                  _handleResetPassword();
                },
                child: const Text(
                  'Send Reset Email',
                  style: TextStyle(color: Colors.white, fontSize: 25),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<bool> _sendResetEmail() async {
    try
    {
      _emailValidate(_emailController.value.text);
      String email = _emailController.value.text;
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      return true;
    } catch (e) {
      return false;
    }
  }

  void _handleResetPassword() async {
    setState(() {});
    showDialog(
      context: context,
      builder: (context) {
        return FutureBuilder(
          future: _sendResetEmail(), 
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
                title: Text("Success! Reset Email Sent to\n${_emailController.value.text}", style: const TextStyle(fontSize: 16),),
                actions: [TextButton(child: const Text("OK"), onPressed: () {
                    Navigator.pop(context);
                    Navigator.pop(context);
                },)],
              );
            }
            return AlertDialog(
              title: const Text("Error. Please validate email and try again."),
              actions: [TextButton(child: const Text("OK"), onPressed: () {
                    Navigator.pop(context);
              },)],
            );
          }
        );
      },
    );
  }
  
}
