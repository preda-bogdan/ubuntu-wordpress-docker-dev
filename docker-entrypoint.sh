#!/bin/bash

set -euo pipefail

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}

if ! [ -e index.php -a -e wp-includes/version.php ]; then
	echo >&2 "WordPress not found in $PWD - copying now..."
	if [ "$(ls -A)" ]; then
		echo >&2 "WARNING: $PWD is not empty - press Ctrl+C now if this is an error!"
		( set -x; ls -A; sleep 10 )
	fi
	tar --create \
		--file - \
		--one-file-system \
		--directory /home/wordpress \
		--owner "www-data" --group "www-data" \
		. | tar --extract --file -
	echo >&2 "Complete! WordPress has been successfully copied to $PWD"
	if [ ! -e .htaccess ]; then
		# NOTE: The "Indexes" option is disabled in the php:apache base image
		cat > .htaccess <<-'EOF'
			# BEGIN WordPress
			<IfModule mod_rewrite.c>
			RewriteEngine On
			RewriteBase /
			RewriteRule ^index\.php$ - [L]
			RewriteCond %{REQUEST_FILENAME} !-f
			RewriteCond %{REQUEST_FILENAME} !-d
			RewriteRule . /index.php [L]
			</IfModule>
			# END WordPress
		EOF
		chown "www-data:www-data" .htaccess
	fi
fi

# TODO handle WordPress upgrades magically in the same way, but only if wp-includes/version.php's $wp_version is less than /usr/src/wordpress/wp-includes/version.php's $wp_version

# allow any of these "Authentication Unique Keys and Salts." to be specified via
# environment variables with a "WORDPRESS_" prefix (ie, "WORDPRESS_AUTH_KEY")
uniqueEnvs=(
	AUTH_KEY
	SECURE_AUTH_KEY
	LOGGED_IN_KEY
	NONCE_KEY
	AUTH_SALT
	SECURE_AUTH_SALT
	LOGGED_IN_SALT
	NONCE_SALT
)
envs=(
	WORDPRESS_DB_HOST
	WORDPRESS_DB_USER
	WORDPRESS_DB_PASSWORD
	WORDPRESS_DB_NAME
	"${uniqueEnvs[@]/#/WORDPRESS_}"
	WORDPRESS_TABLE_PREFIX
	WORDPRESS_DEBUG
)
haveConfig=
for e in "${envs[@]}"; do
	file_env "$e"
	if [ -z "$haveConfig" ] && [ -n "${!e}" ]; then
		haveConfig=1
	fi
done

# linking backwards-compatibility
if [ -n "${!MYSQL_ENV_MYSQL_*}" ]; then
	haveConfig=1
	# host defaults to "mysql" below if unspecified
	: "${WORDPRESS_DB_USER:=${MYSQL_ENV_MYSQL_USER:-root}}"
	if [ "$WORDPRESS_DB_USER" = 'root' ]; then
		: "${WORDPRESS_DB_PASSWORD:=${MYSQL_ENV_MYSQL_ROOT_PASSWORD:-}}"
	else
		: "${WORDPRESS_DB_PASSWORD:=${MYSQL_ENV_MYSQL_PASSWORD:-}}"
	fi
	: "${WORDPRESS_DB_NAME:=${MYSQL_ENV_MYSQL_DATABASE:-}}"
fi

# only touch "wp-config.php" if we have environment-supplied configuration values
if [ "$haveConfig" ]; then
	: "${WORDPRESS_DB_HOST:=mysql}"
	: "${WORDPRESS_DB_USER:=root}"
	: "${WORDPRESS_DB_PASSWORD:=}"
	: "${WORDPRESS_DB_NAME:=wordpress}"

	# version 4.4.1 decided to switch to windows line endings, that breaks our seds and awks
	# https://github.com/docker-library/wordpress/issues/116
	# https://github.com/WordPress/WordPress/commit/1acedc542fba2482bab88ec70d4bea4b997a92e4
	sed -ri -e 's/\r$//' wp-config*

	if [ ! -e wp-config.php ]; then
		wp config create --dbhost=$WORDPRESS_DB_HOST --dbname=$WORDPRESS_DB_NAME --dbuser=$WORDPRESS_DB_USER --dbpass=$WORDPRESS_DB_PASSWORD
		chown "www-data:www-data" wp-config.php
	fi
fi
#/etc/init.d/mysql start
#wp config create --dbhost=127.0.0.1 --dbname=wordpress --dbuser=root --dbpass=test
#chown "www-data:www-data" wp-config.php

for e in "${envs[@]}"; do
	unset "$e"
done

exec "$@"

php-fpm7.1
nginx -g 'daemon off;'
