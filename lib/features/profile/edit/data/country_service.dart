import 'dart:convert';
import 'package:http/http.dart' as http;
import 'country.dart';

class CountryService {
  static final CountryService _instance = CountryService._internal();
  factory CountryService() => _instance;
  CountryService._internal();

  List<Country>? _cached;
  bool _loading = false;

  List<Country>? get cached => _cached;
  bool get isLoading => _loading;

  Future<List<Country>> fetch() async {
    if (_cached != null) return _cached!;
    if (_loading) {
      while (_loading) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _cached!;
    }

    _loading = true;
    try {
      final response = await http.get(
        Uri.parse('https://countries.dev/countries?sort=name&fields=name,flags,callingCodes'),
      );

      if (response.statusCode != 200) {
        _loading = false;
        return _fallback;
      }

      final list = jsonDecode(response.body) as List;
      _cached = list.map((e) {
        final name = e['name'] as String? ?? '';
        final flags = e['flags'] as Map? ?? {};
        final flagPng = flags['png'] as String? ?? '';
        final codes = e['callingCodes'] as List? ?? [];
        final code = codes.isNotEmpty ? codes.first as String : '';
        final dialCode = code.isNotEmpty ? '+$code' : '';
        return Country(name: name, dialCode: dialCode, flagPng: flagPng);
      }).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      _loading = false;
      return _cached!;
    } catch (_) {
      _loading = false;
      return _fallback;
    }
  }

  static final List<Country> _fallback = [
    const Country(name: 'United States', dialCode: '+1', flagPng: 'https://flagcdn.com/w80/us.png'),
    const Country(name: 'Bangladesh', dialCode: '+880', flagPng: 'https://flagcdn.com/w80/bd.png'),
    const Country(name: 'India', dialCode: '+91', flagPng: 'https://flagcdn.com/w80/in.png'),
    const Country(name: 'United Kingdom', dialCode: '+44', flagPng: 'https://flagcdn.com/w80/gb.png'),
    const Country(name: 'Canada', dialCode: '+1', flagPng: 'https://flagcdn.com/w80/ca.png'),
    const Country(name: 'Australia', dialCode: '+61', flagPng: 'https://flagcdn.com/w80/au.png'),
    const Country(name: 'Germany', dialCode: '+49', flagPng: 'https://flagcdn.com/w80/de.png'),
    const Country(name: 'France', dialCode: '+33', flagPng: 'https://flagcdn.com/w80/fr.png'),
  ];
}
