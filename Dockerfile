FROM swift:5.9-jammy as build

WORKDIR /app
COPY . .

# Build the BlazeServer executable in release mode
RUN swift build -c release --product BlazeServer

FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    libatomic1 libxml2 ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /run

COPY --from=build /app/.build/release/BlazeServer ./BlazeServer

EXPOSE 9090

# Environment variables can be overridden at runtime:
# - BLAZEDB_DB_NAME
# - BLAZEDB_PASSWORD
# - BLAZEDB_PROJECT
# - BLAZEDB_PORT
# - BLAZEDB_AUTH_TOKEN
# - BLAZEDB_SHARED_SECRET

CMD ["./BlazeServer"]


