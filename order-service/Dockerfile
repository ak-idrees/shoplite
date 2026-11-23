
# =========================
# STAGE 1: BUILDER
# =========================
FROM maven:3.9-eclipse-temurin-21 AS builder

WORKDIR /app

# Copy Maven configuration
COPY pom.xml .

# Download dependencies
RUN mvn dependency:go-offline

# Copy application source
COPY src ./src

# Build the application
RUN mvn clean package -DskipTests


# =========================
# STAGE 2: FINAL
# =========================
FROM eclipse-temurin:21-jre-alpine AS final

WORKDIR /app

# Copy the generated JAR from builder
COPY --from=builder /app/target/*.jar app.jar

ENV SERVER_PORT=8082

EXPOSE 8082

USER 10001

ENTRYPOINT ["java", "-jar", "app.jar"]
