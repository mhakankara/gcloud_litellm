FROM ghcr.io/berriai/litellm-database:main-latest
WORKDIR /app
COPY config.yaml /app/config.yaml
EXPOSE 8080
CMD ["litellm", "--port", "${PORT:-8080}", "--config", "${LITELLM_CONFIG:-/app/config.yaml}"]