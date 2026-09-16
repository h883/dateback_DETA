import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sns_novahack/firebase_options.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  });

  testWidgets('email/password sign-up, sign-in, sign-out', (tester) async {
    final auth = FirebaseAuth.instance;
    final email = 'test-${DateTime.now().millisecondsSinceEpoch}@example.com';
    const password = 'Password123!';

    final signUpResult = await auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    expect(signUpResult.user, isNotNull);
    debugPrint('Signed up as ${signUpResult.user?.uid}');

    await auth.signOut();
    expect(auth.currentUser, isNull);

    final signInResult = await auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    expect(signInResult.user, isNotNull);
    expect(signInResult.user?.email, email);
    debugPrint('Signed in as ${signInResult.user?.uid}');

    await signInResult.user?.delete();
    await auth.signOut();
  });
}
