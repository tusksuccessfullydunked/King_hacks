# PythonRizz Project

End-to-end demo: a Flutter app captures a photo plus location/time, uploads to a Python server, the server runs AI to classify the image, and then stores the report in Postgres.

## Components

- `flutter_application_2/` (Flutter app + Python backend)
  - `lib/`: Flutter UI, camera, GPS, and upload client.
  - `python_server/server.py`: Flask server that receives uploads, runs AI, and writes to the database.
  - `python_server/sql_python_file.py`: Postgres table creation and insert helpers.
- `King_hacks/` and root scripts are legacy experiments and are not part of the current pipeline.

## Data Flow

1) Flutter app captures a photo and GPS location, builds metadata JSON, and POSTs to `/upload`.
2) `server.py` receives `image`, `metadata`, plus form fields (`latitude`, `longitude`, `timestamp`, `notes`).
3) AI inference returns `category`, `whatIsIt`, `priority`.
4) If `category != "miscellaneous"`, the report is inserted into Postgres.

## Database Schema (Postgres)

Table: `reports`

- `id` (SERIAL PRIMARY KEY)
- `Category` (TEXT)
- `WhatIsIt` (TEXT)
- `latitude` (DOUBLE PRECISION)
- `longitude` (DOUBLE PRECISION)
- `timestamp` (TIMESTAMP)
- `priority` (INTEGER)

Note: `Category` and `WhatIsIt` are quoted identifiers; use exact casing in SQL.

## Requirements

- Python 3.10.11
- Flutter (for the mobile app)
- Postgres (local or remote)

Python packages used by the server:
- `flask`, `flask-cors`
- `tensorflow`
- `opencv-python`
- `numpy`
- `psycopg2`

## Configure the Database

Edit credentials in `flutter_application_2/python_server/sql_python_file.py`:

```python
dbname="testing"
user="postgres"
password="qwerty123"
host="localhost"
```

## Run the Python Server

From the repo root:

```powershell
python flutter_application_2\python_server\server.py
```

The server listens on `http://0.0.0.0:5000/upload`.

## Run the Flutter App

From `flutter_application_2/`:

```powershell
flutter pub get
flutter run
```

The app uploads to `http://10.0.2.2:5000/upload` on Android emulator.
For a physical device, update the URL in `flutter_application_2/lib/services/server_service.dart`
to your machine's LAN IP (e.g., `http://192.168.1.50:5000/upload`).

## API Contract

Endpoint: `POST /upload` (multipart/form-data)

- File fields:
  - `image`: the captured image
  - `metadata`: JSON file with image metadata (optional)
- Form fields:
  - `latitude` (string)
  - `longitude` (string)
  - `timestamp` (string, ISO-8601)
  - `notes` (string)

Response (JSON) includes:
- `category`, `whatIsIt`, `priority`
- `report_id` (DB id if stored)
- `discarded` (true when category is `miscellaneous`)

## Notes

- AI classification is currently EfficientNet (ImageNet) and uses a simple rule to assign
  `category` and `priority`. You can customize these rules in
  `flutter_application_2/python_server/server.py`.
- If Postgres is unavailable, the server will return an error when trying to insert the report.