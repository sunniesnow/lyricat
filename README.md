# Lyricat

Lyricat is a Discord bot that provides querying service for things related to the game Lyrica.

## Deploy

Follow the steps.

1. Clone this repo and run `bundle install`.
2. Use [AssetRipper](https://github.com/AssetRipper/AssetRipper)
to extract [Lyrica's APK](https://apkcombo.com/lyrica/com.Rnova.lyrica/download/apk).
Specify the paths to useful files in `config.yml`
or copy the useful files to the paths specified in `config.yml`.
3. Specify every required environment variables. See [environment variables](#environment-variables).
4. Copy `config.yml` to the dir specified by `LYRICAT_DATA_DIR`.
5. Run `ruby main.rb`.

### Environment variables

| Name | Description |
|-|-|
| `LYRICAT_DATA_DIR` | The dir containing database and config files. Defaults to `./data`. |
| `LYRICAT_RES_DIR` | The dir containing resource files. The base dir of items in `res` in config. Defaults to `./res`. |
| `LYRICAT_CONFIG` | The path to config file. Relative to `LYRICAT_DATA_DIR`. Defaults to `config.yml`. |
| `LYRICAT_DAN` | The path to the file specifying dan courses. Relative to `LYRICAT_DATA_DIR`. Defaults to `dan.yml`. |
| `LYRICAT_THREAD_COUNT` | The number of threads to use for parallel HTTP requests. Defaults to 8. |
| `LYRICAT_RETRY_COUNT` | The number of retries when communicating with Lyrica's server. Defaults to 3. |
| `LYRICAT_STATIC_SESSION_TOKEN` | (Required) The session token used to retrieve leaderboards. |
| `LYRICAT_DISCORD_TOKEN` | (Required) The Discord bot token. |
| `LYRICAT_DISCORD_MAINTAINER_ID` | The Discord user ID of the maintainer. |

## Docker deploy

1. Download `docker-compose.yml.example` and rename it to `docker-compose.yml`.
2. Download `data/config.yml` and put it in the `data` dir
(specified in the volume mapping in `docker-compose.yml`).
3. Specify every required environment variables in `docker-compose.yml`.
4. Use AssetRipper to extract Lyrica's APK, and put the useful files in the `res` dir
(specified in the volume mapping in `docker-compose.yml`).
5. Run `docker compose up -d`.

If you want to build the image yourself,
clone this repo and rename `docker-compose.yml.example` to `docker-compose.yml`.
Change `image: ulysseszhan/lyricat:latest` to `build: .`.
Run `docker compose build`.

### Updating

Simply run `docker compose pull && docker compose up -d`.

### Migrating

Simply copy over `data.db` in the `data` dir (specified in the volume mapping in `docker-compose.yml`).

## License

This is **not** free software.
See LICENSE for details.
