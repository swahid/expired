# Expired

A polished Flutter app for tracking expiring products with barcode scanning, quick product entry, and an at-a-glance expiry dashboard.

## ✨ What this app does
- Scan barcodes and prefill product details when a saved item already exists.
- Add, edit, and remove products from a simple inventory dashboard.
- Highlight products expiring within 7 days with an easy-to-read alert view.
- Store product and category information locally with SQLite for offline-friendly use.

## 🧩 Highlights
- Material 3 UI with a clean, modern dashboard.
- Local persistence using SQLite (`product`, `category`, and `items`).
- Barcode scanning support for fast item entry.
- Lightweight structure ideal for MVP and future expansion.

## 🚀 Quick start
1. Install Flutter and the project dependencies:
   flutter pub get
2. Run the app:
   flutter run
3. Build for Android or iOS when ready:
   flutter build apk
   flutter build ios

## 📁 Project structure
- lib/main.dart — dashboard, forms, product card UI, and barcode flow
- lib/database_helper.dart — SQLite schema and local data helpers
- test/ — widget tests for dashboard and product actions

## 🔧 Development notes
- Keep the UI simple and focused on the core expiry workflow.
- Prefer small, readable changes when extending the app.
- Use local persistence first unless a backend is explicitly requested.

## ✅ Current MVP goals
- Barcode-driven product entry
- Dashboard sorted by soonest expiry
- 7-day alert visibility
- Local DB-backed storage for product/category/item records
