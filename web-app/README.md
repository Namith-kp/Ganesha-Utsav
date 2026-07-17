# Ganesh Chanda Tracker — Web App

A beautiful web version of the Ganesh Chanda Tracker, connecting to the same Firebase backend as the Flutter mobile app.

## How to Open

### Option 1 — Python HTTP Server (recommended)
```bash
cd "C:\Users\Admin\Downloads\Ganesha-funds-tracker\web-app"
python -m http.server 8080
```
Then open: http://localhost:8080

### Option 2 — VS Code Live Server
Install the "Live Server" extension, right-click index.html → Open with Live Server

### Option 3 — Direct file
Double-click index.html (some Firebase features may not work due to CORS on file://)

## Firebase Setup Note

Go to Firebase Console → Project Settings → Add App → Web, and update the firebaseConfig in index.html with the web-specific appId and authDomain.
