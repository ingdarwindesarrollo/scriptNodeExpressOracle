# ============================================================
#  setup.ps1 — Crea el proyecto msp-backend completo
#  Uso: .\setup.ps1
#       .\setup.ps1 -NombreProyecto "mi-api"
#       .\setup.ps1 -SkipDocker
# ============================================================

param(
    [string]$NombreProyecto = "msp-backend",
    [switch]$SkipDocker
)

# ── Colores helpers ─────────────────────────────────────────
function Ok    { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Info  { param($msg) Write-Host "  --> $msg"  -ForegroundColor Cyan  }
function Warn  { param($msg) Write-Host "  [!] $msg"  -ForegroundColor Yellow }
function Title { param($msg) Write-Host "`n=== $msg ===" -ForegroundColor Magenta }

# ── Verificar requisitos ─────────────────────────────────────
Title "Verificando requisitos"

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "  [ERROR] Node.js no encontrado. Instálalo desde https://nodejs.org" -ForegroundColor Red
    exit 1
}
Ok "Node.js $(node --version)"

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Host "  [ERROR] npm no encontrado." -ForegroundColor Red
    exit 1
}
Ok "npm $(npm --version)"

$dockerDisponible = $null -ne (Get-Command docker -ErrorAction SilentlyContinue)
if ($dockerDisponible) {
    Ok "Docker disponible"
} else {
    Warn "Docker no encontrado - se omitira la creacion del contenedor Oracle"
    $SkipDocker = $true
}

# ── Crear carpeta del proyecto ───────────────────────────────
Title "Creando proyecto: $NombreProyecto"

if (Test-Path $NombreProyecto) {
    Warn "La carpeta '$NombreProyecto' ya existe. Continuando dentro de ella..."
} else {
    New-Item -ItemType Directory -Name $NombreProyecto | Out-Null
    Ok "Carpeta creada"
}

Set-Location $NombreProyecto

# ── npm init ─────────────────────────────────────────────────
Title "Inicializando npm"
npm init -y | Out-Null
Ok "package.json creado"

# Inyectar scripts y type en package.json
$pkg = Get-Content "package.json" -Raw | ConvertFrom-Json
$pkg.main = "src/app.js"
$pkg | Add-Member -Force -MemberType NoteProperty -Name "type"    -Value "commonjs"
$pkg | Add-Member -Force -MemberType NoteProperty -Name "scripts" -Value @{
    dev   = "nodemon src/app.js"
    start = "node src/app.js"
}
$pkg | ConvertTo-Json -Depth 10 | Set-Content "package.json" -Encoding UTF8
Ok "package.json configurado (scripts + type)"

# ── Instalar dependencias ─────────────────────────────────────
Title "Instalando dependencias"
Info "Instalando producción..."
npm install express cors helmet dotenv oracledb express-validator winston --save-exact 2>&1 | Out-Null
Ok "express, cors, helmet, dotenv, oracledb, express-validator, winston"

Info "Instalando desarrollo..."
npm install nodemon --save-dev 2>&1 | Out-Null
Ok "nodemon"

# ── Crear estructura de carpetas ──────────────────────────────
Title "Creando estructura de carpetas"

$carpetas = @(
    "src/config",
    "src/controllers",
    "src/services",
    "src/routes",
    "src/middlewares",
    "src/utils",
    "logs"
)

foreach ($dir in $carpetas) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}
Ok "src/config, controllers, services, routes, middlewares, utils, logs"

# ── Crear archivos ────────────────────────────────────────────
Title "Creando archivos del proyecto"

# .env
@'
DB_USER=system
DB_PASS=123456
DB_CONN=localhost/XEPDB1
'@ | Set-Content ".env" -Encoding UTF8
Ok ".env"

# .gitignore
@'
node_modules/
.env
logs/
'@ | Set-Content ".gitignore" -Encoding UTF8
Ok ".gitignore"

# init-db.js
@'
const oracledb = require('oracledb');

async function init() {
    let conn;
    try {
        conn = await oracledb.getConnection({
            user: 'system',
            password: '123456',
            connectString: 'localhost/XEPDB1'
        });
        console.log('Conectado');

        await conn.execute(`
            BEGIN
                EXECUTE IMMEDIATE '
                    CREATE TABLE users (
                        id NUMBER GENERATED ALWAYS AS IDENTITY,
                        name VARCHAR2(100),
                        email VARCHAR2(100),
                        PRIMARY KEY (id)
                    )
                ';
            EXCEPTION
                WHEN OTHERS THEN
                    IF SQLCODE != -955 THEN RAISE; END IF;
            END;
        `);
        console.log('Tabla users lista');
    } catch (err) {
        console.error(err);
    } finally {
        if (conn) await conn.close();
    }
}

init();
'@ | Set-Content "init-db.js" -Encoding UTF8
Ok "init-db.js"

