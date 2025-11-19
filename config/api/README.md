# Mediathek API Config

This directory allows local overrides for the API container. The `sqlpasswd`
file, when present, is copied into `/opt/api/data/.passwd/sqlpasswd` so that
`mt-api` can connect to MariaDB.

The default development credentials match the Docker Compose stack:

```
root:example-root
```

Create `sqlpasswd` (without any file extension) to customise the connection
string.
