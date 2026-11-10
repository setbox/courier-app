ARG ELIXIR_VERSION=1.18.3
ARG OTP_VERSION=27

FROM elixir:${ELIXIR_VERSION}-otp-${OTP_VERSION}-alpine AS builder

RUN apk add --no-cache build-base git

ENV MIX_ENV=prod

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

RUN for i in 1 2 3; do \
      [ "$i" = 1 ] || sleep $(((i - 1) * 10)); \
      mix tailwind.install --if-missing && mix esbuild.install --if-missing && break; \
      echo "tentativa $i de baixar os binarios de assets falhou"; \
    done && \
    mix tailwind.install --if-missing && mix esbuild.install --if-missing

COPY priv priv
COPY lib lib
COPY assets assets
RUN mix compile
RUN mix assets.deploy

COPY config/runtime.exs config/
COPY rel rel
RUN mix release

FROM alpine:3.20 AS runtime

RUN apk add --no-cache openssl ncurses-libs libstdc++ libgcc tzdata

ENV PHX_SERVER=true
ENV LANG=C.UTF-8

WORKDIR /app
RUN chown nobody:nobody /app

COPY --from=builder --chown=nobody:nobody /app/_build/prod/rel/courier ./

USER nobody

EXPOSE 4000

CMD ["bin/server"]
