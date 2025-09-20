FROM ghcr.io/berriai/litellm-database:main-latest
WORKDIR /app
ENV PYTHONUNBUFFERED="True"
COPY config.yaml config.yaml
EXPOSE 8080/tcp
CMD ["--port", "8080", "--config", "config.yaml"]