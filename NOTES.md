
user from crm_reactor creates an new db with a new user

```sh
docker exec -e PGPASSWORD=e1123fa504fae08e5cd06b428026f2c3 \
$(docker ps -q --filter name=crm_postgres) \
psql -U postgres_admin -d hex_gh \
 -c "CREATE DATABASE hex_gh;" \
-c "CREATE EXTENSION IF NOT EXISTS vector;" \
 -c "CREATE USER admin_hexgh WITH PASSWORD '05c13434b144859bfdb80fa6c3a2ebff';" \
 -c "GRANT ALL PRIVILEGES ON DATABASE hex_gh TO admin_hexgh;" \
 -c "GRANT ALL ON SCHEMA public TO admin_hexgh;"
```

```sh
docker exec $(docker ps -q --filter "name=crm_postgres") psql -U admin_hexgh -d hex_gh -c "SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';"
```

```sh
docker exec $(docker ps -q --filter name=crm_postgres) \
  pg_dump -U admin_hexgh -d hex_gh -Fc > hex_gh_$(date +%F).dump
```

```sh
docker exec $(docker ps -q --filter name=crm_postgres) psql -U admin_hexgh -d hex_gh -c \
  "COPY (SELECT id, kind, title, outdated, metadata::text, content
         FROM knowledge ORDER BY id) TO STDOUT WITH CSV HEADER" > knowledge_$(date +%F).csv
```
