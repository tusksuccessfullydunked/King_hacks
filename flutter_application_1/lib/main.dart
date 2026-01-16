import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'services/server_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(CameraApp(camera: cameras.first));
}

class PythonService {
  static const channel = MethodChannel('com.CameraApp/python_channel');
  
  static Future<String> processPhoto(String photoPath) async {
    try {
      final externalDir = await getExternalStorageDirectory();
      
      final args = {
        'photo_path': photoPath,
        'external_dir': externalDir?.path ?? '',
      };
      
      final result = await channel.invokeMethod<String>('runPython', {
        'script': 'photo_processor',
        'function': 'process_photo',
        'args': jsonEncode(args),
      });
      
      return result ?? 'No result';
    } on PlatformException catch (e) {
      return 'Failed: ${e.message}';
    }
  }
}

class CameraApp extends StatelessWidget {
  final CameraDescription camera;
  const CameraApp({required this.camera, super.key});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Infrastructure Reporter',
      theme: ThemeData(
        primarySwatch: Colors.green,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: SimpleCameraScreen(camera: camera),
    );
  }
}

class SimpleCameraScreen extends StatefulWidget {
  final CameraDescription camera;
  const SimpleCameraScreen({required this.camera, super.key});
  
  @override
  _SimpleCameraScreenState createState() => _SimpleCameraScreenState();
}

class _SimpleCameraScreenState extends State<SimpleCameraScreen> {
  late CameraController _controller;
  XFile? _image;
  bool _isFrontCamera = false;
  
  Position? _currentPosition;
  bool _isGettingLocation = false;
  String? _locationError;
  
  // Track the JSON file path
  String? _jsonFilePath;

  @override
  void initState() {
    super.initState();
    _initializeCamera(widget.camera);
    _checkAndRequestLocationPermission();
  }
  
  Future<void> _checkAndRequestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar('Please enable location services');
      return;
    }
    
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnackBar('Location permissions are denied');
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      _showSnackBar('Location permissions are permanently denied');
      return;
    }
    
    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      await _getCurrentLocation();
    }
  }

  Future<void> _getCurrentLocation() async {
    if (_isGettingLocation) return;
    
    setState(() {
      _isGettingLocation = true;
      _locationError = null;
    });
    
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 10),
        ),
      );
      
      setState(() {
        _currentPosition = position;
        _isGettingLocation = false;
      });
      
    } on TimeoutException {
      setState(() {
        _locationError = 'Location timeout - try again';
        _isGettingLocation = false;
      });
    }
  }
  
  void _initializeCamera(CameraDescription camera) {
    _controller = CameraController(camera, ResolutionPreset.high);
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    });
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

