class UserModel {
  final String uid;
  final String email;
  final String? displayName;
  final String? photoURL;

  UserModel({
    required this.uid,
    required this.email,
    this.displayName,
    this.photoURL,
  });

  factory UserModel.fromFirebaseUser(user) {
    return UserModel(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName,
      photoURL: user.photoURL,
    );
  }
}