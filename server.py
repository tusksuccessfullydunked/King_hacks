from flask import Flask, request, jsonify
from flask_cors import CORS
import os
import json
from datetime import datetime

import cv2
import numpy as np
from tensorflow.keras.applications import EfficientNetB0
from tensorflow.keras.applications.efficientnet import preprocess_input
from tensorflow.keras.applications.imagenet_utils import decode_predictions

import sql_python_file

app = Flask(__name__)
CORS(app)

UPLOAD_FOLDER = "uploads"
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

MODEL = EfficientNetB0(weights="imagenet")


def classify_image(image_bytes):
    np_arr = np.frombuffer(image_bytes, np.uint8)
    image = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
    if image is None:
        return None, None, None, None
    image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
    image = cv2.resize(image, (224, 224))
    x = np.expand_dims(image, axis=0)
    x = preprocess_input(x)
    pred = MODEL.predict(x)
    _, label, score = decode_predictions(pred, top=1)[0][0]
    category = "miscellaneous" if score < 0.2 else "detected"
    priority = int(max(1, min(10, round(score * 10))))
    return category, label, priority, float(score)

def read_metadata(json_file):
    if not json_file:
        return {}
    try:
        raw = json_file.read()
        json_file.seek(0)
        return json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return {}

def parse_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None

@app.route("/")
def home():
    return "Python server is running! Use POST /upload to send files."

@app.route("/upload", methods=["POST"])
def upload_files():
    try:
        if "image" not in request.files:
            return jsonify({"success": False, "message": "No image file"}), 400

        image_file = request.files["image"]
        json_file = request.files.get("metadata")

        image_bytes = image_file.read()
        image_file.seek(0)

        json_data = read_metadata(json_file)

        latitude = parse_float(request.form.get("latitude")) or parse_float(json_data.get("latitude"))
        longitude = parse_float(request.form.get("longitude")) or parse_float(json_data.get("longitude"))
        timestamp = request.form.get("timestamp") or json_data.get("timestamp") or datetime.now().isoformat()
        notes = request.form.get("notes")

        if latitude is None or longitude is None:
            return jsonify({"success": False, "message": "Missing latitude/longitude"}), 400

        sql_python_file.create_table_if_not_exists()

        category, whatIsIt, priority, score = classify_image(image_bytes)
        if not category or not whatIsIt or priority is None:
            return jsonify({"success": False, "message": "Could not analyze image"}), 400

        timestamp_suffix = datetime.now().strftime("%Y%m%d_%H%M%S")
        image_filename = f"photo_{timestamp_suffix}.jpg"
        image_path = os.path.join(UPLOAD_FOLDER, image_filename)
        image_file.save(image_path)

        json_filename = None
        if json_file:
            json_filename = f"metadata_{timestamp_suffix}.json"
            json_path = os.path.join(UPLOAD_FOLDER, json_filename)
            json_file.save(json_path)

        report_id = None
        discarded = False
        if category == "miscellaneous":
            discarded = True
        else:
            report_id = sql_python_file.save_report(
                category,
                whatIsIt,
                latitude,
                longitude,
                timestamp,
                priority,
            )

        return jsonify(
            {
                "success": True,
                "message": "Files received successfully!",
                "discarded": discarded,
                "report_id": report_id,
                "files": {
                    "image": image_filename,
                    "metadata": json_filename,
                },
                "form_data": {
                    "latitude": latitude,
                    "longitude": longitude,
                    "notes": notes,
                    "timestamp": timestamp,
                },
                "category": category,
                "whatIsIt": whatIsIt,
                "priority": priority,
                "analysis": {
                    "damage_score": round(score, 2),
                    "severity": category,
                    "detected_issues": [whatIsIt],
                    "confidence": round(score, 2),
                },
            }
        )
    except Exception as e:
        return jsonify({"success": False, "message": f"Server error: {str(e)}"}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)