# src/config/db.js
@'
const oracledb = require('oracledb');
require('dotenv').config();

async function initDB() {
    try {
        await oracledb.createPool({
            user: process.env.DB_USER,
            password: process.env.DB_PASS,
            connectString: process.env.DB_CONN,
            poolMin: 1,
            poolMax: 5
        });
        console.log('Oracle conectado');
    } catch (err) {
        console.error(err);
    }
}

async function getConnection() {
    return await oracledb.getConnection();
}

module.exports = { initDB, getConnection };
'@ | Set-Content "src/config/db.js" -Encoding UTF8
Ok "src/config/db.js"

# src/utils/logger.js
@'
const { createLogger, format, transports } = require('winston');

const logger = createLogger({
    level: 'info',
    format: format.combine(
        format.timestamp(),
        format.printf(({ level, message, timestamp }) => {
            return `${timestamp} [${level.toUpperCase()}]: ${message}`;
        })
    ),
    transports: [
        new transports.Console(),
        new transports.File({ filename: 'logs/error.log', level: 'error' }),
        new transports.File({ filename: 'logs/combined.log' })
    ]
});

module.exports = logger;
'@ | Set-Content "src/utils/logger.js" -Encoding UTF8
Ok "src/utils/logger.js"

# src/middlewares/user.validator.js
@'
const { body } = require('express-validator');

exports.createUserValidator = [
    body('name')
        .notEmpty().withMessage('Nombre requerido')
        .isLength({ min: 3 }).withMessage('Minimo 3 caracteres'),

    body('email')
        .isEmail().withMessage('Email invalido')
];
'@ | Set-Content "src/middlewares/user.validator.js" -Encoding UTF8
Ok "src/middlewares/user.validator.js"

# src/middlewares/validate.js
@'
const { validationResult } = require('express-validator');

function validate(req, res, next) {
    const errors = validationResult(req);

    if (!errors.isEmpty()) {
        return res.status(400).json({
            success: false,
            errors: errors.array()
        });
    }

    next();
}

module.exports = validate;
'@ | Set-Content "src/middlewares/validate.js" -Encoding UTF8
Ok "src/middlewares/validate.js"

# src/middlewares/error.middleware.js
@'
const logger = require('../utils/logger');

function errorHandler(err, req, res, next) {
    let message = err.message;
    let status = err.status || 500;

    if (err.message.includes('ORA-00001')) {
        message = 'Registro duplicado';
        status = 400;
    }
    if (err.message.includes('ORA-00942')) {
        message = 'Tabla no existe';
        status = 500;
    }
    if (err.message.includes('ORA-02291')) {
        message = 'Violacion de clave foranea';
        status = 400;
    }

    logger.error(`${req.method} ${req.url} - ${message}`);

    res.status(status).json({
        success: false,
        message
    });
}

module.exports = errorHandler;
'@ | Set-Content "src/middlewares/error.middleware.js" -Encoding UTF8
Ok "src/middlewares/error.middleware.js"

# src/services/user.service.js
@'
const { getConnection } = require('../config/db');

async function getAll() {
    const conn = await getConnection();
    const res = await conn.execute(`SELECT * FROM users`);
    await conn.close();
    return res.rows;
}

async function getById(id) {
    const conn = await getConnection();
    const res = await conn.execute(
        `SELECT * FROM users WHERE id = :id`,
        { id }
    );
    await conn.close();
    return res.rows[0];
}

async function create(user) {
    const conn = await getConnection();
    await conn.execute(
        `INSERT INTO users (name, email) VALUES (:name, :email)`,
        user,
        { autoCommit: true }
    );
    await conn.close();
}

async function update(id, user) {
    const conn = await getConnection();
    await conn.execute(
        `UPDATE users SET name=:name, email=:email WHERE id=:id`,
        { ...user, id },
        { autoCommit: true }
    );
    await conn.close();
}

async function remove(id) {
    const conn = await getConnection();
    await conn.execute(
        `DELETE FROM users WHERE id=:id`,
        { id },
        { autoCommit: true }
    );
    await conn.close();
}

module.exports = { getAll, getById, create, update, remove };
'@ | Set-Content "src/services/user.service.js" -Encoding UTF8
Ok "src/services/user.service.js"

# src/controllers/user.controllers.js
@'
const service = require('../services/user.service');

exports.getAll = async (req, res, next) => {
    try {
        res.json(await service.getAll());
    } catch (err) { next(err); }
};

exports.getOne = async (req, res, next) => {
    try {
        const data = await service.getById(req.params.id);
        if (!data) {
            const error = new Error('Usuario no existe');
            error.status = 404;
            return next(error);
        }
        res.json(data);
    } catch (err) { next(err); }
};

