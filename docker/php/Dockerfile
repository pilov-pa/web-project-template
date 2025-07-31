# syntax=docker/dockerfile:1.7

############################################
# Base image: PHP 8.4 FPM on Debian bookworm
############################################
ARG PHP_VERSION=8.4
FROM php:${PHP_VERSION}-fpm-bookworm AS base

ENV DEBIAN_FRONTEND=noninteractive

# Базовые пакеты, dev-toolchain и заголовки для ext
# clang нужен только для сборки intl (обход ICE gcc)
RUN apt-get update && apt-get install -y --no-install-recommends \
      git unzip bash tzdata ca-certificates \
      libicu-dev libzip-dev zlib1g-dev libpq-dev \
      $PHPIZE_DEPS clang \
    && rm -rf /var/lib/apt/lists/*

# ---- Сборка intl под clang и -O1 (обход ICE) ----
ENV CC=clang CXX=clang++ CFLAGS="-O1" CXXFLAGS="-O1"
RUN docker-php-ext-configure intl \
 && docker-php-ext-install -j"$(nproc)" intl

# Остальные расширения — дефолтным gcc
ENV CC= CXX= CFLAGS= CXXFLAGS=
RUN docker-php-ext-configure zip \
 && docker-php-ext-install -j"$(nproc)" zip pdo_pgsql bcmath opcache

# Опционально: PECL redis (включается ARG-ом)
ARG WITH_REDIS=true
RUN if [ "$WITH_REDIS" = "true" ]; then \
      pecl install redis && docker-php-ext-enable redis ; \
    fi

# Рекомендованные настройки OPcache (переопредели в dev через volume, если надо)
RUN { \
      echo 'opcache.enable=1'; \
      echo 'opcache.enable_cli=0'; \
      echo 'opcache.memory_consumption=256'; \
      echo 'opcache.max_accelerated_files=20000'; \
      echo 'opcache.validate_timestamps=0'; \
      echo 'opcache.revalidate_freq=0'; \
      echo 'opcache.jit=1255'; \
      echo 'opcache.jit_buffer_size=128M'; \
    } > /usr/local/etc/php/conf.d/90-opcache-recommended.ini

# Таймзона
ARG TZ=Europe/Amsterdam
ENV TZ=$TZ
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Composer из официального образа
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

# Рабочая директория
WORKDIR /var/www/html

# Права: маппим www-data под пользователя хоста
ARG PUID=1000
ARG PGID=1000
RUN groupmod -o -g $PGID www-data && usermod -o -u $PUID -g $PGID www-data
USER www-data

EXPOSE 9000

############################################
# Dev stage: Xdebug по флагу
############################################
FROM base AS dev

ARG WITH_XDEBUG=true
USER root
RUN if [ "$WITH_XDEBUG" = "true" ]; then \
      pecl install xdebug && docker-php-ext-enable xdebug && \
      { \
        echo "zend_extension=$(php -r 'echo ini_get(\"extension_dir\");')/xdebug.so"; \
        echo "xdebug.mode=debug,develop"; \
        echo "xdebug.discover_client_host=1"; \
        echo "xdebug.client_port=9003"; \
        echo "xdebug.start_with_request=yes"; \
      } > /usr/local/etc/php/conf.d/99-xdebug.ini ; \
    fi
USER www-data

############################################
# Prod stage: код + prod-зависимости без dev
############################################
FROM base AS prod

# Чистим сборочные зависимости, чтобы облегчить образ
USER root
RUN apt-get purge -y --auto-remove $PHPIZE_DEPS clang \
 && rm -rf /var/lib/apt/lists/*
USER www-data

# Копируем проект (если он уже есть при сборке)
COPY --chown=www-data:www-data . /var/www/html

# Ставим зависимости без dev (если есть composer.json)
RUN if [ -f composer.json ]; then \
      composer install --no-dev --prefer-dist --no-progress --no-interaction && \
      php -r "if (function_exists('opcache_reset')) opcache_reset();" ; \
    fi

CMD ["php-fpm"]
