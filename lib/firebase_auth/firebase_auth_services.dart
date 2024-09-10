import 'package:firebase_auth/firebase_auth.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';

class FirebaseAuthService {
  bool signedIn = false;
  UserCredential? credential;
  late String password;

  Future<User?> signUpWithEmailAndPassword(String email, String password) async {
    try {
      credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
      return credential!.user;
    } catch (e) {
      print(e.toString());
      return null;
    }
  }

  Future<User?> signInWithEmailAndPassword(String email, String password) async {
    try {
      credential = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      return credential!.user;
    } catch (e) {
      print(e.toString());
      return null;
    }
  }

  Future<void> signOut() async {
    await secureStorage.delete(key: "Email");
    await secureStorage.delete(key: "Password");
    await FirebaseAuth.instance.signOut();
  }
}