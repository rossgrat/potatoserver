FROM node:24.22.2-bookworm-slim@sha256:01d566e8d94d8c619591d78652babfccd3c6992a3dffa9ed5ab39e11cf6c70e9 AS build
WORKDIR /app
ENV NEXT_TELEMETRY_DISABLED=1
ADD https://codeload.github.com/hunvreus/pagescms/tar.gz/6f4e860a35d934406580287e7042e5e111e207a1 /tmp/pagescms.tar.gz
RUN echo '62f2e59fac6eb061162f858e9239c697620e1ed0183c2324b0f2a14137f43684  /tmp/pagescms.tar.gz' | sha256sum -c - \
    && tar -xzf /tmp/pagescms.tar.gz --strip-components=1 -C /app \
    && rm /tmp/pagescms.tar.gz
COPY package.json package-lock.json ./
RUN --mount=type=cache,id=pages-cms-npm,target=/root/.npm npm ci --no-audit --no-fund
COPY patch-auth.mjs patch-validation.mjs sign-in.tsx owner-access.test.ts token-refresh.test.mjs hardening.test.mjs /tmp/pages-cms/
RUN node /tmp/pages-cms/patch-auth.mjs \
    && node /tmp/pages-cms/patch-validation.mjs \
    && node --import tsx --test scripts/owner-access.test.ts scripts/token-refresh.test.mjs scripts/hardening.test.mjs
RUN BASE_URL=https://cms.grattafiori.dev \
    DATABASE_URL=postgresql://build:build@127.0.0.1:5432/build \
    BETTER_AUTH_SECRET=build-only-placeholder-not-a-runtime-secret \
    npm exec -- next build

FROM node:24.22.2-bookworm-slim@sha256:01d566e8d94d8c619591d78652babfccd3c6992a3dffa9ed5ab39e11cf6c70e9
WORKDIR /app
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1
COPY --from=build --chown=node:node /app /app
USER node
EXPOSE 3000
CMD ["npm", "run", "start"]
