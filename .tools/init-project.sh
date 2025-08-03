#!/usr/bin/env bash
set -e

add_host_entry() {
  local domain="$1"
  local ip="127.0.0.1"
  local hosts_file

  if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    hosts_file="/c/Windows/System32/drivers/etc/hosts"
  else
    hosts_file="/etc/hosts"
  fi

  if grep -qE "^\s*${ip}\s+${domain}\b" "$hosts_file"; then
    echo "✅ $domain уже есть в $hosts_file"
  else
    echo "🛠️ Добавляю $domain → $ip в $hosts_file..."
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
      echo -e "\n${ip} ${domain}" >> "$hosts_file" && echo "✅ Успешно добавлено!"
    else
      echo -e "\n${ip} ${domain}" | sudo tee -a "$hosts_file" > /dev/null && echo "✅ Успешно добавлено!"
    fi
  fi
}

SOCK_PATH="/var/run/docker.sock"
[[ "$OSTYPE" == "msys" ]] && SOCK_PATH="//var/run/docker.sock"

echo "🔧 Инициализация нового проекта..."
read -rp "👉 Введите имя проекта (slug, например: myapp): " PROJECT
[[ -z "$PROJECT" ]] && { echo "❗ Имя проекта нужно обязательно"; exit 1; }

echo "⚙️ Заменяю плейсхолдер {project} на '$PROJECT'..."
sed -i "s/{project}/$PROJECT/g" docker-compose.yml
sed -i "s/{project}/$PROJECT/g" docker/nginx/default.conf

echo "🌐 Проверяю сеть nginx-proxy..."
if ! docker network inspect nginx-proxy >/dev/null 2>&1; then
  echo "🌐 Создаю сеть nginx-proxy..."
  docker network create nginx-proxy
else
  echo "🌐 Сеть nginx-proxy уже существует"
fi

if ! docker ps --filter name=nginx-proxy --filter status=running | grep nginx-proxy >/dev/null; then
  echo "🚀 Запускаю общий nginx-proxy..."
  docker run -d \
    --name nginx-proxy --restart always \
    -p 80:80 -v $SOCK_PATH:/tmp/docker.sock:ro \
    --network nginx-proxy jwilder/nginx-proxy
else
  echo "🚀 nginx-proxy уже запущен"
fi

echo "🐳 Собираю и запускаю контейнеры проекта..."
docker compose up -d --build

echo "📦 Устанавливаю Symfony внутри php-контейнера..."
docker compose exec -u root php bash -lc "
  set -euo pipefail
  TMP=\$(mktemp -d)
  echo '>> Создаю Symfony в \$TMP/app'
  COMPOSER_CACHE_DIR=/tmp/composer composer create-project symfony/skeleton:^7.1 \"\$TMP/app\" --no-interaction
  cd \"\$TMP/app\"
  composer require symfony/webapp-pack symfony/orm-pack --no-interaction
  composer require --dev symfony/maker-bundle --no-interaction
  shopt -s dotglob
  cp -an * /var/www/
  chown -R www-data:www-data /var/www || true
  echo '>> Symfony скопирован.'
"

if [ -f package.json ]; then
  echo "⚠️ React-проект уже создан. Пропускаю создание."
else
  echo "⚛️ Создаю React-приложение в frontend-контейнере..."
  rm -rf ./frontend/*
  docker compose exec -u root frontend sh -lc '
    pwd
    ls -la
    npx --yes create-vite@latest ./ --template react-ts
    pwd
    ls -la
    echo "🌸 Устанавливаю TailwindCSS..."
    yarn add -D tailwindcss postcss autoprefixer
    npx tailwindcss init -p

    echo "/** @type {import('tailwindcss').Config} */" > tailwind.config.js
    echo "module.exports = { content: [\"./index.html\", \"./src/**/*.{js,ts,jsx,tsx}\"], theme: { extend: {}, }, plugins: [], };" >> tailwind.config.js

    echo "@tailwind base;\n@tailwind components;\n@tailwind utilities;" > src/index.css
  '
fi

echo "🌐 Прописываю BACKEND_URL в frontend/.env"
echo "REACT_APP_BACKEND_URL=http://api.dev.$PROJECT" > frontend/.env

echo "🔧 Добавляю server.allowedHosts в vite.config.ts..."

if [ -f frontend/vite.config.ts ]; then
  awk -v host="dev.$PROJECT" '
    BEGIN { patched = 0 }
    /defineConfig\(\{/ && !patched {
      print
      print "  server: {"
      print "    allowedHosts: [\"" host "\"],"
      print "  },"
      patched = 1
      next
    }
    { print }
  ' frontend/vite.config.ts > frontend/vite.config.ts.tmp && mv frontend/vite.config.ts.tmp frontend/vite.config.ts
fi

add_host_entry "dev.$PROJECT"
add_host_entry "api.dev.$PROJECT"

if [ -d .git ]; then
  read -rp "❓ Удалить текущий .git и инициализировать новый? [y/N]: " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    rm -rf .git && git init && echo "✅ Репозиторий сброшен."
  fi
fi

rm -rf ./.tools

echo ""
echo "🎉 Готово! Проект '$PROJECT' развернут."
echo "📂 Папка проекта: $(pwd)"
echo "🌍 Фронт:  http://dev.$PROJECT"
echo "📡 API:    http://api.dev.$PROJECT"
