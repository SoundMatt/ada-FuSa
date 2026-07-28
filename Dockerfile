# syntax=docker/dockerfile:1.4
# ── Build stage ───────────────────────────────────────────────────────────────
# Built directly on Alpine (musl) rather than cross-compiled/statically
# linked from a glibc host: Alpine ships gcc-gnat + libgnat-static, so the
# result is a natively musl-linked, fully static binary -- satisfying
# extending.md's "alpine/musl-compatible (or static)" bundling requirement
# both ways at once.
FROM alpine:3.20 AS builder

LABEL io.x-fusa.stage="build"

RUN apk add --no-cache gcc-gnat libgnat-static musl-dev \
    && ln -sf /usr/lib/libgnat.a /usr/lib/libgnat-13.a \
    && ln -sf /usr/lib/libgnarl.a /usr/lib/libgnarl-13.a

WORKDIR /build

COPY src ./src
RUN mkdir -p obj bin \
    && gnatmake -gnat2022 -Isrc -Dobj -o bin/adafusa src/adafusa_main.adb -largs -static

# ── Runtime stage ─────────────────────────────────────────────────────────────
FROM alpine:3.20 AS runtime

ARG VERSION=0.1.0
ARG SPEC_VERSION=1.15.0
ARG BUILD_DATE
ARG GIT_COMMIT=unknown

LABEL org.opencontainers.image.title="adafusa" \
      org.opencontainers.image.description="Ada/SPARK Functional Safety Toolkit -- x-FuSa spec v${SPEC_VERSION}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.licenses="MPL-2.0" \
      org.opencontainers.image.vendor="SoundMatt" \
      io.x-fusa.tool="adafusa" \
      io.x-fusa.language="ada" \
      io.x-fusa.spec-version="${SPEC_VERSION}"

# Non-root user for security
RUN addgroup -S adafusa && adduser -S adafusa -G adafusa

WORKDIR /project

COPY --from=builder /build/bin/adafusa /usr/local/bin/adafusa

USER adafusa

ENTRYPOINT ["/usr/local/bin/adafusa"]
CMD ["--help"]

# Health probe -- check version
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD adafusa version || exit 1
