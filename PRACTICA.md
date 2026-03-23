# Práctica técnica: API REST con Node.js, Express y Oracle DB

> **Nivel:** Principiante → Intermedio  
> **Objetivo:** Construir desde cero una API REST completa con arquitectura en capas, validaciones, manejo de errores centralizado y logging, conectada a una base de datos Oracle.

---

## ¿Qué vamos a construir?

Un backend (servidor) que expone una API REST para gestionar **usuarios** (crear, leer, actualizar y borrar — CRUD). El servidor:

- Escucha peticiones HTTP en el puerto 3000
- Valida los datos que llegan antes de procesarlos
- Se conecta a Oracle Database
- Registra errores en archivos de log
- Está organizado en capas (rutas → controladores → servicios → base de datos)

---

## Conceptos previos (léelos antes de empezar)

| Concepto | ¿Qué es? |
|---|---|
| **Node.js** | Entorno que permite ejecutar JavaScript fuera del navegador, en el servidor |
| **Express** | Framework minimalista para crear servidores HTTP con Node.js |
| **API REST** | Interfaz que permite comunicar el frontend con el backend usando HTTP (GET, POST, PUT, DELETE) |
| **Middleware** | Función que se ejecuta entre que llega la petición y se envía la respuesta |
| **ORM / Driver** | Librería que permite hablar con la base de datos desde código JavaScript |
| **dotenv** | Librería para leer variables de entorno desde un archivo `.env` |

---

## Requisitos previos instalados

