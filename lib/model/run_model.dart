import 'package:cloud_firestore/cloud_firestore.dart';

class RunModel {
  final String? id; // 👈 runId do Firestore
  final String userId;
  final DateTime date;
  final double distance; // em metros
  final int duration; // em segundos
  final List<Map<String, double>> route; // lista de latitudes e longitudes
  final double? calories; // calorias estimadas
  final double? pace; // ritmo médio (min/km)

  RunModel({
    this.id,
    required this.userId,
    required this.date,
    required this.distance,
    required this.duration,
    required this.route,
    this.calories,
    this.pace,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'date': date.toIso8601String(),
      'distance': distance,
      'duration': duration,
      'route': route,
      'calories': calories,
      'pace': pace,
    };
  }

  factory RunModel.fromMap(Map<String, dynamic> map) {
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

    final distance = (map['distance'] as num).toDouble();
    final duration = (map['duration'] as num).toInt();

    return RunModel(
      id: map['id']?.toString(), // ✅ AQUI (doc.id entra por fora)
      userId: map['userId'] ?? '',
      date: parseDate(rawDate),
      distance: distance,
      duration: duration,
      route: List<Map<String, double>>.from(
        (rawRoute as List).map((p) => {
          'lat': (p['lat'] as num).toDouble(),
          'lng': (p['lng'] as num).toDouble(),
        }),
      ),
      calories: (map['calories'] != null)
          ? (map['calories'] as num).toDouble()
          : distance * 0.06,
      pace: (map['pace'] != null)
          ? (map['pace'] as num).toDouble()
          : ((duration / 60) / (distance / 1000)),
    );
  }

}
