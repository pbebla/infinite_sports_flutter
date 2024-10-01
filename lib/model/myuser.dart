class MyUser {
  String? firstName;
  String? lastName;
  String? dateJoined;
  String? profileURL;
  String? uid;
  MyUser(String first, String last, String date, String id, [this.profileURL]) {
    firstName = first;
    lastName = last;
    dateJoined = date;
    uid = id;
  }
}