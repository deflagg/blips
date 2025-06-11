# syntax=docker/dockerfile:1

############################################
# Stage 1 – BUILD  (needs devDependencies)
############################################
FROM node:20.18.2-alpine AS build 

WORKDIR /app

# 1  Copy manifests and install ALL deps (prod + dev)
COPY package*.json ./
RUN ls -la
RUN npm ci                                # ← NO --omit=dev here

# 2  Copy source and build with Vite
COPY . .
RUN npm run build                         # outputs to dist/

############################################
# Stage 2 – RUNTIME (no Node, no deps)
############################################
FROM nginx:1.27-alpine AS runtime

RUN apk upgrade --no-cache                # grab latest Alpine fixes

# 3  Copy static bundle only
COPY --from=build /app/dist /usr/share/nginx/html

# 4  SPA fallback so client-side routing works
RUN printf 'server { \
  listen 80; \
  server_name _; \
  root /usr/share/nginx/html; \
  location / { try_files $uri /index.html; } \
}\n' > /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
