FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json ./
RUN npm install
COPY tsconfig.json ./
COPY src/ ./src/
RUN npx tsc

FROM node:20-alpine
WORKDIR /app
RUN apk add --no-cache curl wget python3
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY package.json ./
ENV PORT=8000
EXPOSE 8000
# Engine runner must NOT expose any public ports — internal network only
CMD ["node", "dist/server.js"]
