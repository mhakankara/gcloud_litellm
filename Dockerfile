FROM ghcr.io/berriai/litellm-database:main-latest
WORKDIR /app
COPY config.yaml /app/config.yaml
EXPOSE 8080
CMD ["sh", "-c", "litellm --port $PORT --config ${LITELLM_CONFIG:-/app/config.yaml}"]