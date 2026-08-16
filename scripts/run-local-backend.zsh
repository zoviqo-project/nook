#!/bin/zsh
set -a
source /Users/albertesteveferres/dev/nook/.env
export DB_URL='jdbc:postgresql://127.0.0.1:5432/nook'
export DB_USER="$POSTGRES_USER"
export DB_PASSWORD="$POSTGRES_PASSWORD"
export SPRING_PROFILES_ACTIVE=development
export APPLE_CLIENT_ID='com.albertesteveferres.nook'
set +a
exec /usr/bin/java -jar /Users/albertesteveferres/dev/nook/backend/target/nook-backend-1.0.0.jar
