# Darktar - Private Dart Package Registry
# Multi-stage build for AOT compilation

# =============================================================================
# Build Stage
# =============================================================================
FROM dart:stable AS build

WORKDIR /app

# Copy pubspec files first for better caching
COPY pubspec.* ./

# Get dependencies
RUN dart pub get

# Copy source code
COPY . .

# Generate Drift code
RUN dart run build_runner build --delete-conflicting-outputs

# Compile to native AOT binary
RUN dart compile exe bin/server.dart -o bin/darktar

# =============================================================================
# Runtime Stage
# =============================================================================
FROM gcr.io/distroless/base-debian12

WORKDIR /app

# Copy the compiled binary
COPY --from=build /app/bin/darktar /app/darktar

# Copy static assets and templates
COPY --from=build /app/lib/web/static /app/static
COPY --from=build /app/lib/web/templates /app/templates

# Create data directory
VOLUME ["/data"]

# Environment variables
ENV DARKTAR_PORT=8080
ENV DARKTAR_HOST=0.0.0.0
ENV DARKTAR_STORAGE_PATH=/data/storage
ENV DARKTAR_DATABASE_PATH=/data/darktar.db

# Expose the port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["/app/darktar", "--health-check"] || exit 1

# Run the server
ENTRYPOINT ["/app/darktar"]
