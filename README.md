# Pluto AR Flight Trainer (CPAD mini project)

AR flight simulator that teaches beginners to fly the Pluto drone: a virtual drone is placed on a real
surface through the iPhone camera (ARKit) and flown with an on-screen Pluto-style controller.

- **Stack:** Flutter (single CPAD framework) + `arkit_plugin` (ARKit) | Node.js REST API | SQLite database
- **Platform:** iPhone with ARKit (A9 chip or newer, iOS 13+). Needs a Mac with Xcode to build.
- **No physical drone needed.** The simulator never connects to a drone.

```
pluto_ar_sim/
  app/        Flutter app (lib/sim = flight model, tutorial, missions; lib/screens = UI + AR)
  backend/    Node.js API + SQLite (zero npm dependencies)
  docs/       Project documentation (PROJECT_DOCUMENTATION.md / .docx)
```

## 1. Start the backend (laptop)

Needs Node.js 22.13 or newer (`node -v`).

```bash
cd backend
npm test          # optional: 4 API tests
npm start         # prints the URL(s) to type into the app, e.g. http://192.168.1.23:3000
```

## 2. Build and run the app (Mac + iPhone)

```bash
cd app
./setup.sh                    # one-time: creates the ios/ project, patches permissions, pod install
open ios/Runner.xcworkspace   # Xcode: Runner > Signing & Capabilities > pick your Apple ID team
flutter devices               # your iPhone must be listed
flutter run --release -d <iphone-id>
```

Full step-by-step instructions (Developer Mode, trusting the certificate, Wi-Fi, troubleshooting)
are in `docs/PROJECT_DOCUMENTATION.md`, section 9.

## 3. Use it

1. Log in / create an account (enter the server URL printed by the backend).
2. Open the **Guided tutorial** or a **Mission**.
3. Point the camera at a floor or table, wait for yellow dots, **tap** to place the course.
4. Fly: left stick = throttle + yaw, right stick = pitch + roll; ARM / TAKE OFF / LAND buttons.

## Tests

```bash
cd backend && npm test        # API tests (node:test)
cd app && flutter test        # flight model, state machine, tutorial and mission logic
```
