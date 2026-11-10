# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims to adhere to [Semantic Versioning](https://semver.org/) for tagged releases.

## [Unreleased]
### Fixed
- The bundled nginx passes an outer proxy's `X-Forwarded-Proto` on to the app instead of replacing it with its own `http`, and `.env` and the README say what to set behind an HTTPS reverse proxy (`APP_URL`, `APP_ENV`, `SESSION_SECURE_COOKIE`, `TRUSTED_PROXIES`), without which every form answers 419 ([eventschedule#135](https://github.com/eventschedule/eventschedule/issues/135)).
- The app's data files in `storage/` (`gradients.json`, `currencies.json`, `fonts.json` and the rest) are copied into the storage volume on every start. A volume left from an earlier install never had them, so creating a schedule failed, and one that had them kept old copies after a rebuild ([eventschedule#135](https://github.com/eventschedule/eventschedule/issues/135)).
- An `APP_KEY` Laravel cannot use (most often one pasted without its `base64:` prefix) stops the `app` and `scheduler` containers at start-up with a message saying what is wrong, instead of every page answering with a blank 500 ([eventschedule#135](https://github.com/eventschedule/eventschedule/issues/135)).

## [0.1.0] - 2025-09-17
### Added
- Initial documentation including README and changelog scaffolding for the Docker environment.
