FROM node:22.17.0-alpine

WORKDIR /var/www

RUN apk update \
    && apk add --no-cache python3 make g++ \
    && rm /var/cache/apk/*
