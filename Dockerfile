FROM php:8.3-fpm

LABEL maintainer="Firefly III Docker Maintainers"
LABEL description="Firefly III: A free and open source personal finance manager"

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    libpng-dev \
    libonig-dev \
    libxml2-dev \
    zip \
    unzip \
    nginx \
    libpq-dev \
    supervisor \
    postgresql-client \
    libzip-dev \
    libicu-dev \
    libgmp-dev \
    libsodium-dev \
    && rm -rf /var/lib/apt/lists/*

# Install PHP extensions
RUN docker-php-ext-install \
    pdo_mysql \
    pdo_pgsql \
    mbstring \
    exif \
    pcntl \
    bcmath \
    gd \
    intl \
    xml \
    soap \
    opcache \
    zip \
    gmp \
    sodium

# Configure PHP
COPY docker/php.ini /usr/local/etc/php/conf.d/custom.ini
RUN { \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.interned_strings_buffer=8'; \
    echo 'opcache.max_accelerated_files=4000'; \
    echo 'opcache.revalidate_freq=2'; \
    echo 'opcache.fast_shutdown=1'; \
    echo 'opcache.enable_cli=1'; \
    echo 'upload_max_filesize=100M'; \
    echo 'post_max_size=100M'; \
    echo 'memory_limit=512M'; \
    echo 'max_execution_time=300'; \
    echo 'max_input_time=300'; \
    echo 'display_errors=Off'; \
    echo 'log_errors=On'; \
    echo 'error_log=/dev/stderr'; \
} > /usr/local/etc/php/conf.d/custom.ini

# Configure PHP-FPM
RUN { \
    echo '[global]'; \
    echo 'error_log = /proc/self/fd/2'; \
    echo 'log_level = notice'; \
    echo 'access.log = /proc/self/fd/2'; \
    echo '[www]'; \
    echo 'clear_env = no'; \
    echo 'catch_workers_output = yes'; \
    echo 'decorate_workers_output = no'; \
    echo 'access.format = "%R - %u %t \"%m %r%Q%q\" %s %f %{mili}d %{kilo}M %C%%"'; \
} > /usr/local/etc/php-fpm.d/docker.conf

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Configure nginx
COPY nginx_app.conf /etc/nginx/sites-available/default
RUN echo "daemon off;" >> /etc/nginx/nginx.conf

# Set working directory
WORKDIR /var/www

# Copy application files
COPY . /var/www

# Copy start script
COPY start.sh /var/www/start.sh
RUN chmod +x /var/www/start.sh

# Install dependencies
RUN composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader

# Set permissions
RUN chown -R www-data:www-data /var/www/storage /var/www/bootstrap/cache

# Configure supervisor with detailed logging
RUN mkdir -p /var/log/supervisor
RUN { \
    echo '[supervisord]'; \
    echo 'nodaemon=true'; \
    echo 'logfile=/var/log/supervisor/supervisord.log'; \
    echo 'pidfile=/var/run/supervisord.pid'; \
    echo 'loglevel=info'; \
    echo ''; \
    echo '[program:nginx]'; \
    echo 'command=/usr/sbin/nginx'; \
    echo 'stdout_logfile=/dev/stdout'; \
    echo 'stdout_logfile_maxbytes=0'; \
    echo 'stderr_logfile=/dev/stderr'; \
    echo 'stderr_logfile_maxbytes=0'; \
    echo 'autorestart=true'; \
    echo 'startretries=3'; \
    echo ''; \
    echo '[program:php-fpm]'; \
    echo 'command=/usr/local/sbin/php-fpm'; \
    echo 'stdout_logfile=/dev/stdout'; \
    echo 'stdout_logfile_maxbytes=0'; \
    echo 'stderr_logfile=/dev/stderr'; \
    echo 'stderr_logfile_maxbytes=0'; \
    echo 'autorestart=true'; \
    echo 'startretries=3'; \
} > /etc/supervisor/conf.d/supervisord.conf

# Create directory for PHP logs
RUN mkdir -p /var/log/php
RUN touch /var/log/php/errors.log && chown www-data:www-data /var/log/php/errors.log

# Expose port 80
EXPOSE 80

# Health check using the built-in Laravel health check endpoint
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

# Environment variables
ENV PHP_OPCACHE_VALIDATE_TIMESTAMPS=0 \
    PHP_OPCACHE_MAX_ACCELERATED_FILES=10000 \
    PHP_OPCACHE_MEMORY_CONSUMPTION=128 \
    NGINX_ACCESS_LOG=/dev/stdout \
    NGINX_ERROR_LOG=/dev/stderr \
    PHP_FPM_ACCESS_LOG=/dev/stdout \
    PHP_FPM_ERROR_LOG=/dev/stderr

# Start using our script
CMD ["/var/www/start.sh"]
