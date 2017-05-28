# Контейнер с InfluxBD 1.2 включенным скриптом бэкапа

## Использование

### Клонируем репу с контейнером на сервер

    mkdir -p /docker/influxdb; cd /docker/influxdb
    git pull git@gitlab.southbridge.ru:docker/influxdb.git

### Собираем образ

    cd /docker/influxdb; docker build -t influxdb:latest influxdb:1.2-1 .

### Запускаем

    docker run -d --name influxdb:latest -v /docker/influxdb/data/:/var/lib/influxdb \
      -v /docker/influxdb/backups/:/var/backups/influxdb/ \
      -v /docker/influxdb/configs/infuxdb.cnf:/etc/influxdb/influxdb.cnf \
      influxdb

### Включаем снятие бэкапа

    echo "00 03 * * * root docker exec -ti influxdb /srv/southbridge/bin/influxdb-backup.sh > /var/log/influxdb-backup.log 2>&1" > /etc/cron.d/influxdb-backup
    cat << EOF >/etc/logrotate.d/influxdb-backup
    /var/log/influxdb-backup.log {
        missingok
        dateext
        notifempty
        nocompress
        copytruncate
        rotate 4
        weekly
    }
    EOF

## Как настроить контейнер

- Отключить бекапы?
- удалить /root/.influxdb

- Настройки бекапов?
- файл /srv/southbridge/etc/influxdb-backup.conf
-- BACKUP_DBS - список баз данных для дампа
-- BACKUP_METASTORE - бекап метаинформации о сервере в отдельную директорию
