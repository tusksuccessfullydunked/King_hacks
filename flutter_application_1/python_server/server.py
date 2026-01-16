# server.py
from flask import Flask, request, jsonify
from flask_cors import CORS
import os
import json
from datetime import datetime

app = Flask(__name__)
CORS(app)

UPLOAD_FOLDER = 'uploads'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

@app.route('/')
def home():
    return "Python server is running! Use POST /upload to send files."

@app.route('/upload', methods=['POST'])
def upload_files():
    print("\n" + "="*60)
    print("🚀 NEW UPLOAD RECEIVED!")
    print("="*60)
    
    try:
        # Check if files exist
        if 'image' not in request.files:
            print("❌ ERROR: No image file")
            return jsonify({'success': False, 'message': 'No image file'}), 400
        
        image_file = request.files['image']
        json_file = request.files.get('metadata')
        
        print(f"📸 Image file received: {image_file.filename}")
        print(f"📏 Image size: {len(image_file.read())} bytes")
        image_file.seek(0)  # Reset file pointer after reading
        
        json_data = {}
        if json_file:
            print(f"📄 JSON file received: {json_file.filename}")
            print(f"📊 JSON size: {len(json_file.read())} bytes")
            json_file.seek(0)  # Reset file pointer
            
            # Try to read JSON content
            try:
                # Read as bytes first
                json_bytes = json_file.read()
                json_file.seek(0)  # Reset again
                
                # Try to decode as UTF-8
                json_content = json_bytes.decode('utf-8')
                json_data = json.loads(json_content)
                print("📋 JSON Content:")
                print(json.dumps(json_data, indent=2))
            except UnicodeDecodeError:
                print("⚠️ JSON file is not valid UTF-8, treating as binary")
                json_data = {"error": "JSON file was not valid UTF-8 text"}
            except json.JSONDecodeError:
                print("⚠️ JSON file is not valid JSON")
                json_data = {"error": "File content is not valid JSON"}
        else:
            print("ℹ️ No JSON file received")
        
        # Get form data
        print("📍 Form Data:")
        print(f"  Latitude: {request.form.get('latitude', 'Not provided')}")
        print(f"  Longitude: {request.form.get('longitude', 'Not provided')}")
        print(f"  Notes: {request.form.get('notes', 'No notes')}")
        
        # Generate unique filename
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        # Save image (as binary)
        image_filename = f"photo_{timestamp}.jpg"
        image_path = os.path.join(UPLOAD_FOLDER, image_filename)
        image_file.save(image_path)
        print(f"💾 Image saved to: {image_path}")
        
        # Save JSON if exists
        if json_file:
            json_filename = f"metadata_{timestamp}.json"
            json_path = os.path.join(UPLOAD_FOLDER, json_filename)
            
            # Save the file as-is (binary)
            json_file.save(json_path)
            print(f"💾 JSON saved to: {json_path}")
            
            # Also try to save the parsed JSON
            parsed_json_path = os.path.join(UPLOAD_FOLDER, f"parsed_{timestamp}.json")
            try:
                with open(parsed_json_path, 'w', encoding='utf-8') as f:
                    json.dump(json_data, f, indent=2)
                print(f"💾 Parsed JSON saved to: {parsed_json_path}")
            except:
                print("⚠️ Could not save parsed JSON")
        
        print("✅ SUCCESS! Files received and saved")
        print("="*60)
        
        # Return success response
        return jsonify({
            'success': True,
            'message': 'Files received successfully!',
            'files': {
                'image': image_filename,
                'metadata': json_filename if json_file else None
            },
            'form_data': {
                'latitude': request.form.get('latitude'),
                'longitude': request.form.get('longitude'),
                'notes': request.form.get('notes')
            },
            'analysis': {
                'damage_score': 0.75,
                'severity': 'high',
                'detected_issues': ['cracks', 'potholes'],
                'confidence': 0.92
            },
            'recommendations': [
                'Immediate inspection needed',
                'Consider temporary closure'
            ]
        })
        
    except Exception as e:
        print(f"❌ ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({
            'success': False,
            'message': f'Server error: {str(e)}'
        }), 500

if __name__ == '__main__':
    print("\n" + "="*60)
    print("🐍 PYTHON FILE UPLOAD SERVER")
    print("="*60)
    print(f"📁 Upload folder: {os.path.abspath(UPLOAD_FOLDER)}")
    print(f"🌐 Server URL: http://127.0.0.1:5000")
    print("="*60 + "\n")
    
    app.run(host='0.0.0.0', port=5000, debug=True)