# Node-RED с предустановленными нодами.
# Собирается автоматически при `docker compose up` — после клонирования
# репозитория ничего доставлять руками через палитру не нужно.
FROM nodered/node-red:4.0

# Dashboard 2.0 (@flowfuse/node-red-dashboard) — актуальная версия дашборда.
# Старый node-red-dashboard (1.x) больше не развивается, не используем его.
RUN npm install --no-audit --no-fund --no-update-notifier --omit=dev \
        @flowfuse/node-red-dashboard
