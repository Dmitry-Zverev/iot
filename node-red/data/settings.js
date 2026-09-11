/**
 * Настройки Node-RED.
 * Всё чувствительное берётся из переменных окружения (файл .env → docker-compose.yml),
 * поэтому этот файл безопасно хранить в git.
 */
module.exports = {
    flowFile: 'flows.json',

    // Флоу в git должны быть читаемыми в diff'ах, а не одной строкой
    flowFilePretty: true,

    uiPort: process.env.PORT || 1880,

    // Ключ шифрования для flows_cred.json (там лежат пароли из MQTT-нод).
    credentialSecret: process.env.NODE_RED_CREDENTIAL_SECRET,

    // Логин в редактор. Если хеш не задан — вход без пароля (удобно для первого запуска,
    // но scripts/setup его всегда генерирует).
    adminAuth: process.env.NODE_RED_ADMIN_HASH ? {
        type: "credentials",
        users: [{
            username: process.env.NODE_RED_ADMIN_USER || "admin",
            password: process.env.NODE_RED_ADMIN_HASH,
            permissions: "*"
        }]
    } : undefined,

    logging: {
        console: { level: "info", metrics: false, audit: false }
    },

    // Разрешаем функциям в function-нодах видеть эти модули.
    functionGlobalContext: {},

    // Node-RED 4: разрешить использовать ${ENV_VAR} в настройках нод
    editorTheme: {
        projects: { enabled: false },
        codeEditor: { lib: "monaco" }
    },

    // Таймаут HTTP-запросов из нод
    httpRequestTimeout: 120000,

    // Каталог, куда палитра ставит доп. ноды
    userDir: '/data',
};
