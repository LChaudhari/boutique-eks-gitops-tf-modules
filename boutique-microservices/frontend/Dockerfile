# Frontend Dockerfile
FROM node:20-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./
RUN npm install --production=false

# Copy source code
COPY . .

# API base URL baked into the static CRA bundle at build time (REACT_APP_*).
# Defaults to a same-origin relative path so the SPA calls the same host it was
# served from (/api -> ALB ingress -> gateway), working without a hard-coded
# domain. Override at build: --build-arg REACT_APP_API_URL=https://<domain>/api
ARG REACT_APP_API_URL=/api
ENV REACT_APP_API_URL=$REACT_APP_API_URL

# Build the app
RUN npm run build

# Install serve globally
RUN npm install -g serve

EXPOSE 3000

# Use serve to host the static files
CMD ["serve", "-s", "build", "-l", "3000", "--single"]