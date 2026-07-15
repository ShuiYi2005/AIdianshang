FROM node:20-alpine AS build

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:20-alpine

WORKDIR /app
ENV PORT=4173
COPY server.mjs ./server.mjs
COPY --from=build /app/dist ./dist
EXPOSE 4173
CMD ["node", "server.mjs"]
