# Contributing to Darktar

Thank you for your interest in contributing to Darktar! This document provides guidelines for local development and contribution.

## Development Setup

### Prerequisites

- **Dart SDK**: 3.5.0 or higher
- **Docker** (optional): For containerized testing

### Getting Started

1. **Clone the repository**:
   ```bash
   git clone https://github.com/fres-sudo/darktar.git
   cd darktar
   ```

2. **Install dependencies**:
   ```bash
   dart pub get
   ```

3. **Generate Drift code**:
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

4. **Configure environment** (optional):
   ```bash
   cp .env.example .env
   # Edit .env with your settings
   ```

5. **Run the server**:
   ```bash
   dart run bin/server.dart
   ```

6. **Verify it's working**:
   ```bash
   curl http://localhost:8080/health
   ```

## Project Structure

```
darktar/
├── bin/
│   └── server.dart          # Entry point
├── lib/
│   ├── api/                 # HTTP API layer
│   │   ├── handlers/        # Route handlers
│   │   └── middleware/      # Auth, CORS, etc.
│   ├── config/              # Environment configuration
│   ├── data/                # Data layer
│   │   ├── database.dart    # Drift tables
│   │   ├── repositories/    # Repository pattern
│   │   └── result.dart      # Result type
│   ├── storage/             # Blob storage abstraction
│   ├── web/                 # Web UI
│   │   ├── handlers/        # Page handlers
│   │   ├── static/          # CSS, JS, assets
│   │   └── templates/       # Mustache templates
│   └── server.dart          # Main server class
└── test/                    # Tests
```

## Development Workflow

### Running Tests

```bash
dart test
```

### Analyzing Code

```bash
dart analyze
```

### Code Formatting

```bash
dart format lib test
```

### Regenerating Drift Code

After modifying `lib/data/database.dart`:
```bash
dart run build_runner build --delete-conflicting-outputs
```

## Commit Guidelines

We use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` New features
- `fix:` Bug fixes
- `docs:` Documentation changes
- `chore:` Maintenance tasks
- `refactor:` Code refactoring
- `test:` Adding or updating tests

Example:
```
feat: add S3 storage adapter support
```

## Testing the Pub API

### Publishing a Test Package

1. Create a test package:
   ```bash
   mkdir -p /tmp/test_pkg
   cd /tmp/test_pkg
   dart create .
   ```

2. Add your Darktar server:
   ```bash
   dart pub token add http://localhost:8080
   ```

3. Publish:
   ```bash
   dart pub publish --server http://localhost:8080
   ```

### Consuming a Package

Add to your `pubspec.yaml`:
```yaml
dependencies:
  test_pkg:
    hosted: http://localhost:8080
    version: ^1.0.0
```

Then run:
```bash
dart pub get
```

## Building Docker Image

```bash
docker build -t darktar/server:dev .
docker run -p 8080:8080 -v $(pwd)/data:/data darktar/server:dev
```

## Areas for Contribution

- [ ] Unit tests for repositories
- [ ] Integration tests for Pub API
- [ ] S3 storage adapter (Enterprise)
- [ ] OIDC authentication (Enterprise)
- [ ] Pana analysis scoring
- [ ] dartdoc integration

## Questions?

Open an issue on GitHub or reach out to the maintainers.
