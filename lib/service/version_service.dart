import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';

class VersionService {
  static Stream<bool> versionStream() async* {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentBuild = int.parse(packageInfo.buildNumber);

    yield* FirebaseFirestore.instance
        .collection("appConfig")
        .doc("versionControl")
        .snapshots()
        .map((snapshot) {
      final data = snapshot.data();
      if (data == null) return false;

      final minRequiredBuild = data["min_required_build"] ?? 0;

      return currentBuild < minRequiredBuild;
    });
  }
}