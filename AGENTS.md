# Project Agent Instructions

This workspace is the Flutter app "Expired" for managing expiring products.

## Project goal
Build a clean MVP app that helps users:
- scan or enter a product barcode quickly,
- save product details such as barcode, name, price, quantity, and dates,
- review an expiry dashboard with 7-day alerts,
- persist data locally with SQLite for offline-friendly usage.

## Current app stack
- Flutter + Dart
- Material 3 UI
- SQLite local persistence
- Barcode scanning support via mobile_scanner
- Camera permission handling via permission_handler

## AI agent priorities
1. Keep the product flow fast: scan → fill → save.
2. Preserve the existing dashboard and expiry alert behavior.
3. Prefer small, readable changes over large refactors.
4. Use local DB logic when adding or updating product data.
5. Avoid unrelated features until the core MVP flow is stable.

## Required conventions
- Keep the UI simple, clear, and touch-friendly.
- Sort products by expiry date in ascending order when shown in the dashboard.
- Treat the 7-day warning as a key requirement.
- When editing product logic, keep DB, UI, and tests consistent.
- If a feature affects persistence, update both the DB helper and the UI path.

## File map for agents
- lib/main.dart — app UI, dashboard, product card, add/edit sheet, barcode flow
- lib/database_helper.dart — SQLite schema, product/category/items logic
- test/ — widget tests for the main user flows

## Implementation guidance
- Prefer incremental improvements to the existing MVP.
- If a bug appears in the add-product path, trace both initialization and DB access before changing UI behavior.
- Keep naming and structures consistent with the current Flutter project.

## Notes for agents
- This file is the main guidance for future AI-assisted changes.
- Do not add complex backend or analytics work before the core expiry workflow is reliable.
