DC = docker compose -f docker-compose.yml

up:
	${DC} up -d

down:
	${DC} down

build:
	cp -n backend/.env backend/.env.local 2>/dev/null || true
	${DC} up -d --build
	${DC} exec php composer install
	${DC} exec php bin/console doctrine:migrations:migrate -n

lint:
	${DC} exec frontend yarn run lint

prettier:
	${DC} exec frontend yarn run prettier

xdebug_on:
	${DC} exec php /bin/sh -c 'cp /usr/local/etc/xdebug.ini /usr/local/etc/php/conf.d/ && kill -USR2 1'

xdebug_off:
	${DC} exec php /bin/sh -c 'rm /usr/local/etc/php/conf.d/xdebug.ini && kill -USR2 1'

in:
	${DC} exec php /bin/bash

cs:
	docker compose exec php php vendor/bin/phpcs --standard=phpcs.xml -n -p -s --parallel=32
csfix:
	docker compose exec php php vendor/bin/phpcbf --standard=phpcs.xml -n -p -s --parallel=32

init-project:
	@bash .tools/init-project.sh