# Copyright 2024 Nils Knieling
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# The python:3.11-slim tag points to the latest release based on Debian 12 (bookworm)
FROM python:3.11-slim

WORKDIR /app

# Log Python messages immediately instead of being buffered
ENV PYTHONUNBUFFERED="True"

# Default HTTP port (Cloud Run will set $PORT at runtime)
EXPOSE 8080/tcp

# Install LiteLLM proxy + prisma client CLI, then generate Prisma client
COPY requirements.txt requirements.txt
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir prisma && \
    PRISMA_SCHEMA_PATH="$(python - <<'PY'\nimport litellm\nfrom pathlib import Path\np = Path(litellm.__file__).parent / 'proxy' / 'prisma' / 'schema.prisma'\nprint(p)\nPY\n)" && \
    python -m prisma generate --schema "$PRISMA_SCHEMA_PATH" && \
    pip cache purge

# Copy default config; can be overridden with --config
COPY config.yaml /app/config.yaml

# Use a tiny init for proper signal handling
RUN apt-get update && apt-get install -y --no-install-recommends tini && rm -rf /var/lib/apt/lists/*

# Start
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["sh", "-lc", "litellm --port ${PORT:-8080} --config ${LITELLM_CONFIG:-/app/config.yaml}"]
