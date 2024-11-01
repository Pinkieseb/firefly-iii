# This Procfile is used by Coolify to start the application
# It executes our start.sh script which handles initialization and process management

web: bash /var/www/start.sh 2>&1 | tee -a /var/log/firefly-startup.log
