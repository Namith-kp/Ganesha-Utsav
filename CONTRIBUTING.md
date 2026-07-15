# Contributing to Ganesha Funds Tracker

First off, thank you for considering contributing to the Ganesha Funds Tracker! It's people like you that make open source tools and community projects such a great place to learn, inspire, and create.

Following these guidelines helps to communicate that you respect the time of the developers managing and developing this open source project. In return, they should reciprocate that respect in addressing your issue, assessing changes, and helping you finalize your pull requests.

## How Can I Contribute?

### Reporting Bugs

This section guides you through submitting a bug report. Following these guidelines helps maintainers and the community understand your report, reproduce the behavior, and find related reports.

- **Check existing issues**: Before creating a bug report, please check if the issue has already been reported in the issue tracker.
- **Use a clear and descriptive title**: For the issue to identify the problem.
- **Describe the exact steps to reproduce the problem**: Provide as many details as possible.
- **Provide specific examples to demonstrate the steps**: Include links to files, or copy/paste snippets, which you use in those examples.
- **Describe the behavior you observed after following the steps**: Point out what exactly is the problem with that behavior.
- **Explain which behavior you expected to see instead and why.**

### Suggesting Enhancements

This section guides you through submitting an enhancement suggestion, including completely new features and minor improvements to existing functionality.

- **Check existing issues**: Check if the enhancement has already been suggested.
- **Use a clear and descriptive title**: For the issue to identify the suggestion.
- **Provide a step-by-step description of the suggested enhancement**: Provide as many details as possible.
- **Describe the current behavior and explain which behavior you expected to see instead**: Explain why this enhancement would be useful.

### Pull Requests

The process described here has several goals:

- Maintain the quality of the codebase.
- Fix problems that are important to users.
- Engage the community in working toward the best possible version of this tool.

Please follow these steps to have your contribution considered by the maintainers:

1. **Fork the repository** and create your branch from `main`.
2. **Clone your fork**: `git clone https://github.com/your-username/ganesha-funds-tracker.git`
3. If you've added code that should be tested, **add tests**.
4. If you've changed APIs or features, **update the documentation**.
5. Ensure the test suite passes.
6. **Make sure your code lints**. Run `flutter analyze` to check for any linting issues.
7. Issue that pull request!

## Setting Up for Local Development

To contribute code, you will need to set up the project on your local machine.

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Ensure you are using the latest stable release)
- An IDE (like [Android Studio](https://developer.android.com/studio), [IntelliJ IDEA](https://www.jetbrains.com/idea/), or [VS Code](https://code.visualstudio.com/)) with the Flutter and Dart plugins installed.
- Git

### Installation Steps

1. **Fork the repo** to your own GitHub account.
2. **Clone your fork** to your local machine:
   ```bash
   git clone https://github.com/your-username/ganesha-funds-tracker.git
   ```
3. **Navigate to the directory**:
   ```bash
   cd ganesha-funds-tracker
   ```
4. **Install dependencies**:
   ```bash
   flutter pub get
   ```
5. **Run the app**:
   ```bash
   flutter run
   ```

## Styleguides

### Git Commit Messages

- Use the present tense ("Add feature" not "Added feature").
- Use the imperative mood ("Move cursor to..." not "Moves cursor to...").
- Limit the first line to 72 characters or less.
- Reference issues and pull requests liberally after the first line.

### Code Conventions

- This project follows the official [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style).
- Run `flutter format .` to automatically format your code before committing.
- Run `flutter analyze` to ensure there are no linting errors.

## Need Help?

If you have any questions or need help setting up the project, feel free to open an issue with your questions.

Thank you for contributing!
