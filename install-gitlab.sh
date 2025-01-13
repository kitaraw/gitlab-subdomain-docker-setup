#!/bin/bash

# Проверка прав суперпользователя
if [ "$EUID" -ne 0 ]; then
  echo "Пожалуйста, выполните этот скрипт с правами суперпользователя (sudo)."
  exit 1
fi

# Функция для установки необходимых пакетов
install_dependencies() {
  echo "Установка необходимых пакетов..."
  apt update && apt install -y curl gnupg certbot docker.io
  if ! command -v docker &>/dev/null; then
    echo "Ошибка: Docker не установлен."
    exit 1
  fi
}

# Установка Docker Compose
install_docker_compose() {
  if ! command -v docker-compose &>/dev/null; then
    echo "Установка Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
      -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
  fi
  docker-compose --version || {
    echo "Ошибка: Docker Compose не установлен."
    exit 1
  }
}

# Получение данных от пользователя
read -p "Введите имя домена (без http://, https:// и слешей): " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  echo "Ошибка: Доменное имя не может быть пустым."
  exit 1
fi

read -p "Вы хотите использовать стандартные порты 80 и 443? (y/n): " USE_DEFAULT_PORTS
if [[ "$USE_DEFAULT_PORTS" == "y" ]]; then
  HTTP_PORT=80
  HTTPS_PORT=443
  SSH_PORT=22
else
  echo "Убедитесь, что кастомные порты доступны извне. Также порт 80 должен быть открыт для работы Certbot."
  read -p "Введите HTTP порт: " HTTP_PORT
  read -p "Введите HTTPS порт: " HTTPS_PORT
  read -p "Введите SSH порт: " SSH_PORT
fi

# Установка зависимостей
install_dependencies
install_docker_compose

# Проверка существующих сертификатов
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
if [[ -d "$CERT_PATH" ]]; then
  echo "Сертификаты для домена $DOMAIN уже существуют. Пропуск генерации."
else
  echo "Генерация SSL-сертификатов для домена $DOMAIN..."
  certbot certonly --standalone --preferred-challenges http -d "$DOMAIN" || {
    echo "Ошибка: Сертификаты не сгенерированы."
    exit 1
  }
fi

# Копирование сертификатов
echo "Копирование сертификатов в директорию ssl..."
mkdir -p ssl
cp "$CERT_PATH/fullchain.pem" ./ssl/$DOMAIN.crt
cp "$CERT_PATH/privkey.pem" ./ssl/$DOMAIN.key

# Создание docker-compose.yml
echo "Создание docker-compose.yml на основе шаблона..."
sed -e "s/{{DOMAIN}}/$DOMAIN/g" \
    -e "s/{{HTTP_PORT}}/$HTTP_PORT/g" \
    -e "s/{{HTTPS_PORT}}/$HTTPS_PORT/g" \
    -e "s/{{SSH_PORT}}/$SSH_PORT/g" \
    docker-compose-template.yml > docker-compose.yml

# Запуск GitLab
echo "Запуск GitLab с помощью Docker Compose..."
docker-compose up -d

echo "Установка завершена. GitLab доступен по адресу https://$DOMAIN."
echo "Первое поднятие может занять более 5 минут."
