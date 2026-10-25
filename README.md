# Call of Salah

A Flutter application for iOS and Android.

## Tech Stack

- **Flutter**: 3.47.1 (Dart 3.13.1)
- **Platforms**: iOS, Android
- **Package Manager**: Swift Package Manager (iOS)

## Key Dependencies

### State Management
- **provider**: ^6.1.2 - Simple and effective state management

### Dependency Injection
- **get_it**: ^8.0.2 - Service locator pattern

### Storage & Utilities
- **shared_preferences**: ^2.3.4 - Local key-value storage
- **path_provider**: ^2.1.5 - File system paths
- **http**: ^1.2.2 - HTTP requests
- **connectivity_plus**: ^6.1.0 - Network connectivity
- **url_launcher**: ^6.3.1 - URL launching
- **intl**: ^0.20.1 - Internationalization and localization

## Getting Started

### Prerequisites
- Flutter SDK 3.47.1 or higher
- Xcode (for iOS development)
- Android Studio (for Android development)

### Installation

1. Clone the repository
2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app:
   ```bash
   flutter run
   ```

## Development

### Code Generation
If using code generation (e.g., with build_runner):
```bash
flutter pub run build_runner build
```

### Testing
Run tests:
```bash
flutter test
```

Run integration tests:
```bash
flutter test integration_test
```

## Resources

- [Flutter Documentation](https://docs.flutter.dev/)
- [Flutter Learning Resources](https://docs.flutter.dev/reference/learning-resources)
- [Dart Language Guide](https://dart.dev/guides/language/language-tour)
