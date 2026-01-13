import 'dart:convert';
import 'package:http/http.dart' as http;

class RunWeather {
  final double tempC;
  final int code;
  final String condition;

  RunWeather({
    required this.tempC,
    required this.code,
    required this.condition,
  });

  Map<String, dynamic> toMap() => {
    'tempC': tempC,
    'code': code,
    'condition': condition,
    'source': 'open-meteo',
  };
}

class WeatherService {
  // Open-Meteo: histórico/forecast por hora (gratis, sem key)
  // Vamos buscar a hora mais próxima do endTime da corrida.
  static Future<RunWeather?> fetchForRun({
    required double lat,
    required double lng,
    required DateTime endTime,
  }) async {
    try {
      // Open-Meteo usa datas no formato YYYY-MM-DD
      final date = _yyyyMmDd(endTime);

      // timezone=auto -> retorna times já no fuso local do ponto (boa)
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
            '?latitude=$lat'
            '&longitude=$lng'
            '&hourly=temperature_2m,weathercode'
            '&start_date=$date'
            '&end_date=$date'
            '&timezone=auto',
      );

      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;

      final jsonMap = jsonDecode(resp.body) as Map<String, dynamic>;
      final hourly = jsonMap['hourly'] as Map<String, dynamic>?;

      if (hourly == null) return null;

      final times = (hourly['time'] as List?)?.cast<String>() ?? const [];
      final temps = (hourly['temperature_2m'] as List?) ?? const [];
      final codes = (hourly['weathercode'] as List?) ?? const [];

      if (times.isEmpty || temps.isEmpty || codes.isEmpty) return null;

      // pega índice da hora mais próxima do endTime
      final idx = _closestHourIndex(times, endTime);
      if (idx < 0 || idx >= times.length) return null;

      final temp = (temps[idx] as num).toDouble();
      final code = (codes[idx] as num).toInt();
      final condition = _weatherCodeToPtBR(code);

      return RunWeather(tempC: temp, code: code, condition: condition);
    } catch (_) {
      return null;
    }
  }

  static String _yyyyMmDd(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static int _closestHourIndex(List<String> isoTimes, DateTime target) {
    // isoTimes vem tipo "2026-01-12T14:00"
    // timezone=auto => já vem no fuso local da região.
    int bestIdx = 0;
    int bestDiff = 1 << 62;

    for (int i = 0; i < isoTimes.length; i++) {
      final t = DateTime.tryParse(isoTimes[i]);
      if (t == null) continue;
      final diff = (t.difference(target)).inMinutes.abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  static String _weatherCodeToPtBR(int code) {
    // tabela oficial Open-Meteo (resumo PT-BR)
    // 0: clear, 1-3: cloudy, 45/48 fog, 51-57 drizzle, 61-67 rain,
    // 71-77 snow, 80-82 showers, 95 thunderstorm, 96-99 hail
    if (code == 0) return 'Céu limpo';
    if (code >= 1 && code <= 3) return 'Nublado';
    if (code == 45 || code == 48) return 'Neblina';
    if (code >= 51 && code <= 57) return 'Garoa';
    if (code >= 61 && code <= 67) return 'Chuva';
    if (code >= 71 && code <= 77) return 'Neve';
    if (code >= 80 && code <= 82) return 'Pancadas';
    if (code == 95) return 'Trovoadas';
    if (code == 96 || code == 99) return 'Trovoadas com granizo';
    return 'Tempo indefinido';
  }
}
