# EventSchedule Docker Environment

This repository provides a Docker-based runtime for the [EventSchedule](https://github.com/eventschedule/eventschedule) Laravel application. It packages PHP-FPM, Nginx, MariaDB, and a scheduler worker so that the app can be bootstrapped quickly for local development, testing, or small-scale deployments.

## Features

- **Multi-service stack**: PHP-FPM application container, Nginx web server, MariaDB database, and a dedicated scheduler runner.
- **Automated bootstrap**: Composer dependencies and frontend assets are built into the image; database migrations and (when unset) the application key are provisioned automatically when the containers start.
- **Persistent volumes**: Shared Docker volumes retain database data and uploaded files between restarts.
- **Configurable upstream branch**: Build arguments allow pinning to a specific EventSchedule git reference.

## Prerequisites

- Docker Engine 24.0 or newer
- Docker Compose v2 plugin
- Internet access on the build machine to fetch Composer, npm, and git dependencies

## Getting Started

1. Review `.env` and adjust credentials before first start (the repo ships a working
   `.env` for local use):
   ```bash
   # In .env set DB_PASSWORD, APP_URL, and (for production) a fixed APP_KEY.
   # See "Environment Configuration" below.
   ```
2. Start the stack:
   ```bash
   docker compose up --build -d
   ```
3. Visit [http://localhost:8080](http://localhost:8080) to access the application.

The first startup can take several minutes while dependencies are installed and assets are compiled.

## Service Overview

| Service    | Description                                                                 |
|------------|-----------------------------------------------------------------------------|
| `app`      | PHP-FPM container running the Laravel application code.                     |
| `web`      | Nginx container serving HTTP traffic and proxying PHP requests to `app`.    |
| `db`       | MariaDB 11 database with credentials controlled by `.env`.                  |
| `scheduler`| Long-running worker that executes `php artisan schedule:run` every minute.  |

## Environment Configuration

Key settings are defined in `.env` and forwarded into the containers. At a minimum you should set `DB_PASSWORD`. Additional variables supported by Laravel (e.g., `MAIL_` settings) can be added to tailor the runtime.

- **`APP_URL`** defaults to `http://localhost:8080`. Set it to the address users actually reach, otherwise generated links and emails point to localhost.
- **`APP_KEY`** is generated automatically on first start if left blank, but that key then lives only inside the container and is regenerated whenever the container is recreated (logging users out and breaking previously encrypted data). For anything beyond throwaway local testing, set a fixed key once and keep it in `.env`:
  ```bash
  docker compose run --rm app php artisan key:generate --show
  ```
  Uncomment the `APP_KEY=` line in `.env` and paste the printed value; it is then shared by the `app` and `scheduler` services via `env_file`.

The Dockerfile clones the upstream EventSchedule repository. You can change the source branch or tag by editing `APP_REF` in `docker-compose.yml` or passing `--build-arg APP_REF=...` to `docker compose build`.

## Operational Tips

- **Logs**: View service logs with `docker compose logs -f <service>`.
- **Migrations**: The entrypoint runs `php artisan migrate --force` on startup. Run additional artisan commands via `docker compose exec app php artisan ...`.
- **Database access**: Connect to MariaDB on `localhost:3306` (when exposed) using credentials defined in `.env`.
- **Updating dependencies**: Rebuild the `app` image (`docker compose build app`) after modifying Composer or npm dependencies.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a history of notable updates.

## License

This repository packages the upstream EventSchedule application, which is subject to its own license. Review the upstream project for licensing details and ensure compliance when deploying.
