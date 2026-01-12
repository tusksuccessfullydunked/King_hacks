import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart' as path;

// ========== SIMPLE FILE WRITING SOLUTION ==========
// We'll save JSON files in the SAME directory as the photos
// No path_provider needed!

Future<void> saveJsonFile(String imagePath, double lat, double lng) async {
  try {
    // Get the directory where the photo is stored
    final photoFile = File(imagePath);
    final photoDir = photoFile.parent;
    
    print('📁 Photo directory: ${photoDir.path}');
    print('✅ Directory exists: ${await photoDir.exists()}');
    
    // Create JSON filename (same as photo but .json extension)
    final jsonPath = imagePath.replaceAll('.jpg', '.json');
    final jsonFile = File(jsonPath);
    
    // Create JSON data
    final jsonData = {
      'image_path': imagePath,
      'latitude': lat,
      'longitude': lng,
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'ready_for_ai',
    };
    
    // Write JSON file
    await jsonFile.writeAsString(
      JsonEncoder.withIndent('  ').convert(jsonData),
      flush: true,
    );
    
    // Verify it worked
    final fileExists = await jsonFile.exists();
    final fileSize = await jsonFile.length();
    
    print('📄 JSON saved: $jsonPath');
    print('✅ File exists: $fileExists');
    print('📏 File size: $fileSize bytes');
    print('🎯 Python can read from: ${photoDir.path}');
    
  } catch (e) {
    print('❌ Error saving JSON: $e');
  }
}
// ==================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(camera: cameras.first));
}

class MyApp extends StatelessWidget {
  final CameraDescription camera;
  const MyApp({required this.camera, Key? key}) : super(key: key);
  
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
  const SimpleCameraScreen({required this.camera, Key? key}) : super(key: key);
  
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
  String? _jsonDestinationDir;

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
      
      print('📍 Location obtained: ${position.latitude}, ${position.longitude}');
      
    } on TimeoutException catch (e) {
      setState(() {
        _locationError = 'Location timeout - try again';
        _isGettingLocation = false;
      });
      print('Location timeout: $e');
    } catch (e) {
      setState(() {
        _locationError = 'Failed to get location: ${e.toString()}';
        _isGettingLocation = false;
      });
      print('Location error: $e');
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
  if (_currentPosition == null) {
    await _getCurrentLocation();
    if (_currentPosition == null) {
      _showSnackBar('Cannot take photo without location');
      return;
    }
  }
  
  try {
    // 1. Take photo (goes to temp location)
    final image = await _controller.takePicture();
    
    setState(() {
      _image = image;
    });
    
    // 2. Save to PUBLIC directory
    await _saveToPublicDirectory(image.path);
    
    _showSnackBar('✅ Photo + JSON saved to public folder!');
    
  } catch (e) {
    print('Error: $e');
    _showSnackBar('Failed to capture photo');
  }
}

