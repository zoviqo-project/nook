FROM eclipse-temurin:17-jdk-alpine AS build
WORKDIR /src
COPY . .
RUN ./mvnw -q -DskipTests package
FROM eclipse-temurin:17-jre-alpine
RUN addgroup -S nook && adduser -S nook -G nook
WORKDIR /app
COPY --from=build /src/target/nook-backend-1.0.0.jar app.jar
RUN mkdir -p data/photos && chown -R nook:nook /app
USER nook
EXPOSE 8080
ENTRYPOINT ["java","-jar","app.jar"]
