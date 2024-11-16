import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/createaccountpage.dart';
import 'package:infinite_sports_flutter/forgotpasswordpage.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginDemoState createState() => _LoginDemoState();
}

class _LoginDemoState extends State<LoginPage> {
  late TextEditingController _emailController;
  late TextEditingController _passwordController;
  String? _loginErrorText;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    /*
    every time we navigate to another TextField
    the build method called and can causing some UX issue
    to prevent that issue, we reassign the errorTexts to null.
    */
    _loginErrorText = null;
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        centerTitle: true,
        title: const Text("Login or Sign Up"),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 60.0),
              child: Center(
                child: SizedBox(
                    width: 200,
                    height: 150,
                    /*decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(50.0)),*/
                    child: Image.asset('assets/infinite.png')),
              ),
            ),
            Padding(
              //padding: const EdgeInsets.only(left:15.0,right: 15.0,top:0,bottom: 0),
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Email',
                    hintText: 'Enter valid email id as abc@gmail.com'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                  left: 15.0, right: 15.0, top: 15, bottom: 0),
              //padding: EdgeInsets.symmetric(horizontal: 15),
              child: TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    errorText: (_loginErrorText),
                    labelText: 'Password',
                    hintText: 'Enter secure password'),
                onSubmitted: (value) async {
                  _processSignIn();
                },
              ),
            ),
            TextButton(
              onPressed: (){
                Navigator.push(context, MaterialPageRoute(builder:(context) {
                    return const ForgotPasswordPage();
                },));
              },
              child: Text(
                'Forgot Password',
                style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 15),
              ),
            ),
            Container(
              height: 50,
              width: 250,
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(20)),
              child: TextButton(
                onPressed: () async {
                  _processSignIn();
                },
                child: const Text(
                  'Login',
                  style: TextStyle(color: Colors.white, fontSize: 25),
                ),
              ),
            ),
            Padding(padding: const EdgeInsets.only(
                  left: 15.0, right: 15.0, top: 5, bottom: 0), child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [const Text("Auto Sign In"), Checkbox(value: autoSignIn, onChanged: (value) async {
              SharedPreferences prefs = await SharedPreferences.getInstance();
              await prefs.setBool('autoSignIn', value!);
              setState(() {
                autoSignIn = value;
              });
            })],),),
            const SizedBox(
              height: 130,
            ),
            TextButton(
              onPressed: (){
                Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateAccountPage())).then((value) {
                  setState(() {
                    if (signedIn) {
                      Navigator.pop(context);
                    }
                  });
                });
              },
              child: Text(
                'New User? Create Account',
                style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _processSignIn() async {
    showDialog(
      barrierDismissible: false,
      context: context, 
      builder: (context) {
        return Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          )
        );
      }
    );
    await _signIn();
    Navigator.pop(context);
    if (signedIn) {
      Navigator.pop(context);
    }
  }

  Future<bool> _signIn() async {
    String email = _emailController.text;
    String password = _passwordController.text;
    User? user = await auth.signInWithEmailAndPassword(email, password);

    if (user != null) {
      signedIn = true;
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await uploadToken(user, token);
      }
      return true;
    } else {
      _loginErrorText = "Username or password is incorrect. Try again.";
      print("Error for login");
      setState(() {
      });
      return false;
    }
  }
}
