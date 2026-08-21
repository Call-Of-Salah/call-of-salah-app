# Call of Salah — App

The Flutter mobile app for Call of Salah.

## Stack

- Flutter (Dart) — one codebase for iOS and Android, plus NFC and local UI state
- Supabase Auth — passwordless phone OTP sign-in
- Firebase Cloud Messaging — push notifications
- Talks to [call-of-salah-server](https://github.com/Call-Of-Salah/call-of-salah-server) over REST (`/v1`)

## Getting started

```bash
flutter pub get
flutter run
```

Copy `.env.example` to `.env` (once one exists) and fill in the required values before running.

## Contributing

- Branch off `main`, open a pull request — direct pushes to `main` are blocked.
- PRs require at least 1 approval before merging.
- Keep your branch up to date by rebasing onto `main`, not merging `main` into your branch.

## License

MIT — see [LICENSE](./LICENSE).