- [Node.js](https://nodejs.org) v18 o superior
- [Docker Desktop](https://www.docker.com/products/docker-desktop) instalado y corriendo
- Un cliente REST para probar: [Postman](https://www.postman.com) o [Thunder Client](https://www.thunderclient.com)

---

## Paso 0 — Levantar Oracle XE con Docker

Antes de escribir una sola línea de código del proyecto, necesitamos tener la base de datos disponible. En lugar de instalar Oracle manualmente (un proceso largo y complejo), usamos **Docker** para tenerla corriendo en segundos.

### ¿Qué es Docker?

Docker es una herramienta que permite ejecutar aplicaciones dentro de **contenedores**: entornos aislados, ligeros y reproducibles. Un contenedor empaqueta el programa y todo lo que necesita para funcionar (sistema operativo mínimo, librerías, configuración), de modo que funciona igual en cualquier máquina.

| Concepto Docker | Analogía |
|---|---|
| **Imagen** | Receta de cocina (plantilla de solo lectura) |
| **Contenedor** | El plato cocinado (instancia en ejecución de una imagen) |
| **Docker Hub** | Repositorio público de imágenes listas para usar |

### ¿Por qué usar Docker para Oracle en lugar de instalarlo directamente?

| Instalación manual | Con Docker |
|---|---|
| Requiere 4–8 GB de espacio en el sistema | La imagen pesa ~1 GB |
| El instalador puede tardar 30–60 minutos | Lista en 2–3 minutos |
| Difícil de desinstalar limpiamente | Se borra con `docker rm oracle-xe` |
| Configura el sistema operativo anfitrión | Corre completamente aislado |
| Solo funciona en ciertos sistemas operativos | Funciona igual en Windows, Mac y Linux |

### 0.1 Ejecutar el contenedor de Oracle XE

```bash
docker run -d \
  -p 1521:1521 \
  -e ORACLE_PASSWORD=123456 \
  --name oracle-xe \
  gvenzl/oracle-xe
```

En Windows (una sola línea):

```bash
docker run -d -p 1521:1521 -e ORACLE_PASSWORD=123456 --name oracle-xe gvenzl/oracle-xe
```

**Desglose del comando, parte por parte:**

| Fragmento | ¿Qué hace? |
|---|---|
| `docker run` | Crea y arranca un nuevo contenedor |
| `-d` | Modo **detached**: corre en segundo plano, no bloquea la terminal |
| `-p 1521:1521` | **Port mapping**: expone el puerto 1521 del contenedor en el puerto 1521 de tu máquina. Formato: `puerto_local:puerto_contenedor` |
| `-e ORACLE_PASSWORD=123456` | Pasa una **variable de entorno** al contenedor. Oracle XE usará `123456` como contraseña del usuario `system` |
| `--name oracle-xe` | Asigna el nombre `oracle-xe` al contenedor para poder referenciarlo fácilmente |
| `gvenzl/oracle-xe` | Nombre de la **imagen** en Docker Hub: usuario `gvenzl`, imagen `oracle-xe`. Docker la descarga automáticamente si no la tienes |

**¿Por qué el puerto 1521?**  
Es el puerto estándar de Oracle Database (equivalente al `3306` de MySQL o `5432` de PostgreSQL). El driver `oracledb` de Node.js se conecta a este puerto por defecto.

### 0.2 Verificar que el contenedor está corriendo

```bash
docker ps
```

Deberías ver algo como:

```
CONTAINER ID   IMAGE              STATUS          PORTS                    NAMES
a1b2c3d4e5f6   gvenzl/oracle-xe   Up 2 minutes    0.0.0.0:1521->1521/tcp   oracle-xe
```

### 0.3 Ver los logs del contenedor (esperar que arranque)

Oracle XE tarda entre 60 y 90 segundos en inicializarse por primera vez. Puedes seguir los logs en tiempo real:

```bash
docker logs -f oracle-xe
```

Cuando veas la línea:

```
DATABASE IS READY TO USE!
```

la base de datos ya acepta conexiones. Presiona `Ctrl + C` para salir del seguimiento de logs.

### 0.4 Comandos útiles para gestionar el contenedor

```bash
# Detener el contenedor (la BD queda apagada, los datos se conservan)
docker stop oracle-xe

# Volver a arrancar el contenedor (sin perder datos)
docker start oracle-xe

# Ver los logs
docker logs oracle-xe

# Eliminar el contenedor completamente
docker rm -f oracle-xe

# Entrar al contenedor con una terminal interactiva
docker exec -it oracle-xe bash
```

**¿Cuándo se pierden los datos?**  
Al hacer `docker rm`, el contenedor y su contenido se borran. Para persistir los datos entre recreaciones del contenedor, se usa un **volumen Docker** (tema avanzado):

```bash
docker run -d -p 1521:1521 -e ORACLE_PASSWORD=123456 \
  -v oracle-data:/opt/oracle/oradata \
  --name oracle-xe gvenzl/oracle-xe
```

Con `-v oracle-data:/opt/oracle/oradata`, los archivos de la BD se guardan en un volumen gestionado por Docker y sobreviven aunque elimines el contenedor.

### 0.5 Cadena de conexión

Una vez que el contenedor está listo, la cadena de conexión para Node.js es:

```
localhost/XEPDB1
```

- `localhost` → Oracle corre en tu propia máquina (gracias al `-p 1521:1521`)
- `XEPDB1` → nombre del **Pluggable Database** (PDB) que crea Oracle XE por defecto

Esta es la misma cadena que se usa en el archivo `.env`:

```
DB_CONN=localhost/XEPDB1
```

---

## Paso 1 — Crear el proyecto Node.js

### 1.1 Inicializar el proyecto

```bash
mkdir msp-backend
cd msp-backend
npm init -y
```

**¿Por qué `npm init -y`?**  
Crea el archivo `package.json` automáticamente sin hacer preguntas (`-y` acepta todo por defecto). Este archivo es el "pasaporte" del proyecto: lista su nombre, versión y todas las dependencias que necesita.

### 1.2 Instalar dependencias

```bash
npm install express cors helmet dotenv oracledb express-validator winston
npm install --save-dev nodemon
```

| Paquete | ¿Para qué sirve? |
|---|---|
| `express` | Crear el servidor y definir rutas |
| `cors` | Permitir que otros dominios (p. ej. un frontend) consuman nuestra API |
| `helmet` | Añadir cabeceras HTTP de seguridad automáticamente |
| `dotenv` | Leer las credenciales de la BD desde un archivo `.env` en vez de escribirlas en el código |
| `oracledb` | Driver oficial de Oracle para Node.js |
| `express-validator` | Validar y sanear datos del `req.body` |
| `winston` | Sistema de logging profesional (guarda logs en archivos) |
| `nodemon` | Reinicia el servidor automáticamente cada vez que guardas un archivo (solo en desarrollo) |

**¿Por qué separar `--save-dev`?**  
`nodemon` solo se necesita mientras desarrollas, no en producción. `--save-dev` lo guarda en `devDependencies` para dejar claro que es una herramienta de desarrollo, no parte del producto final.

### 1.3 Ajustar `package.json`

Abre `package.json` y agrega la sección `"scripts"` y `"type"`:

```json
{
  "name": "msp-backend",
  "version": "1.0.0",
  "type": "commonjs",
  "scripts": {
    "dev": "nodemon src/app.js",
    "start": "node src/app.js"
  },
  "dependencies": { ... },
  "devDependencies": { ... }
}
```

**¿Por qué `"type": "commonjs"`?**  
Node.js soporta dos sistemas de módulos: CommonJS (el clásico `require()`) y ESModules (`import/export`). Al poner `"commonjs"` declaramos explícitamente que usamos `require()`, evitando errores de compatibilidad.

**¿Por qué dos scripts (`dev` y `start`)?**  
- `npm run dev` → arranca con `nodemon` (recarga automática, ideal para desarrollar)
- `npm start` → arranca con `node` puro (para producción o pruebas finales)

---

## Paso 2 — Variables de entorno

### 2.1 Crear el archivo `.env`

En la raíz del proyecto, crea el archivo `.env`:

```
DB_USER=system
DB_PASS=123456
DB_CONN=localhost/XEPDB1
```

**¿Por qué un archivo `.env` y no escribir los datos directamente en el código?**  
- Si subes el código a GitHub con la contraseña escrita, cualquiera puede verla.
- Con `.env` separas la configuración del código. En producción usas otras credenciales sin tocar el código.

### 2.2 Crear `.gitignore`

```
node_modules/
.env
logs/
```

**¿Por qué?**  
- `node_modules/` pesa cientos de MB; se regenera con `npm install`.
- `.env` contiene secretos que no deben versionarse.
- `logs/` son archivos generados automáticamente.

---

## Paso 3 — Estructura de carpetas

```
msp-backend/
├── src/
│   ├── app.js                        ← Punto de entrada del servidor
│   ├── config/
│   │   └── db.js                     ← Conexión a Oracle
│   ├── routes/
│   │   └── user.routes.js            ← Define las URLs disponibles
│   ├── controllers/
│   │   └── user.controllers.js       ← Maneja request y response
│   ├── services/
│   │   └── user.service.js           ← Lógica de negocio y queries SQL
│   ├── middlewares/
│   │   ├── error.middleware.js       ← Manejo centralizado de errores
│   │   ├── validate.js               ← Ejecuta las validaciones
│   │   └── user.validator.js         ← Reglas de validación del usuario
│   └── utils/
│       └── logger.js                 ← Configuración de Winston (logs)
├── init-db.js                        ← Script para crear la tabla en Oracle
├── .env                              ← Variables de entorno (no subir a git)
└── package.json
```

**¿Por qué esta separación en capas?**  
Cada carpeta tiene **una sola responsabilidad**. Esto sigue el principio **SRP (Single Responsibility Principle)**:

- Si cambia la base de datos, solo tocas `services/` y `config/`.
- Si cambia una validación, solo tocas `middlewares/`.
- Si el código crece, es fácil encontrar y modificar cada parte sin romper las demás.

---

## Paso 4 — Configurar la conexión a Oracle

### `src/config/db.js`

```js
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
        console.log('✅ Oracle conectado');
    } catch (err) {
        console.error(err);
    }
}

async function getConnection() {
    return await oracledb.getConnection();
}

module.exports = { initDB, getConnection };
```

**¿Por qué un pool de conexiones y no conectarse cada vez?**  
Abrir una conexión a la base de datos es una operación lenta. Un **pool** mantiene varias conexiones abiertas y listas para usarse. Cuando llega una petición, toma una del pool (rápido), la usa y la devuelve. Esto mejora drásticamente el rendimiento bajo carga.

- `poolMin: 1` → siempre hay al menos 1 conexión activa.
- `poolMax: 5` → máximo 5 conexiones simultáneas.

**¿Por qué `require('dotenv').config()` aquí?**  
Para que las variables `process.env.DB_USER`, etc., estén disponibles en el momento en que este módulo se carga.

---

## Paso 5 — Crear la tabla en Oracle

### `init-db.js` (en la raíz)

```js
const oracledb = require('oracledb');

async function init() {
    let conn;
    try {
        conn = await oracledb.getConnection({
            user: 'system',
            password: '123456',
            connectString: 'localhost/XEPDB1'
        });
        console.log('✅ Conectado');

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
        console.log('✅ Tabla creada');
    } catch (err) {
        console.error(err);
    } finally {
        if (conn) await conn.close();
    }
}

init();
```

Ejecuta este script **una sola vez**:

```bash
node init-db.js
```

**¿Por qué el bloque `BEGIN...EXCEPTION`?**  
Oracle lanza el error `ORA-00955` si la tabla ya existe. El bloque PL/SQL captura ese error específico (`SQLCODE = -955`) y lo ignora, así puedes ejecutar el script varias veces sin que falle.

**¿Por qué `GENERATED ALWAYS AS IDENTITY`?**  
Es el equivalente Oracle a `AUTO_INCREMENT` de MySQL. El campo `id` se incrementa automáticamente con cada inserción, sin que tengas que indicarlo manualmente.

---

## Paso 6 — Capa de Servicio (lógica de negocio y SQL)

### `src/services/user.service.js`

```js
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
```

**¿Por qué `:id`, `:name`, `:email` en vez de concatenar directamente?**  
Esto se llama **parámetros bind** (consultas parametrizadas). Previene ataques de **SQL Injection**, donde un atacante manipula el SQL enviando datos maliciosos. Ejemplo de lo que se evita:

```
// ❌ PELIGROSO (concatenación directa)
`SELECT * FROM users WHERE id = ${req.params.id}`
// Si id = "1 OR 1=1", devuelve TODOS los registros

// ✅ SEGURO (bind parameters)
`SELECT * FROM users WHERE id = :id`, { id: req.params.id }
// Oracle trata el valor como dato, nunca como código SQL
```

**¿Por qué `autoCommit: true`?**  
Oracle por defecto no hace `COMMIT` automático. Sin esta opción, los cambios (`INSERT`, `UPDATE`, `DELETE`) quedan en una transacción pendiente y se pierden si la conexión se cierra. Con `autoCommit: true` se confirman inmediatamente.

---

## Paso 7 — Logger (registro de eventos)

### `src/utils/logger.js`

```js
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
```

**¿Por qué usar Winston y no simplemente `console.log`?**  
`console.log` solo imprime en pantalla y desaparece. Winston:
- Guarda los logs en **archivos** persistentes.
- Distingue niveles: `info`, `warn`, `error`.
- Añade **timestamps** automáticos.
- En producción, puedes desactivar los logs de consola sin cambiar el código.

**¿Qué genera este logger?**  
```
2026-03-22T10:15:30.123Z [ERROR]: DELETE /api/users/99 - Usuario no existe
```

---

## Paso 8 — Middlewares

Un **middleware** es una función con la firma `(req, res, next)`. Se ejecuta en el pipeline de Express antes de llegar al controlador final. Si llama a `next()`, pasa al siguiente middleware. Si hace `res.json()`, termina el ciclo.

```
Petición HTTP → middleware1 → middleware2 → controlador → respuesta
```

### 8.1 Validador de reglas — `src/middlewares/user.validator.js`

```js
const { body } = require('express-validator');

exports.createUserValidator = [
    body('name')
        .notEmpty().withMessage('Nombre requerido')
        .isLength({ min: 3 }).withMessage('Mínimo 3 caracteres'),

    body('email')
        .isEmail().withMessage('Email inválido')
];
```

**¿Por qué validar aquí y no en el servicio?**  
La validación de **formato** (¿es un email válido? ¿tiene al menos 3 caracteres?) pertenece a la capa HTTP, no a la lógica de negocio. Si el dato es inválido, rechazamos la petición **antes** de llegar a la base de datos, ahorrando recursos.

### 8.2 Ejecutor de validaciones — `src/middlewares/validate.js`

```js
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
```

**¿Por qué dos archivos separados (validator + validate)?**  
- `user.validator.js` define **qué** validar (las reglas específicas del usuario).
- `validate.js` define **cómo** responder cuando hay errores (lógica genérica, reutilizable en cualquier ruta).

Así, si mañana creas un módulo `product`, reutilizas `validate.js` y solo creas `product.validator.js` con sus propias reglas.

### 8.3 Manejador de errores — `src/middlewares/error.middleware.js`

```js
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
        message = 'Violación de clave foránea';
        status = 400;
    }

    logger.error(`${req.method} ${req.url} - ${message}`);

    res.status(status).json({
        success: false,
        message
    });
}

module.exports = errorHandler;
```

**¿Por qué tiene 4 parámetros `(err, req, res, next)`?**  
Express identifica un middleware de errores **exactamente** por tener 4 parámetros. Si tiene 3, no lo trata como manejador de errores. Este es el contrato de Express.

**¿Por qué centralizar el manejo de errores?**  
Sin esto, cada controlador necesitaría su propio `try/catch` con su propio `res.status(500)...`. Con un handler centralizado, los controladores solo hacen `next(err)` y este middleware se encarga de todo: loggear, traducir errores de Oracle y responder con un formato consistente.

---

## Paso 9 — Controladores

### `src/controllers/user.controllers.js`

```js
const service = require('../services/user.service');

exports.getAll = async (req, res, next) => {
    try {
        const data = await service.getAll();
        res.json(data);
    } catch (err) {
        next(err);  // ← pasa el error al middleware de errores
    }
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
    } catch (err) {
        next(err);
    }
};

exports.create = async (req, res, next) => {
    try {
        await service.create(req.body);
        res.status(201).json({ message: 'Creado' });
    } catch (err) {
        next(err);
    }
};

exports.update = async (req, res, next) => {
    try {
        await service.update(req.params.id, req.body);
        res.json({ message: 'Actualizado' });
    } catch (err) {
        next(err);
    }
};

exports.delete = async (req, res, next) => {
    try {
        await service.remove(req.params.id);
        res.json({ message: 'Eliminado' });
    } catch (err) {
        next(err);
    }
};
```

**¿Por qué `next(err)` en lugar de `res.status(500).json(...)`?**  
Al llamar `next(err)`, delegamos el manejo al `errorHandler` del paso 8.3. Esto garantiza que **todos** los errores del sistema siguen el mismo camino: se loggean con Winston y responden con el mismo formato JSON. La consistencia es clave para que el frontend sepa siempre cómo interpretar un error.

**¿Por qué `res.status(201)` al crear?**  
El código HTTP `201 Created` es semánticamente correcto para indicar que un recurso fue creado exitosamente. Usar `200 OK` para una creación es técnicamente incorrecto aunque funcione.

---

## Paso 10 — Rutas

### `src/routes/user.routes.js`

```js
const router = require('express').Router();
const c = require('../controllers/user.controllers');
const validate = require('../middlewares/validate');
const { createUserValidator } = require('../middlewares/user.validator');

router.get('/', c.getAll);
router.get('/:id', c.getOne);

router.post(
    '/',
    createUserValidator,  // 1. aplica las reglas de validación
    validate,             // 2. si hay errores → responde 400, si no → next()
    c.create              // 3. solo llega aquí si los datos son válidos
);

router.put('/:id', c.update);
router.delete('/:id', c.delete);

module.exports = router;
```

**¿Por qué el orden `createUserValidator → validate → c.create` importa?**  
Express ejecuta los middlewares **en orden**. Si `validate` va antes de `createUserValidator`, intentaría verificar errores que aún no se calcularon. El orden correcto es: primero colectar los errores, luego evaluarlos, y solo si todo está bien, ejecutar el controlador.

**¿Por qué `/:id` y no `/user/:id`?**  
El prefijo `/api/users` ya se define en `app.js`. Las rutas aquí son **relativas** a ese prefijo, así que `/:id` resulta en `/api/users/:id`.

---

## Paso 11 — Punto de entrada: el servidor

### `src/app.js`

```js
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');

const { initDB } = require('./config/db');
const userRoutes = require('./routes/user.routes');
const errorHandler = require('./middlewares/error.middleware');

const app = express();

// Middlewares globales
app.use(cors());
app.use(helmet());
app.use(express.json());

// Rutas
app.use('/api/users', userRoutes);

// Inicializar pool de conexiones
initDB();

// Servidor
app.listen(3000, () => {
    console.log('Servidor en 3000');
});

// Manejador de errores (SIEMPRE al final)
app.use(errorHandler);
```

**¿Por qué `app.use(express.json())`?**  
Por defecto, Express no sabe leer el body de una petición POST/PUT. Este middleware parsea el `Content-Type: application/json` y lo pone disponible en `req.body`.

**¿Por qué `cors()`?**  
Los navegadores bloquean por seguridad las peticiones a dominios distintos al del sitio web (política CORS). Al activar este middleware, el servidor declara qué orígenes tienen permiso para consumir la API.

**¿Por qué `helmet()`?**  
Helmet agrega automáticamente varias cabeceras HTTP de seguridad que protegen contra ataques comunes como clickjacking, sniffing de tipo MIME, etc. Es una buena práctica activarlo en todo servidor Express.

**¿Por qué `errorHandler` va AL FINAL?**  
Express procesa los middlewares en orden de registro. Si el `errorHandler` estuviera antes de las rutas, nunca capturaría errores de las rutas (aún no registradas). Debe ser el **último** `app.use()` para capturar cualquier error que burbujee desde las rutas.

---

## Flujo completo de una petición

Así viaja un `POST /api/users` con `{ "name": "Ana", "email": "ana@mail.com" }`:

```
Cliente HTTP
    │
    ▼
app.use(cors())          → añade cabeceras CORS
app.use(helmet())        → añade cabeceras de seguridad
app.use(express.json())  → parsea el body JSON → req.body = { name, email }
    │
    ▼
app.use('/api/users', userRoutes)
    │
    ▼
router.post('/', createUserValidator, validate, c.create)
    │
    ├── createUserValidator  → evalúa reglas sobre req.body
    ├── validate             → ¿hay errores? → NO → next()
    └── c.create(req, res, next)
            │
            ▼
        service.create(req.body)
            │
            ▼
        INSERT INTO users... (Oracle)
            │
            ▼
        res.status(201).json({ message: 'Creado' })
            │
            ▼
        ← Respuesta al cliente
```

Si en algún paso ocurre un error:
```
c.create → catch(err) → next(err) → errorHandler → logger.error() → res.status(500).json(...)
```

---

## Paso 12 — Ejecutar y probar

### Iniciar el servidor en modo desarrollo

```bash
npm run dev
```

Deberías ver:
```
Servidor en 3000
✅ Oracle conectado
```

### Endpoints disponibles

| Método | URL | Descripción |
|---|---|---|
| `GET` | `/api/users` | Obtener todos los usuarios |
| `GET` | `/api/users/:id` | Obtener un usuario por ID |
| `POST` | `/api/users` | Crear un usuario |
| `PUT` | `/api/users/:id` | Actualizar un usuario |
| `DELETE` | `/api/users/:id` | Eliminar un usuario |

### Ejemplos con Postman / Thunder Client

**Crear usuario** — `POST /api/users`
```json
// Body (JSON):
{
    "name": "Ana García",
    "email": "ana@ejemplo.com"
}

// Respuesta esperada (201):
{ "message": "Creado" }
```

**Crear con datos inválidos** — `POST /api/users`
```json
// Body:
{ "name": "AB", "email": "no-es-email" }

// Respuesta esperada (400):
{
  "success": false,
  "errors": [
    { "msg": "Mínimo 3 caracteres", "path": "name" },
    { "msg": "Email inválido", "path": "email" }
  ]
}
```

**Obtener uno** — `GET /api/users/1`
```json
// Respuesta (200):
[1, "Ana García", "ana@ejemplo.com"]
```

**Actualizar** — `PUT /api/users/1`
```json
// Body:
{ "name": "Ana López", "email": "ana.lopez@ejemplo.com" }
// Respuesta: { "message": "Actualizado" }
```

**Eliminar** — `DELETE /api/users/1`
```json
// Respuesta: { "message": "Eliminado" }
```

---

## Resumen de la arquitectura

```
┌─────────────┐     HTTP     ┌──────────────────────────────────────┐
│   Cliente   │ ──────────► │              Express App              │
│ (Postman /  │             │                                        │
│  Frontend)  │             │  Middlewares globales                 │
└─────────────┘             │   cors / helmet / json                │
                            │                                        │
                            │  ┌─────────────────────────────────┐  │
                            │  │            Rutas                │  │
                            │  │  /api/users → user.routes.js    │  │
                            │  └──────────────┬──────────────────┘  │
                            │                 │                      │
                            │  ┌──────────────▼──────────────────┐  │
                            │  │         Middlewares             │  │
                            │  │  validator → validate           │  │
                            │  └──────────────┬──────────────────┘  │
                            │                 │                      │
                            │  ┌──────────────▼──────────────────┐  │
                            │  │         Controlador             │  │
                            │  │      user.controllers.js        │  │
                            │  └──────────────┬──────────────────┘  │
                            │                 │                      │
                            │  ┌──────────────▼──────────────────┐  │
                            │  │           Servicio              │  │
                            │  │       user.service.js           │  │
                            │  └──────────────┬──────────────────┘  │
                            │                 │                      │
                            │  ┌──────────────▼──────────────────┐  │
                            │  │        Base de Datos            │  │
                            │  │     Oracle XE (oracledb)        │  │
                            │  └─────────────────────────────────┘  │
                            │                                        │
                            │  Error Handler (último middleware)     │
                            │  Winston Logger → logs/               │
                            └──────────────────────────────────────┘
```

---

## Errores comunes y cómo resolverlos

| Error | Causa | Solución |
|---|---|---|
| `MODULE_NOT_FOUND` | El `require()` apunta a un archivo que no existe | Verifica que el nombre del archivo y la ruta sean exactos (incluyendo la `s` en `controllers`) |
| `ORA-12541: TNS:no listener` | Oracle no está corriendo | Inicia el servicio de Oracle Database |
| `ORA-01017: invalid username/password` | Credenciales incorrectas en `.env` | Verifica `DB_USER` y `DB_PASS` |
| `Cannot read properties of undefined (req.body)` | Falta `app.use(express.json())` | Asegúrate de que ese middleware esté antes de las rutas |
| Cambios en código no se reflejan | Servidor no se reinició | Usa `npm run dev` con nodemon |

---

## Bonus — Script de instalación automática

Todo lo que se explica en esta guía está automatizado en el archivo `setup.ps1`. Con un solo comando crea la carpeta del proyecto, instala dependencias, genera todos los archivos y levanta Oracle XE en Docker.

### ¿Cómo usarlo?

**Opción 1 — Proyecto con nombre por defecto (`msp-backend`):**
```powershell
.\setup.ps1
```

**Opción 2 — Con un nombre personalizado:**
```powershell
.\setup.ps1 -NombreProyecto "mi-api-usuarios"
```

**Opción 3 — Sin Docker (si ya tienes Oracle corriendo):**
```powershell
.\setup.ps1 -SkipDocker
```

### Primera vez que ejecutas scripts en PowerShell

Windows bloquea por seguridad la ejecución de scripts `.ps1` por defecto. Si ves el error `"no se puede cargar el archivo ... no está firmado digitalmente"`, ejecuta primero:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

**¿Qué significa?**  
- `RemoteSigned` permite ejecutar scripts locales sin firmar, pero exige firma digital a los descargados de Internet.
- `-Scope CurrentUser` aplica el cambio solo a tu usuario, sin afectar al resto del sistema.

### ¿Qué hace el script paso a paso?

| Fase | Qué hace |
|---|---|
| **Verificación** | Comprueba que `node`, `npm` y `docker` estén instalados |
| **Carpeta** | Crea el directorio del proyecto y entra en él |
| **npm init** | Ejecuta `npm init -y` y configura `scripts` y `"type": "commonjs"` en `package.json` |
| **Dependencias** | Instala todos los paquetes de producción y `nodemon` como dev |
| **Estructura** | Crea todas las subcarpetas (`config`, `controllers`, `services`, etc.) |
| **Archivos** | Genera cada archivo `.js`, `.env` y `.gitignore` con su contenido completo |
| **Docker** | Comprueba si el contenedor ya existe; si no, lanza `docker run` para Oracle XE |
| **Resumen** | Muestra la estructura creada y los próximos pasos a seguir |

### Después de ejecutar el script

```powershell
# 1. Seguir los logs de Oracle hasta ver "DATABASE IS READY TO USE!"
docker logs -f oracle-xe

# 2. Crear la tabla (solo una vez)
node init-db.js

# 3. Arrancar el servidor
npm run dev
```

---

## Buenas prácticas aplicadas en este proyecto

- **Variables de entorno** para secretos (nunca hardcodear contraseñas).
- **Arquitectura en capas** (routes → controllers → services → db) para separar responsabilidades.
- **Consultas parametrizadas** para prevenir SQL Injection.
- **Validación en capa HTTP** para rechazar datos inválidos antes de llegar a la BD.
- **Error handler centralizado** para respuestas de error consistentes y logging automático.
- **Pool de conexiones** para rendimiento bajo carga.
- **Logging con Winston** para tener trazabilidad de errores en producción.
- **Helmet** para cabeceras de seguridad HTTP sin esfuerzo.
