# Agent Rules of Engagement: MediPoss Architecture Integrity

To maintain the stability of the MediPoss project, every AI agent **must** follow these rules when making changes.

## 1. The "UI vs. Brain" Rule
The project is strictly split into **Shared Logic (The Brain)** and **Platform-Specific UI (The Skin)**.

### A. Modifying UI (Low Risk)
- **Scope**: `lib/screens/windows/`, `lib/screens/android/`, `lib/theme/`, `lib/widgets/`.
- **Instruction**: You are free to optimize, redesign, or fix UI components in these folders. 
- **Constraint**: If you change an Android UI file, it **must not** affect the Windows UI file, and vice versa. Always check if the screen is "Dispatched" from a base file in `lib/screens/`.

### B. Modifying the "Brain" (High Risk)
- **Scope**: `lib/shared/models/`, `lib/shared/providers/`, `lib/shared/services/`.
- **Instruction**: Any change here affects **BOTH** Windows and Android.
- **Mandatory Requirement**: If you modify any logic in the `shared` directory, you **MUST** verify the build on both platforms:
    1. `flutter run -d windows`
    2. `flutter run -d [android_device_id]`
- **Warning**: Never assume a "shared" fix works on both platforms without testing. Path handling (FileSystem) and networking (WebSockets) behave differently on Windows vs. Android.

## 2. Integrity of Dispatchers
- **Scope**: `lib/screens/*.dart` (files like `pos_screen.dart`, `dashboard_screen.dart`).
- **Rule**: These files are "Smart Routers" (Dispatchers). They **must** remain minimal. 
- **Instruction**: Do not add UI logic or core business logic to these files. They should only contain the `StatelessWidget` that checks `Platform.isAndroid` and returns the relevant OS-specific view.

## 3. Import Governance
- **Rule**: Use **Relative Imports** for all internal files.
- **Incorrect**: `import 'package:medipos/shared/models/patient.dart';`
- **Correct**: `import '../../shared/models/patient.dart';` (depending on depth).
- **Reason**: The project structure is deep. Absolute package imports have historically caused circular dependency and build-runner resolution failures.

## 4. Database Schema Changes
- **Action**: Modified a file in `lib/shared/models/`.
- **Requirement**: You **must** run the generator immediately:
    `dart run build_runner build --delete-conflicting-outputs`
- **Verification**: Ensure `objectbox.g.dart` is updated and commit it along with the model changes.

## 5. Summary Context
Before starting any major task, always read `project_summary.md` and these rules to ensure you don't undo the architectural segregation.
