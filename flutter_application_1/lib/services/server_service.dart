import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

// In services/server_service.dart
class ServerService {
  static Future<Map<String, dynamic>> uploadPhotoWithJson({
    required String imagePath,
    required String jsonFilePath,
    required double latitude,
    required double longitude,
    String? notes,
  }) async {
    print('\n' + '='*50);
    print('🚀 UPLOAD FUNCTION CALLED!');
    print('='*50);
    
    try {
      // IMPORTANT: Use the correct URL
      // For Android Emulator:
      var url = Uri.parse('http://10.0.2.2:5000/upload');
      
      // For testing, let's see what URL we're using
      print('📡 Target URL: $url');
      
      // Check if files exist
      File imageFile = File(imagePath);
      File jsonFile = File(jsonFilePath);
      
      if (!await imageFile.exists()) {
        print('❌ Image file does not exist!');
        return {'success': false, 'message': 'Image file not found'};
      }
      
      if (!await jsonFile.exists()) {
        print('❌ JSON file does not exist!');
        return {'success': false, 'message': 'JSON file not found'};
      }
      
      print('✅ Files verified:');
      print('   Image: ${imagePath.split('/').last} (${await imageFile.length()} bytes)');
      print('   JSON: ${jsonFilePath.split('/').last} (${await jsonFile.length()} bytes)');
      
      // Create multipart request
      var request = http.MultipartRequest('POST', url);
      
      // Add image file
      var multipartImage = await http.MultipartFile.fromPath(
        'image',
        imagePath,
        filename: 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      request.files.add(multipartImage);
      print('✅ Image file added to request');
      
      // Add JSON file
      var multipartJson = await http.MultipartFile.fromPath(
        'metadata',
        jsonFilePath,
        filename: 'data_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      request.files.add(multipartJson);
      print('✅ JSON file added to request');
      
      // Add form fields
      request.fields.addAll({
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'notes': notes ?? 'Flutter upload',
        'timestamp': DateTime.now().toIso8601String(),
      });
      print('✅ Form data added');
      print('   Latitude: $latitude');
      print('   Longitude: $longitude');
      print('   Notes: $notes');
      
      print('📤 Sending request...');
      
      // Send the request
      var streamedResponse = await request.send();
      print('📥 Response received, status: ${streamedResponse.statusCode}');
      
      // Get response body
      var response = await http.Response.fromStream(streamedResponse);
      print('📄 Response body:');
      print(response.body);
      
      if (streamedResponse.statusCode == 200) {
        var result = jsonDecode(response.body);
        print('✅ Upload successful!');
        return result;
      } else {
        print('❌ Upload failed with status: ${streamedResponse.statusCode}');
        return {
          'success': false,
          'message': 'Server returned ${streamedResponse.statusCode}',
          'body': response.body,
        };
      }
      
    } catch (e) {
      print('❌ ERROR in upload: $e');
      print('Stack trace:');
      print(e.toString());
      return {
        'success': false,
        'message': 'Upload failed: $e',
      };
    }
  }
}