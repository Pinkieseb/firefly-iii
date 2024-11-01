#!/bin/bash

# Exit on error, but allow retries for certain commands
set -e

# Function for logging with timestamps and log levels
log() {
    local level=$1
    shift
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a /var/log/firefly-startup.log
}

# Function to check if PostgreSQL is ready
check_postgres() {
    log "INFO" "Checking PostgreSQL connection..."
    max_attempts=30
    counter=0

    until pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" > /dev/null 2>&1; do
        counter=$((counter + 1))
        if [ $counter -eq $max_attempts ]; then
            log "ERROR" "Failed to connect to PostgreSQL after $max_attempts attempts"
            return 1
        fi
        log "WARN" "Waiting for PostgreSQL to become ready... (Attempt $counter/$max_attempts)"
        sleep 2
    done
    log "INFO" "Successfully connected to PostgreSQL"
    return 0
}

# Function to verify required environment variables
verify_env_vars() {
    log "INFO" "Verifying environment variables..."
    local required_vars=(
        "APP_KEY"
        "DB_HOST"
        "DB_PORT"
        "DB_DATABASE"
        "DB_USERNAME"
        "DB_PASSWORD"
        "APP_URL"
    )

    local missing_vars=0
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            log "ERROR" "Required environment variable $var is not set"
            missing_vars=$((missing_vars + 1))
        fi
    done

    if [ $missing_vars -gt 0 ]; then
        log "ERROR" "Missing $missing_vars required environment variables"
        return 1
    fi

    log "INFO" "All required environment variables are set"
    return 0
}

# Function to setup Laravel application
setup_laravel() {
    log "INFO" "Setting up Laravel application..."

    # Create storage directory structure if it doesn't exist
    local storage_dirs=(
        "storage/app/public"
        "storage/framework/cache"
        "storage/framework/sessions"
        "storage/framework/views"
        "storage/logs"
        "bootstrap/cache"
    )

    for dir in "${storage_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log "INFO" "Creating directory: $dir"
            mkdir -p "$dir"
        fi
    done

    # Set proper permissions
    log "INFO" "Setting proper permissions..."
    chown -R www-data:www-data storage bootstrap/cache
    chmod -R 775 storage bootstrap/cache

    # Clear various caches
    log "INFO" "Clearing caches..."
    php artisan config:clear
    php artisan cache:clear
    php artisan view:clear
    php artisan route:clear

    # Optimize for production
    log "INFO" "Optimizing for production..."
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
    php artisan event:cache

    # Run migrations
    log "INFO" "Running database migrations..."
    if php artisan migrate --force; then
        log "INFO" "Database migrations completed successfully"
    else
        log "ERROR" "Database migrations failed"
        return 1
    fi

    # Create storage link if it doesn't exist
    if [ ! -L "public/storage" ]; then
        log "INFO" "Creating storage link..."
        php artisan storage:link
    fi

    return 0
}

# Function to verify application health
check_application_health() {
    log "INFO" "Verifying application health..."
    max_attempts=5
    counter=0

    until curl -s -f http://localhost/health > /dev/null 2>&1; do
        counter=$((counter + 1))
        if [ $counter -eq $max_attempts ]; then
            log "ERROR" "Application failed health check after $max_attempts attempts"
            return 1
        fi
        log "WARN" "Waiting for application to become healthy... (Attempt $counter/$max_attempts)"
        sleep 5
    done
    log "INFO" "Application is healthy"
    return 0
}

# Main execution
main() {
    log "INFO" "Starting Firefly III initialization..."

    # Create log directory
    mkdir -p /var/log
    touch /var/log/firefly-startup.log
    chown www-data:www-data /var/log/firefly-startup.log

    # Verify environment variables
    verify_env_vars || exit 1

    # Wait for database
    check_postgres || exit 1

    # Setup Laravel application
    setup_laravel || exit 1

    # Start supervisor (which manages nginx and php-fpm)
    log "INFO" "Starting supervisord..."
    exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
}

# Run main function
main
