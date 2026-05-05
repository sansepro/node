# node

Скрипт для установки и запуска `remnawave/node` в Docker.

`install.sh`:

- при необходимости обновляет систему и устанавливает `curl`, `wget`, `ufw`;
- проверяет наличие Docker и устанавливает его через официальный скрипт, если Docker не найден;
- создает рабочую директорию `/opt/<name>`;
- опционально настраивает `ufw` и ICMP-правила;
- опционально применяет sysctl-настройки;
- создает `docker-compose.yml`;
- запускает контейнер `remnawave/node:latest` в режиме `host`.

## Быстрый запуск

```bash
bash <(wget -qO- https://raw.githubusercontent.com/sansepro/node/main/install.sh)
```

По умолчанию скрипт работает в интерактивном режиме и задает вопросы по ходу установки.

## Требования

- Ubuntu/Debian система;
- доступ в интернет для установки пакетов, Docker и загрузки Docker-образа.

## Параметры

| Параметр | Описание |
| --- | --- |
| `--update` | Обновить систему и установить `curl`, `wget`, `ufw` без подтверждения. |
| `--no-update` | Не обновлять систему. |
| `--name <name>` | Имя контейнера, hostname и директории в `/opt`. По умолчанию: `remnanode`. |
| `--port <port>` | Порт ноды. По умолчанию: `2000`. |
| `--key <SECRET_KEY>` | Secret key для подключения ноды. |
| `--ufw` | Настроить `ufw` без подтверждения (Будут открыты только 3 порта `OpenSSH`, `443`, `<port>`). |
| `--no-ufw` | Не настраивать `ufw`. |
| `--sysctl` | Применить sysctl-настройки без подтверждения. |
| `--no-sysctl` | Не применять sysctl-настройки. |

## Неинтерактивный запуск

```bash
bash <(wget -qO- https://raw.githubusercontent.com/sansepro/node/main/install.sh) --update --name remnanode --port 2000 --key "SECRET_KEY" --ufw --sysctl
```

Замените `SECRET_KEY` на значение из панели Remnawave.

## Что будет создано

Скрипт создает директорию:

```bash
/opt/<name>
```

Внутри нее создается `docker-compose.yml` и запускается контейнер:

```bash
docker compose up -d
```

После запуска скрипт показывает логи контейнера:

```bash
docker compose logs -f -t
```

## Важные замечания

- При настройке `ufw` скрипт открывает `OpenSSH`, `443/tcp` и `2000/tcp`.
- Перед изменением `/etc/ufw/before.rules` создается backup вида `/etc/ufw/before.rules.bak_<timestamp>`.
- Sysctl-настройки записываются в `/opt/sysctl.conf` и применяются командой `sysctl -p /opt/sysctl.conf`.


## Как открыть порты через `ufw`

Замените 2001 на нужный вам порт:

```bash
ufw allow 2001/tcp
```
Перезагрузите `ufw`:

```bash
ufw reload
```

или:

```bash
ufw disable && ufw --force enable
```