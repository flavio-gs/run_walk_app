import 'package:cloud_firestore/cloud_firestore.dart';

class SeasonConfig {
  final String id;
  final String name;
  final Map<String, dynamic> theme;

  SeasonConfig({required this.id, required this.name, required this.theme});

  factory SeasonConfig.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return SeasonConfig(
      id: doc.id,
      name: (data['name'] ?? 'Season') as String,
      theme: Map<String, dynamic>.from(data['theme'] ?? const {}),
    );
  }
}

class SeasonService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<SeasonConfig?> activeSeasonStream() {
    return _db
        .collection('seasons')
        .where('isActive', isEqualTo: true)
        .limit(1)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return null;
      return SeasonConfig.fromDoc(snap.docs.first);
    });
  }
}
