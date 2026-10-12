# PHP: Laravel web application

[Documentation index](../README.md) | [Project README](../../README.md)

Follow the [shared setup guidance](./README.md) first. Run infrastructure commands
from the repository root and project commands from your application directory.

Requires PHP and Composer compatible with the selected Laravel release,
including the PDO MySQL extension.

```sh
composer create-project laravel/laravel php-web
cd php-web
composer require predis/predis
```

Configure Laravel's generated `.env`, replacing its existing database settings:

```dotenv
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=local_db
DB_USERNAME=dev_user
DB_PASSWORD=REPLACE_WITH_MYSQL_PASSWORD

REDIS_CLIENT=predis
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
REDIS_PASSWORD=null

MAIL_MAILER=smtp
MAIL_HOST=127.0.0.1
MAIL_PORT=1025
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_FROM_ADDRESS=developer@example.test
MAIL_FROM_NAME=Development
```

In Laravel's mail configuration, ensure SMTP transport is unencrypted for
Mailpit: use `MAIL_SCHEME=smtp` in releases using a scheme setting, or
`MAIL_ENCRYPTION=null` in releases using an encryption setting.
Inspect the generated mail configuration because these keys vary by release.

```sh
php artisan config:clear
php artisan migrate
php artisan serve --host=127.0.0.1 --port=8000
# In another terminal:
php artisan test
```

Open http://127.0.0.1:8000 and inspect test email at http://127.0.0.1:8025.
Redis is available but must be selected in your Laravel cache/queue configuration
if you want to use it. Run `php artisan queue:work` only after configuring a queue
connection and implementing jobs. For plain PHP, use PDO with the same database
settings; the built-in PHP server is for development only.
