ARG BUILDER_IMAGE="hexpm/elixir:1.20.2-erlang-29.0.2-debian-trixie-20260623-slim"
ARG RUNNER_IMAGE="debian:trixie-slim"

# --- Build stage ---
FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && \
    apt-get install -y build-essential git python3 python3-pip && \
    pip3 install sqlite-vec --break-system-packages && \
    apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

RUN mkdir config
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile --force || mix deps.compile telegex --force
RUN mix assets.setup
COPY priv priv
COPY lib lib
COPY assets assets

RUN mix assets.deploy
RUN mix compile

COPY config/runtime.exs config/
COPY rel rel

RUN mix release

# --- Runner stage ---
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates \
    python3 python3-pip && \
    pip3 install sqlite-vec --break-system-packages && \
    apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app

RUN chown nobody /app
COPY --from=builder --chown=nobody:root /app/_build/prod/rel/hex_gh ./
RUN chmod +x /app/bin/server

# Data directory for SQLite memory DB (mount a volume here)
RUN mkdir -p /app/data && chown nobody /app/data
ENV MEMORY_DB_PATH=/app/data/memory.db

USER nobody

ENV PHX_SERVER=true
EXPOSE 4000

CMD ["/app/bin/server"]
