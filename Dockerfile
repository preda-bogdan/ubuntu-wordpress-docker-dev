FROM ubuntu:16.04

RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

RUN apt-get update && apt-get install -y --no-install-recommends \
		software-properties-common \
		language-pack-en-base \
		build-essential \
		bash \
		sudo \
		nano \
		cron \
		wget \
		unzip \
		mysql-client \
        openssh-client \
        git \
        curl \
		nginx \
	&& LC_ALL=en_US.UTF-8 add-apt-repository ppa:ondrej/php && apt-get update && apt-get install -y --no-install-recommends \
		php7.1-fpm \
		php7.1-common \
		php7.1-mbstring \
		php7.1-xmlrpc \
		php7.1-soap \
		php7.1-gd \
		php7.1-xml \
		php7.1-intl \
		php7.1-mysql \
		php7.1-cli \
		php7.1-mcrypt \
		php7.1-zip \
		php7.1-curl \
		php7.1-dev

RUN curl -o /bin/wp-cli.phar https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar

COPY wp.sh /bin/wp

RUN chmod +x /bin/wp-cli.phar /bin/wp

RUN apt-get install -y sudo

ENV WORDPRESS_VERSION 4.9.6
ENV WORDPRESS_SHA1 40616b40d120c97205e5852c03096115c2fca537

RUN mkdir -p /home/wordpress

RUN set -ex; \
	curl -o wordpress.tar.gz -fSL "https://wordpress.org/wordpress-${WORDPRESS_VERSION}.tar.gz"; \
	echo "$WORDPRESS_SHA1 *wordpress.tar.gz" | sha1sum -c -; \
	tar -xzf wordpress.tar.gz -C /home/; \
	rm wordpress.tar.gz; \
	chown -R www-data:www-data /home/

RUN cp -R /home/wordpress/* /var/www/html/

RUN chown -R www-data:www-data /var/www/html/

RUN	curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/bin --filename=composer --version=1.1.2 && \
	chmod +x /usr/bin/composer

RUN cd ~ && curl -sL https://deb.nodesource.com/setup_8.x -o nodesource_setup.sh && bash nodesource_setup.sh \
	&& apt-get update && apt-get install -y nodejs && nodejs -v && npm -v

COPY nginx/nginx.conf /etc/nginx/sites-enabled/default

COPY phpfpm/php-fpm.conf  /etc/php/7.1/fpm/pool.d/www.conf

RUN service php7.1-fpm start

COPY wordpress/.htaccess /var/www/html/.htaccess

COPY wordpress/index.php /var/www/html/index.php

COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
RUN ln -s usr/local/bin/docker-entrypoint.sh / # backwards compat

#USER www-data

#RUN cd /var/www/html/ && wp config create --dbhost=$WORDPRESS_DB_HOST --dbname=$WORDPRESS_DB_NAME --dbuser=$WORDPRESS_DB_USER --dbpass=$WORDPRESS_DB_PASSWORD

WORKDIR /var/www/html

EXPOSE 80 3306

ENTRYPOINT ["docker-entrypoint.sh"]