// NEW METHOD: Save to public directory
Future<void> _saveToPublicDirectory(String imagePath) async {
  try {
    // Create public directory in Downloads folder
    final publicDir = Directory('/storage/emulated/0/Download/InfrastructureReports');
    
    if (!await publicDir.exists()) {
      await publicDir.create(recursive: true);
      print('✅ Created public directory: ${publicDir.path}');
    }
    
    // Generate unique filename with timestamp
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final baseName = 'report_$timestamp';
    
    // 1. Copy photo to public directory (optional)
    final publicPhotoPath = '${publicDir.path}/$baseName.jpg';
    try {
      final originalPhoto = File(imagePath);
      await originalPhoto.copy(publicPhotoPath);
      print('✅ Photo copied to: $publicPhotoPath');
    } catch (e) {
      print('⚠️ Could not copy photo: $e');
    }
    
    // 2. Create JSON file in public directory
    _jsonFilePath = '${publicDir.path}/$baseName.json';
    final jsonFile = File(_jsonFilePath!);
    
    // Prepare JSON data
    final jsonData = {
      'image_path': publicPhotoPath,  // Use public path, not temp path
      'original_image_path': imagePath,
      'latitude': _currentPosition!.latitude,
      'longitude': _currentPosition!.longitude,
      'accuracy': _currentPosition!.accuracy,
      'timestamp': DateTime.now().toIso8601String(),
      'device_info': {
        'platform': 'Android',
        'public_directory': publicDir.path,
      },
      'status': 'ready_for_ai_analysis',
    };
    
    // Write JSON file
    await jsonFile.writeAsString(
      JsonEncoder.withIndent('  ').convert(jsonData),
      flush: true,
    );
    
    // Store the public directory
    _jsonDestinationDir = publicDir.path;
    
    // 3. Print success message with ADB commands
    print('\n' + '='*50);
    print('✅ FILES SAVED TO PUBLIC DIRECTORY');
    print('='*50);
    print('📁 Public Directory: $publicDir');
    print('📷 Photo: $publicPhotoPath');
    print('📄 JSON: $_jsonFilePath');
    print('📍 Location: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
    print('');
    print('🔧 TO ACCESS FILES FROM YOUR COMPUTER:');
    print('1. Open Command Prompt as Administrator');
    print('2. Run: cd C:\\platform-tools');
    print('3. Run: adb devices');
    print('4. Run: adb pull /storage/emulated/0/Download/InfrastructureReports/ C:\\Users\\roman\\Desktop\\');
    print('');
    print('📱 OR access on device:');
    print('File Manager → Downloads → InfrastructureReports');
    print('='*50 + '\n');
    
  } catch (e) {
    print('❌ Error saving to public directory: $e');
    
    // Fallback: Save to original temp location
    print('⚠️ Falling back to temp directory...');
    await _saveToTempDirectory(imagePath);
  }
}

// Fallback method if public directory fails
Future<void> _saveToTempDirectory(String imagePath) async {
  try {
    // Original method - save next to photo
    final jsonPath = imagePath.replaceAll('.jpg', '.json');
    _jsonFilePath = jsonPath;
    _jsonDestinationDir = path.dirname(imagePath);
    
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
    
    print('✅ Fallback: Saved to temp directory');
    print('📄 JSON: $jsonPath');
    
  } catch (e) {
    print('❌ Fallback also failed: $e');
  }
}
  

Future<void> _cleanupJsonFile() async {
  if (_jsonFilePath != null) {
    try {
      final jsonFile = File(_jsonFilePath!);
      if (await jsonFile.exists()) {
        await jsonFile.delete();
        print('🗑️ Deleted JSON file: $_jsonFilePath');
      }
      
      // Also try to delete the photo copy if it exists
      if (_jsonFilePath!.contains('InfrastructureReports')) {
        final photoPath = _jsonFilePath!.replaceAll('.json', '.jpg');
        final photoFile = File(photoPath);
        if (await photoFile.exists()) {
          await photoFile.delete();
          print('🗑️ Deleted photo copy: $photoPath');
        }
      }
    } catch (e) {
      print('Error deleting files: $e');
    }
    _jsonFilePath = null;
    _jsonDestinationDir = null;
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
                        const Text('📷 Photo File:', style: TextStyle(fontWeight: FontWeight.bold)),
                        SelectableText(_image!.path, style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 10),
                        
                        const Text('📄 JSON File:', style: TextStyle(fontWeight: FontWeight.bold)),
                        SelectableText(_jsonFilePath ?? 'Not created', style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 10),
                        
                        const Text('📁 Python should watch:', style: TextStyle(fontWeight: FontWeight.bold)),
                        SelectableText(path.dirname(_image!.path), style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 10),
                        
                        const Text('📍 Location Data:', style: TextStyle(fontWeight: FontWeight.bold)),
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
                print('=== DEBUG INFO ===');
                print('Current position: $_currentPosition');
                print('JSON path: $_jsonFilePath');
                if (_image != null) {
                  print('Photo path: ${_image!.path}');
                  print('Photo dir: ${path.dirname(_image!.path)}');
                }
                print('==================');
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