exports.create = async (req, res, next) => {
    try {
        await service.create(req.body);
        res.status(201).json({ message: 'Creado' });
    } catch (err) { next(err); }
};

exports.update = async (req, res, next) => {
    try {
        await service.update(req.params.id, req.body);
        res.json({ message: 'Actualizado' });
    } catch (err) { next(err); }
};

exports.delete = async (req, res, next) => {
    try {
        await service.remove(req.params.id);
        res.json({ message: 'Eliminado' });
    } catch (err) { next(err); }
};
'@ | Set-Content "src/controllers/user.controllers.js" -Encoding UTF8
Ok "src/controllers/user.controllers.js"

# src/routes/user.routes.js
@'
const router = require('express').Router();
const c = require('../controllers/user.controllers');
const validate = require('../middlewares/validate');
const { createUserValidator } = require('../middlewares/user.validator');

router.get('/',    c.getAll);
router.get('/:id', c.getOne);

router.post(
    '/',
    createUserValidator,
    validate,
    c.create
);

router.put('/:id',    c.update);
router.delete('/:id', c.delete);

module.exports = router;
'@ | Set-Content "src/routes/user.routes.js" -Encoding UTF8
Ok "src/routes/user.routes.js"

# src/app.js
@'
const express = require('express');
const cors    = require('cors');
const helmet  = require('helmet');

const { initDB }     = require('./config/db');
const userRoutes     = require('./routes/user.routes');
const errorHandler   = require('./middlewares/error.middleware');

const app = express();

app.use(cors());
app.use(helmet());
app.use(express.json());

app.use('/api/users', userRoutes);

initDB();

app.listen(3000, () => {
    console.log('Servidor en http://localhost:3000');
});

app.use(errorHandler);
'@ | Set-Content "src/app.js" -Encoding UTF8
Ok "src/app.js"

# ── Docker: Oracle XE ─────────────────────────────────────────
if (-not $SkipDocker) {
    Title "Levantando Oracle XE en Docker"

    $contenedorExiste = docker ps -a --format "{{.Names}}" 2>$null | Where-Object { $_ -eq "oracle-xe" }

    if ($contenedorExiste) {
        $estado = docker inspect -f "{{.State.Running}}" oracle-xe 2>$null
        if ($estado -eq "true") {
            Warn "El contenedor 'oracle-xe' ya está corriendo. No se vuelve a crear."
        } else {
            Info "El contenedor existe pero está detenido. Arrancando..."
            docker start oracle-xe | Out-Null
            Ok "Contenedor 'oracle-xe' arrancado"
        }
    } else {
        Info "Descargando imagen y creando contenedor (puede tardar unos minutos)..."
        docker run -d -p 1521:1521 -e ORACLE_PASSWORD=123456 --name oracle-xe gvenzl/oracle-xe | Out-Null
        Ok "Contenedor 'oracle-xe' creado y arrancando en segundo plano"
        Warn "Oracle XE tarda ~90 segundos en inicializarse."
        Info "Ejecuta 'docker logs -f oracle-xe' y espera el mensaje: DATABASE IS READY TO USE!"
    }
}

# ── Resumen final ─────────────────────────────────────────────
Title "Proyecto listo"

Write-Host ""
Write-Host "  Estructura creada:" -ForegroundColor White
Write-Host "    $NombreProyecto/"
Write-Host "    +-- src/app.js"
Write-Host "    +-- src/config/db.js"
Write-Host "    +-- src/routes/user.routes.js"
Write-Host "    +-- src/controllers/user.controllers.js"
Write-Host "    +-- src/services/user.service.js"
Write-Host "    +-- src/middlewares/{error.middleware, validate, user.validator}.js"
Write-Host "    +-- src/utils/logger.js"
Write-Host "    +-- init-db.js"
Write-Host "    +-- .env"
Write-Host "    \-- .gitignore"
Write-Host ""
Write-Host "  Proximos pasos:" -ForegroundColor White
if (-not $SkipDocker) {
    Write-Host "    1. Espera el mensaje 'DATABASE IS READY TO USE!' en los logs de Docker"
    Write-Host "       docker logs -f oracle-xe"
    Write-Host "    2. Crea la tabla:"
    Write-Host "       node init-db.js"
    Write-Host "    3. Arranca el servidor:"
    Write-Host "       npm run dev"
} else {
    Write-Host "    1. Levanta Oracle XE manualmente o con Docker:"
    Write-Host "       docker run -d -p 1521:1521 -e ORACLE_PASSWORD=123456 --name oracle-xe gvenzl/oracle-xe"
    Write-Host "    2. Crea la tabla:"
    Write-Host "       node init-db.js"
    Write-Host "    3. Arranca el servidor:"
    Write-Host "       npm run dev"
}
Write-Host ""
Write-Host "  API disponible en: http://localhost:3000/api/users" -ForegroundColor Green
Write-Host ""
