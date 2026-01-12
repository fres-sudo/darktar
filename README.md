# Darktar

A self-hosted private package registry for Dart and Flutter.

## Quick Start

### Prerequisites

- Dart SDK 3.5.0 or higher
- (Optional) Docker for containerized deployment

### Local Development

1. Clone the repository:
   ```bash
   git clone https://github.com/fres-sudo/darktar.git
   cd darktar
   ```

2. Install dependencies:
   ```bash
   dart pub get
   ```

3. Generate Drift database code:
   ```bash
   dart run build_runner build
   ```

4. Copy and configure environment:
   ```bash
   cp .env.example .env
   # Edit .env with your settings
   ```

5. Run the server:
   ```bash
   dart run bin/server.dart
   ```

6. Verify it's running:
   ```bash
   curl http://localhost:8080/health
   ```

### Docker Deployment

```bash
# Build the image
docker build -t darktar/server:latest .

# Run with persistent data
docker run -d \
  -p 8080:8080 \
  -v $(pwd)/data:/data \
  -e DARKTAR_ADMIN_TOKEN=your-secure-token \
  darktar/server:latest
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `DARKTAR_PORT` | `8080` | HTTP server port |
| `DARKTAR_HOST` | `0.0.0.0` | Host to bind to |
| `DARKTAR_STORAGE_PATH` | `./data/storage` | Path for package tarballs |
| `DARKTAR_DATABASE_PATH` | `./data/darktar.db` | SQLite database path |
| `DARKTAR_ADMIN_TOKEN` | (generated) | Admin authentication token |
| `DARKTAR_BASE_URL` | (auto) | Base URL for API responses |

## Usage

### Publishing a Package

1. Add your Darktar server as a token:
   ```bash
   dart pub token add http://localhost:8080
   ```

2. Publish your package:
   ```bash
   dart pub publish --server http://localhost:8080
   ```

### Consuming a Package

Add the hosted dependency to your `pubspec.yaml`:

```yaml
dependencies:
  my_internal_package:
    hosted: http://localhost:8080
    version: ^1.0.0
```

Then run:
```bash
dart pub get
```

## License

AGPL-3.0 - See [LICENSE](LICENSE) for details.
