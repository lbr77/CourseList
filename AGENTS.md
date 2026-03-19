# Repository Guidelines

## Project Structure & Module Organization
- `CourseList/App`: app entry, root navigation, and tab/sheet routing.
- `CourseList/Features`: user-facing features such as `Timetable`, `Settings`, `Import`, `SchoolPicker`, and editors.
- `CourseList/Data`: persistence and service layer, including SQLite/WCDB access in `Data/Database` and repository implementations in `Data/Repository`.
- `CourseList/Domain`: shared models, inputs, protocols, and validation rules.
- `CourseList/Integrations`: adapters for third-party UI or platform integrations such as `ConfigurableKit` and widgets.
- `CourseList/Assets.xcassets`: app icons, colors, and bundled image assets.
- `CourseList/Vendor`: vendored dependencies used directly by the app, e.g. `CalendarKit`.

## Build, Test, and Development Commands
- `open CourseList.xcodeproj`: open the project in Xcode.
- `xcodebuild -project CourseList.xcodeproj -scheme CourseList -destination 'generic/platform=iOS Simulator' build`: full simulator build used for CI-style verification.
- `xcodebuild -project CourseList.xcodeproj -scheme CourseList -destination 'platform=iOS Simulator,name=iPhone 16' build`: local device-specific build.
- There is currently no dedicated test target in the repository. If you add one, prefer `xcodebuild ... test` with the same project and scheme pattern.

## Coding Style & Naming Conventions
- Use Swift with 4-space indentation and standard Xcode formatting.
- Prefer small, focused types and extensions over large multi-purpose files.
- Name Swift types in `UpperCamelCase`; methods, properties, and variables in `lowerCamelCase`.
- Keep UI code in `Features/...`; keep database and persistence logic in `Data/...`; keep reusable business rules in `Domain/...`.
- Match the existing style: concise comments, no unnecessary abstractions, and English identifiers in code.

## Testing Guidelines
- Add targeted tests for new business logic, repository behavior, and import/validation code before adding UI-heavy tests.
- Prefer XCTest naming like `testCreateTimetableRejectsEmptyName()`.
- For UI changes without tests, at minimum run a simulator build and verify the affected flow manually.

## Commit & Pull Request Guidelines
- Current history is minimal (`Initial Commit`), so use short imperative commit messages such as `Add configurable settings root page`.
- Keep commits focused on one change area.
- PRs should include: a short summary, affected paths, manual verification steps, and screenshots for UI changes.
- Mention any database schema or navigation behavior changes explicitly in the PR description.

## Security & Configuration Tips
- Do not hardcode secrets, tokens, or school-specific private endpoints.
- Treat database migrations and repository changes carefully; verify existing timetable data remains readable.
