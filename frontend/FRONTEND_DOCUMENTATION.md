# Frontend Documentation - Enterprise Auth Mobile

This document provides a technical overview of the Flutter frontend application, its architecture, structure, and instructions for development and execution.

## 1. Architecture & Patterns

The application is built using **Clean Architecture** principles and the **BLoC (Business Logic Component)** pattern for state management. This ensures a highly modular, testable, and maintainable codebase.

### Layers:
- **Domain Layer:** Pure business logic. Contains Entities and Use Cases. It defines "what" the app does without knowing about any external frameworks.
- **Data Layer:** Implementation of repositories defined in the domain layer. Handles data retrieval from REST APIs (via Dio) and local persistence (via SQLite and Secure Storage).
- **Presentation Layer:** Contains the UI (Widgets/Pages) and the BLoCs/Cubits that manage their state.

## 2. Folder Structure

The project is organized **by feature**, which allows teams to work on independent modules without significant overlap.

```text
lib/
├── core/                   # Shared infrastructure
│   ├── config/             # Global configuration (API endpoints, constants)
│   ├── services/           # Platform-level services (Storage, Printing, Audio)
│   ├── utils/              # Common helpers and utilities
│   ├── widgets/            # Reusable UI components across features
│   └── app_theme.dart      # Centralized styling for Light and Dark modes
├── features/               # Application Modules
│   ├── auth/               # Session management, Login, Register
│   ├── logistics/          # Delivery, Receipts, Transfers
│   ├── inventory/          # Stock control, Picking, QR Scanning
│   ├── manufacturing/      # Production tracking
│   └── [feature_name]/     # Standard sub-structure:
│       ├── data/           # Repositories & Models (DART/JSON mapping)
│       ├── domain/         # Entities & Use Cases (Business rules)
│       └── presentation/   # BLoC logic & UI Pages/Screens
└── main.dart               # App entry point & Global Dependency Injection
```

## 3. Navigation & Routing

The application uses **State-Driven Entry** and **Direct Navigation**:

- **Entry Point:** In `main.dart`, the `MaterialApp` root listens to the `AuthBloc`.
    - If the user is `Authenticated`, it loads `HomeScreen`.
    - Otherwise, it redirects to `LoginScreen`.
- **Navigation:** The app does not use a central route table. Instead, it uses standard imperative navigation:
  ```dart
  Navigator.push(context, MaterialPageRoute(builder: (_) => YourNewPage()));
  ```
- **Main Dashboard:** The `HomeScreen` acts as the primary hub, granting access to modules based on the user's permissions retrieved during login.

## 4. Setup & Execution Instructions

To get the application running on your local machine, follow these stages:

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) installed and configured.
- A physical device or emulator (Android/iOS).

### Stage 1: Installation
Navigate to the frontend directory:
```bash
cd frontend
```
Install all required dependencies:
```bash
flutter pub get
```

### Stage 2: Code Generation (Optional)
If you modify any models or files that use `@JsonSerializable`, run the build runner:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### Stage 3: Running the App
Launch the application on your connected device:
```bash
flutter run
```

---

## 5. Development Guide: Adding a New Page

To add a new page to the application:

1. **Locate the Feature:** Find the relevant folder in `lib/features/`.
2. **Create the Screen:** Add a new file in the `presentation/pages/` subfolder.
3. **Handle State:** If the page requires complex logic, define a new BLoC/Cubit in `presentation/bloc/`.
4. **Register Providers:** Ensure any new BLoCs or Repositories are registered in `lib/main.dart` within the `MultiBlocProvider` or `MultiRepositoryProvider`.
5. **Navigate:** Link to your new page from an existing screen using `Navigator.push`.
