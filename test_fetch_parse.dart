// ignore_for_file: avoid_print

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:app_secretaria/models/report_model.dart';

void main() async {
  const url = 'https://script.google.com/macros/s/AKfycbxw2FWbqnNvCdnMORY4BMg44mfplFi8YQ838GNhKFQUBMfsI3HMyISq742LxKoWqqp5/exec';
  
  final Map<String, dynamic> data = {
    'action': 'buscar_relatorios',
    'payload': <String, dynamic>{},
  };
  
  try {
    print('Sending POST request...');
    var request = http.Request('POST', Uri.parse(url));
    request.headers.addAll({'Content-Type': 'application/json; charset=utf-8'});
    request.body = jsonEncode(data);
    request.followRedirects = false;

    var client = http.Client();
    var streamedResponse = await client.send(request);
    var response = await http.Response.fromStream(streamedResponse);

    http.Response finalResponse = response;

    if (response.statusCode == 302 || response.statusCode == 303) {
      final location = response.headers['location'];
      print('Following redirect to $location...');
      if (location != null) {
        finalResponse = await http.get(Uri.parse(location));
      }
    }

    print('Final Status code: ${finalResponse.statusCode}');
    if (finalResponse.statusCode == 200) {
      final body = utf8.decode(finalResponse.bodyBytes);
      print('Body loaded successfully. Decoding...');
      final decoded = jsonDecode(body);
      final rawData = decoded['data'];
      print('Found ${rawData.length} reports. Parsing each...');
      
      int successCount = 0;
      int errorCount = 0;
      for (final item in rawData) {
        try {
          final row = Map<String, dynamic>.from(item);
          ReportModel.fromJson(row); // parse only to verify no exception is thrown
          successCount++;
        } catch (e, stack) {
          errorCount++;
          print('--- PARSING ERROR ---');
          print('Error: $e');
          print('Row data: $item');
          print('Stack trace: $stack');
          print('----------------------');
        }
      }
      print('Done! Success: $successCount, Errors: $errorCount');
    }
  } catch (e) {
    print('Fatal error: $e');
  }
}