Future<void> _takePhoto() async {
  try {
    // 1. Get location first
    if (_currentPosition == null) {
      await _getCurrentLocation();
      if (_currentPosition == null) {
        _showSnackBar('Need location first');
        return;
      }
    }
    
    // 2. Take photo
    final image = await _controller.takePicture();
    setState(() => _image = image);
    
    // 3. Save JSON file
    await _saveToPublicDirectory(image.path);
    
    if (_jsonFilePath == null) {
      _showSnackBar('Failed to create JSON file');
      return;
    }
    
    // 4. DEBUG: Print what we're about to send
    print('\n' + '='*50);
    print('📤 READY TO UPLOAD TO PYTHON:');
    print('='*50);
    print('📸 Image: ${image.path}');
    print('📄 JSON: $_jsonFilePath');
    print('📍 Location: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
    
    // 5. Show uploading message
    _showSnackBar('Uploading to Python server...');
    
    // 6. CALL THE UPLOAD FUNCTION (make sure this line exists!)
    final result = await ServerService.uploadPhotoWithJson(
      imagePath: image.path,
      jsonFilePath: _jsonFilePath!,
      latitude: _currentPosition!.latitude,
      longitude: _currentPosition!.longitude,
      notes: 'Infrastructure report ${DateTime.now()}',
    );
    
    // 7. Show result
    print('📥 Server response: $result');
    
    if (result['success'] == true) {
      _showSnackBar('✅ Uploaded! Check Python console.');
    } else {
      _showSnackBar('❌ Failed: ${result['message']}');
    }
    
  } catch (e) {
    _showSnackBar('Error: $e');
    print('❌ Photo error: $e');
  }
}



Future<Directory> _getPublicDirectory() async {
  // For Android
  if (Platform.isAndroid) {
    final externalDir = await getExternalStorageDirectory();
    if (externalDir != null) {
      return Directory('${externalDir.path}/InfrastructureReports');
    }
  }
  // Fallback to app documents directory
  final appDir = await getApplicationDocumentsDirectory();
  return Directory('${appDir.path}/InfrastructureReports');
}

// NEW METHOD: Save to public directory
Future<void> _saveToPublicDirectory(String imagePath) async {
  try {
    // Create public directory in Downloads folder
    final publicDir = await _getPublicDirectory();
    
    if (!await publicDir.exists()) {
      await publicDir.create(recursive: true);
    }
    
    // Generate unique filename with timestamp
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final baseName = 'report_$timestamp';
    
    // 1. Copy photo to public directory (optional)
    final publicPhotoPath = '${publicDir.path}/$baseName.jpg';
    final originalPhoto = File(imagePath);
    await originalPhoto.copy(publicPhotoPath);
    
    // 2. Create JSON file in public directory
    _jsonFilePath = '${publicDir.path}/$baseName.json';
    final jsonFile = File(_jsonFilePath!);
    
    // Prepare JSON data
    final jsonData = {
      'image_path': publicPhotoPath,  // Use public path, not temp path
      'latitude': _currentPosition!.latitude,
      'longitude': _currentPosition!.longitude,
      'timestamp': DateTime.now().toIso8601String(),
      'original_image_path': imagePath,
      'device_info': {
        'platform': 'Android',
        'public_directory': publicDir.path,
      },
    };
    
    // Write JSON file
    await jsonFile.writeAsString(
      JsonEncoder.withIndent('  ').convert(jsonData),
      flush: true,
    );
    
  } catch (e) {
    // Fallback: Save to original temp location
    await _saveToTempDirectory(imagePath);
  }
}

// Fallback method if public directory fails
Future<void> _saveToTempDirectory(String imagePath) async {
  try {
    // Original method - save next to photo
    final jsonPath = imagePath.replaceAll('.jpg', '.json');
    _jsonFilePath = jsonPath;
    
    final jsonData = {
      'image_path': imagePath,
      'latitude': _currentPosition!.latitude,
      'longitude': _currentPosition!.longitude,
      'timestamp': DateTime.now().toIso8601String(),
      'note': 'Saved to temp directory (public directory failed)',
    };
    
    final jsonFile = File(jsonPath);
    await jsonFile.writeAsString(
      JsonEncoder.withIndent('  ').convert(jsonData),
      flush: true,
    );
    
  } catch (e) {
    _showSnackBar("Fallback failed");
  }
}
  

Future<void> _cleanupJsonFile() async {
  if (_jsonFilePath != null) {
    try {
      final jsonFile = File(_jsonFilePath!);
      if (await jsonFile.exists()) {
        await jsonFile.delete();
      }
      
      // Also try to delete the photo copy if it exists
      if (_jsonFilePath!.contains('InfrastructureReports')) {
        final photoPath = _jsonFilePath!.replaceAll('.json', '.jpg');
        final photoFile = File(photoPath);
        if (await photoFile.exists()) {
          await photoFile.delete();
        }
      }
    } catch (e) {
      _showSnackBar("Error deleting files: $e");
    }
    _jsonFilePath = null;
  }
}
  Future<void> _switchCamera() async {
    final cameras = await availableCameras();
    if (cameras.length < 2) return;
    
    final newCamera = _isFrontCamera
        ? cameras.firstWhere(
            (cam) => cam.lensDirection == CameraLensDirection.back,
            orElse: () => cameras.first,
          )
        : cameras.firstWhere(
            (cam) => cam.lensDirection == CameraLensDirection.front,
            orElse: () => cameras.last,
          );
    
    await _controller.dispose();
    _initializeCamera(newCamera);
    setState(() {
      _isFrontCamera = !_isFrontCamera;
    });
  }
  
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
  
  Widget _buildLocationStatus() {
    if (_isGettingLocation) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Getting location...',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      );
    }
    
    if (_locationError != null) {
      return GestureDetector(
        onTap: _getCurrentLocation,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off, color: Colors.orange, size: 16),
            const SizedBox(width: 8),
            Text(
              'Location error - Tap to retry',
              style: const TextStyle(color: Colors.orange, fontSize: 14),
            ),
          ],
        ),
      );
    }
    
    if (_currentPosition != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_on, color: Colors.green, size: 16),
          const SizedBox(width: 8),
          Text(
            'Lat: ${_currentPosition!.latitude.toStringAsFixed(6)}',
            style: const TextStyle(color: Colors.green, fontSize: 14),
          ),
        ],
      );
    }
    
    return GestureDetector(
      onTap: _getCurrentLocation,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_searching, color: Colors.blue, size: 16),
          const SizedBox(width: 8),
          Text(
            'Tap to get location',
            style: const TextStyle(color: Colors.blue, fontSize: 14),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCameraPreview() {
    return Container(
      margin: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0x80),
            blurRadius: 20,
            spreadRadius: 5,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: CameraPreview(_controller),
      ),
    );
  }
  
  Widget _buildCapturedImage() {
    return Container(
      margin: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0x80),
            blurRadius: 20,
            spreadRadius: 5,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: [
            Image.file(File(_image!.path), fit: BoxFit.cover),
            
            // Location overlay
            if (_currentPosition != null)
              Positioned(
                bottom: 10,
                left: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0xB3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lat: ${_currentPosition!.latitude.toStringAsFixed(6)}',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      Text(
                        'Lng: ${_currentPosition!.longitude.toStringAsFixed(6)}',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      
                      // JSON file indicator
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0x4D),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.data_object, size: 12, color: Colors.green),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'JSON saved with photo',
                                style: const TextStyle(color: Colors.green, fontSize: 10),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            // Close button
            Positioned(
              top: 15,
              right: 15,
              child: FloatingActionButton.small(
                onPressed: () async {
                  await _cleanupJsonFile();
                  setState(() => _image = null);
                },
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
                child: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCameraControls() {
    if (_image != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // File info button
          ElevatedButton.icon(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Files Ready for Python'),
                  content: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Photo File:', style: TextStyle(fontWeight: FontWeight.bold)),
                        SelectableText(_image!.path, style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 10),
                        
                        const Text('JSON File:', style: TextStyle(fontWeight: FontWeight.bold)),
                        SelectableText(_jsonFilePath ?? 'Not created', style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 10),
                        
                        const Text('Python should watch:', style: TextStyle(fontWeight: FontWeight.bold)),
                        SelectableText(path.dirname(_image!.path), style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 10),
                        
                        const Text('Location Data:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('Latitude: ${_currentPosition!.latitude.toStringAsFixed(6)}'),
                        Text('Longitude: ${_currentPosition!.longitude.toStringAsFixed(6)}'),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.file_present),
            label: const Text('VIEW FILE PATHS'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              backgroundColor: Colors.blue[800],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
          ),
          const SizedBox(height: 10),
          
          // Retake button
          TextButton.icon(
            onPressed: () async {
              await _cleanupJsonFile();
              setState(() => _image = null);
            },
            icon: const Icon(Icons.refresh, color: Colors.white70),
            label: const Text(
              'RETAKE PHOTO',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      );
    }
    
    return Column(
      children: [
        // Location status
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(20),
          ),
          child: _buildLocationStatus(),
        ),
        const SizedBox(height: 20),
        
        // Camera controls
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Switch camera button
            FloatingActionButton(
              onPressed: _switchCamera,
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
              child: Icon(
                _isFrontCamera ? Icons.camera_rear : Icons.camera_front,
              ),
            ),
            
            // Main capture button
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: FloatingActionButton(
                onPressed: _takePhoto,
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                elevation: 5,
                child: const Icon(Icons.camera, size: 30),
              ),
            ),
            
            // Debug/test button
            FloatingActionButton(
              onPressed: () {
                _showSnackBar('Debug info printed to console');
              },
              backgroundColor: Colors.orange[800],
              foregroundColor: Colors.white,
              child: const Icon(Icons.bug_report),
            ),
          ],
        ),
      ],
    );
  }
  
  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
              ),
              const SizedBox(height: 20),
              Text(
                'Initializing Camera...',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Infrastructure Issue'),
        backgroundColor: Colors.green[800],
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.location_on),
            onPressed: _getCurrentLocation,
            tooltip: 'Refresh location',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Instruction text
            Container(
              padding: const EdgeInsets.all(20),
              child: Text(
                _image == null
                    ? 'Take a photo of infrastructure issue'
                    : 'Photo + JSON ready for AI processing',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            
            // Camera preview or captured image
            Expanded(
              child: Center(
                child: _image == null
                    ? _buildCameraPreview()
                    : _buildCapturedImage(),
              ),
            ),
            
            // Controls
            Container(
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
              child: _buildCameraControls(),
            ),
          ],
        ),
      ),
    );
  }
}