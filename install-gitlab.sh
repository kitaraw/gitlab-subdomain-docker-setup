#!/bin/bash

# Убедимся, что скрипт выполняется с правами суперпользователя
if [ "$EUID" -ne 0 ]; then
  echo "Пожалуйста, выполните этот скрипт с правами суперпользователя (sudo)."
  exit 1
fi

# Запрос имени домена
read -p "Введите имя домена (без http://, https:// и слешей): " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  echo "Ошибка: Доменное имя не может быть пустым."
  exit 1
fi

# Запрос портов
echo "Вы хотите использовать стандартные порты 80 и 443?"
read -p "Введите 'y' для использования стандартных портов или 'n' для кастомных: " USE_DEFAULT_PORTS

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

# Убедимся, что необходимые пакеты установлены
echo "Установка необходимых пакетов..."
apt update -y
apt install -y curl gnupg certbot docker.io

# Установка Docker Compose
echo "Установка Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Проверяем Docker Compose
docker-compose --version
if [ $? -ne 0 ]; then
  echo "Ошибка: Docker Compose не установлен."
  exit 1
fi

# Генерация SSL-сертификатов
echo "Генерация SSL-сертификатов для домена $DOMAIN..."
certbot certonly --standalone --preferred-challenges http -d "$DOMAIN"

if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
  echo "Ошибка: Сертификаты не сгенерированы."
  exit 1
fi

# Копирование сертификатов
echo "Копирование сертификатов в директорию ssl..."
mkdir -p ssl
cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem ./ssl/$DOMAIN.crt
cp /etc/letsencrypt/live/$DOMAIN/privkey.pem ./ssl/$DOMAIN.key

# Создание docker-compose.yml на основе шаблона
echo "Создание docker-compose.yml на основе шаблона..."
sed -e "s/{{DOMAIN}}/$DOMAIN/g" \
    -e "s/{{HTTP_PORT}}/$HTTP_PORT/g" \
    -e "s/{{HTTPS_PORT}}/$HTTPS_PORT/g" \
    -e "s/{{SSH_PORT}}/$SSH_PORT/g" \
    docker-compose-template.yml > docker-compose.yml

# Запуск GitLab
echo "Запуск GitLab с помощью Docker Compose..."
docker-compose up -d

echo "Установка завершена. GitLab доступен по адресу после того как поднимется https://$DOMAIN. Первое поднятие может быть долгим и занимать более 5 минут"
