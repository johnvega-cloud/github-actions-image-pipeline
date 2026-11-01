# Stage 1: compile on the runner's own CPU and cross-compile for the target one.
# This is much faster than compiling arm64 inside QEMU.
FROM --platform=$BUILDPLATFORM golang:1.27-alpine AS build
ARG TARGETOS TARGETARCH
WORKDIR /src
COPY go.mod main.go ./
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o /hello .

# Stage 2: a minimal base image with no shell or package manager, running as non-root.
FROM gcr.io/distroless/static-debian13:nonroot
COPY --from=build /hello /hello
EXPOSE 8080
ENTRYPOINT ["/hello"]
