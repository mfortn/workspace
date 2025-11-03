# phpMyAdmin (Global)

## First-time setup
```bash
docker network create dbmesh || true
docker compose up -d
# open http://localhost:8080
```

## Login
- **Server**: the container name of your project's DB (e.g., `proj1_db`, `proj2_db`)
- **Username**: `root` or your app user (e.g., `proj1_user`)
- **Password**: corresponding password (e.g., `proj1_root` or `proj1_pass`)

> Add each project's DB service to the shared network `dbmesh`.
