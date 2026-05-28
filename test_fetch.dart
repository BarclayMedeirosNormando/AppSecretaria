// ignore_for_file: avoid_print

import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  const url = 'https://script.google.com/macros/s/AKfycbxw2FWbqnNvCdnMORY4BMg44mfplFi8YQ838GNhKFQUBMfsI3HMyISq742LxKoWqqp5/exec';
  
  final Map<String, dynamic> data = {
    'action': 'buscar_relatorios',
    'payload': <String, dynamic>{},
  };
  
  try {
    print('Sending request to $url...');
    var response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    
    print('Status code: ${response.statusCode}');
    print('Headers: ${response.headers}');
    
    if (response.statusCode == 302 || response.statusCode == 303) {
      final location = response.headers['location'];
      print('Redirect location: $location');
      if (location != null) {
        var finalResponse = await http.get(Uri.parse(location));
        print('Final Status code: ${finalResponse.statusCode}');
        print('Final Body length: ${finalResponse.body.length}');
        print('Final Body: ${finalResponse.body.substring(0, finalResponse.body.length > 500 ? 500 : finalResponse.body.length)}');
      }
    } else {
      print('Body: ${response.body}');
    }
  } catch (e) {
    print('Error: $e');
  }
}
