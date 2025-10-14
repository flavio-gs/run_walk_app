import 'package:cloud_firestore/cloud_firestore.dart';

class RunModel {
  final DateTime date;
  final double distance; // em metros
  final int duration; // em segundos
  final List<Map<String, double>> route; // lista de latitudes e longitudes

  RunModel({
    required this.date,
    required this.distance,
    required this.duration,
    required this.route,
  });

  Map<String, dynamic> toMap() {
    return {
      'date': date.toIso8601String(),
      'distance': distance,
      'duration': duration,
      'route': route,
    };
  }

  factory RunModel.fromMap(Map<String, dynamic> map) {
    // Data pode vir como String ou Firestore Timestamp
    DateTime parseDate(dynamic rawDate) {
      if (rawDate is Timestamp) return rawDate.toDate();
      if (rawDate is String) return DateTime.parse(rawDate);
      throw Exception('Formato de data inválido: $rawDate');
    }

    final rawDate = map['date'] ?? map['createdAt'];
    final rawRoute = map['route'] ?? map['path'];

    if (rawDate == null ||
        map['distance'] == null ||
        map['duration'] == null ||
        rawRoute == null) {
      throw Exception('Dados inválidos no documento: $map');
    }

    return RunModel(
      date: parseDate(rawDate),
      distance: (map['distance'] as num).toDouble(),
      duration: (map['duration'] as num).toInt(),
      route: List<Map<String, double>>.from(
        (rawRoute as List).map((p) => {
              'lat': (p['lat'] as num).toDouble(),
              'lng': (p['lng'] as num).toDouble(),
            }),
      ),
    );
  }
}
