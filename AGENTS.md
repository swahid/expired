# Project Agent Instructions

This workspace is a new app project for managing expiring products.

## Project goal
- Build a minimal product inventory app with the following core features:
  - Scan a product barcode and create a product entry.
  - Store product fields: barcode, name, manufacturing date, expiry date, unit price, and optional quantity.
  - Display a simple dashboard sorted by soonest expiry date.
  - Show a daily alert or notification for products expiring within 7 days.

## Project name
- name: Expired
- package: com.expired.app

## What agents should do first
- Recognize that this is a new workspace with no existing source files.
- Ask the user which platform or stack to scaffold first, for example:
  - Mobile app build with Flutter
- Prefer a simple implementation that minimizes overhead and focuses on the core feature set.

## Important conventions for this project
- Keep the UI simple and clear.
- Sort products by expiry date in ascending order on the dashboard.
- Treat the 7-day expiry warning as a key requirement.
- Use local persistence initially unless the user explicitly requests a backend.
- Keep the product entry flow fast: barcode scan → product details → save.

## When extending the project
- Only add additional features if the core barcode scan, product entry, sorting, and expiry alert flow are working.
- Prefer readable code, simple state management, and clear file structure.
- If using web or mobile frameworks, keep dependencies minimal.

## Notes for agents
- This file is the primary guidance for generating the first project scaffolding.
- Do not add unrelated features or complex inventory management until the MVP flow is complete.
