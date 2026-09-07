import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() async {
  final provider = 'asiacloud';
  final tmdbId = 550;
  final url = 'https://scrapper.rivestream.org/api/provider?provider=$provider&id=$tmdbId';
  print('Fetching: $url');
  final res = await http.get(Uri.parse(url), headers: {
    'User-Agent': 'Mozilla/5.0',
    'Accept': 'application/json',
  });
  print('Status: ${res.statusCode}');
  print('Body: ${res.body}');
}
