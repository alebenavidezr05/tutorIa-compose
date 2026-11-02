# TutorIA

TutorIA es un tutor académico con IA para estudiantes de habla hispana: diagnostica el nivel,
arma un plan de estudio y conversa con el estudiante a través del tutor **Vex** (Claude), con
fuentes verificables, recursos visuales con licencia abierta, autorización parental para menores
y cifrado de datos personales conforme a la Ley 1581 de 2012 (Colombia).

El proyecto vive en tres repositorios públicos:

| Repositorio | Contenido |
|---|---|
| `tutorIa-backend` | API FastAPI + agente tutor, `Dockerfile`, CI del backend |
| `tutorIa-frontend` | SPA Angular, `Dockerfile` + `Caddyfile`, CI del frontend |
| `tutorIa-compose` (este) | `docker-compose.yml`, despliegue en AWS (`deploy/`), CI de integración y este README |

![Identidad visual](docs/brand/identidad-visual.png)

## Contenido

1. [Arquitectura](#1-arquitectura)
2. [Requisitos por ruta](#2-requisitos-por-ruta)
3. [Ruta A — Con Docker (recomendada)](#3-ruta-a--con-docker-recomendada)
4. [Ruta B — Local sin Docker](#4-ruta-b--local-sin-docker)
5. [Primer recorrido de prueba](#5-primer-recorrido-de-prueba)
6. [Conectar los proveedores de IA](#6-conectar-los-proveedores-de-ia)
7. [Protección de datos (Ley 1581 de 2012)](#7-protección-de-datos-ley-1581-de-2012)
8. [Datos personales, menores y cifrado](#8-datos-personales-menores-y-cifrado)
9. [Consumo y costos de IA](#9-consumo-y-costos-de-ia)
10. [Ruta D — Despliegue en AWS (EC2 bajo demanda)](#10-ruta-d--despliegue-en-aws-ec2-bajo-demanda)
11. [Ruta C — AWS administrado (opcional)](#11-ruta-c--aws-administrado-opcional)
12. [Pruebas y calidad](#12-pruebas-y-calidad)
13. [Solución de problemas](#13-solución-de-problemas)
14. [Estructura, convenciones y hoja de ruta](#14-estructura-convenciones-y-hoja-de-ruta)

---

## 1. Arquitectura

### 1.1 Las tres redes (igual en local y en producción)

```
                    publica puertos
Navegador ──────────────▶ frontend (Caddy: SPA + proxy /api + HTTPS)
                              │ redes: web + interna
                              ▼
                          backend (FastAPI + agente tutor)
                              │ redes: interna + salida
                 ┌────────────┴─────────────┐
                 ▼                          ▼
        db (PostgreSQL)              HTTPS saliente: Anthropic, OpenAI, proveedores de
        red: interna                 fuentes e imágenes abiertas, YouTube (opcional),
        SIN salida a internet        AWS (KMS, S3, SES). Solo el backend sale.
```

| Red | Tipo | Quién | Para qué |
|---|---|---|---|
| `interna` | `internal: true` (sin internet) | db, backend, frontend | Comunicación entre contenedores |
| `salida` | normal | solo backend | Única salida a internet del sistema |
| `web` | normal | solo frontend | Publicar 80/443 y que Caddy pida su certificado |

- La base de datos no publica puertos ni tiene salida. El backend no publica puertos. El único
  puerto publicado es el del frontend.
- Caddy necesita salida hacia Let's Encrypt para el certificado; no procesa datos: sirve archivos
  estáticos y reenvía `/api/`.
- Restringir la salida del backend a una lista de dominios requiere un proxy de salida (hoja de
  ruta). Mientras tanto, la descarga de imágenes ya filtra dominios en la aplicación.
- En local todo es falso por defecto (`LLM_PROVIDER=fake`, `CORREO_PROVEEDOR=fake`,
  `CIFRADO_PROVEEDOR=local`, `ALMACEN_PROVEEDOR=local`, `MODERACION_PROVEEDOR=fake`, fuentes,
  imágenes y pasarela simuladas): arranca sin llaves, sin AWS y sin red externa.

### 1.2 Producción: EC2 bajo demanda (Ruta D)

```
                  ┌────────────── Lambda "despertador" (Function URL) ───────────────┐
 Entrada ───────▶ │ página "Encendiendo TutorIA…": si la EC2 está detenida la enciende │
 (enlace de       │ y, cuando responde, redirige a la app conservando ruta y #fragmento │
 correo/favorito) └──────────────────────────────┬───────────────────────────────────┘
                                                 │ ec2:StartInstances / DescribeInstances
                                                 ▼
Navegador ──HTTPS 443──▶ EC2 Ubuntu 24.04 (Elastic IP, dominio propio, EBS cifrado con KMS)
                           └ Docker Compose: frontend (Caddy) · backend · db   (§1.1)
                              │ rol IAM de la instancia (sin llaves estáticas)
                              ├─▶ KMS  (DEK de cifrado de columnas)
                              ├─▶ S3   (archivos de estudiantes con expiración · respaldos)
                              ├─▶ SES  (correos de autorización a acudientes)
                              └─▶ SSM  (Session Manager: sin puerto 22)
cron cada 5 min ─▶ "¿hubo uso en los últimos 30 min?" ─ no ─▶ limpieza + respaldo a S3 + apagado
```

| Conexión | Protocolo | Regla |
|---|---|---|
| Navegador → Caddy | HTTPS 443 (80 redirige) | Let's Encrypt automático; cabeceras de seguridad y CSP |
| Caddy → backend | HTTP, red interna, 8000 | `response_header_timeout 120s` |
| Backend → db | TCP 5432, red interna | Sin TLS (red sin salida); la base no publica puertos |
| Backend → KMS / S3 / SES | HTTPS, rol de la instancia | Permisos mínimos (`deploy/iam/`) |
| Backend → Anthropic / OpenAI / fuentes / imágenes / YouTube | HTTPS por `salida` | Solo el backend |
| Navegador → youtube-nocookie.com | HTTPS | Único tercero del CSP (`frame-src`), solo tras un clic |
| Navegador → Lambda despertador | HTTPS | Solo cuando la instancia está apagada; no toca datos |

---

## 2. Requisitos por ruta

| Ruta | Necesitas |
|---|---|
| **A. Docker** (recomendada, igual en los tres sistemas) | Docker Desktop (Windows con WSL 2; macOS Intel/Apple Silicon) o Docker Engine + plugin Compose (Linux), Git |
| **B. Local** (desarrollo) | Python 3.11, Node.js LTS (22.22.3+ o 24.15+), PostgreSQL 16, Git |
| **D. AWS: EC2 bajo demanda** (producción) | Cuenta de AWS, AWS CLI v2 + plugin de Session Manager, un dominio o subdominio propio, cuentas de Anthropic y OpenAI |
| C. AWS administrado (opcional) | Lo de D más Terraform (no generado; ver §11) |

---

## 3. Ruta A — Con Docker (recomendada)

### 3.1 Traer los tres repositorios

**Linux / macOS / Git Bash**

```bash
git clone https://github.com/alebenavidezr05/tutorIa-compose.git
cd tutorIa-compose
bash deploy/clonar.sh
```

**Windows (PowerShell)** — sin bash, clona a mano:

```powershell
git clone https://github.com/alebenavidezr05/tutorIa-compose.git
cd tutorIa-compose
git clone https://github.com/alebenavidezr05/tutorIa-backend.git backend
git clone https://github.com/alebenavidezr05/tutorIa-frontend.git frontend
```

> ¿Ya tienes los tres repositorios como carpetas hermanas (`tutorIa-backend`, `tutorIa-frontend`
> y `tutorIa-compose` en la misma carpeta)? No los muevas: en el `.env` pon
> `BACKEND_DIR=../tutorIa-backend` y `FRONTEND_DIR=../tutorIa-frontend`.

> En Windows, clona dentro de WSL 2 (`\\wsl$\...`) si Docker va lento. Los `.gitattributes`
> fuerzan LF; si clonaste antes de que existieran, vuelve a clonar.

### 3.2 Configurar

| Sistema | Copiar el `.env` |
|---|---|
| Linux/macOS | `cp .env.example .env` |
| PowerShell | `Copy-Item .env.example .env` |
| cmd | `copy .env.example .env` |

Edita `.env` y cambia al menos `POSTGRES_PASSWORD`, `JWT_SECRET` e `INDICE_CIEGO_CLAVE`:

| Sistema | Generar un secreto |
|---|---|
| Linux/macOS | `openssl rand -hex 32` |
| PowerShell | `[Convert]::ToHexString((1..32 \| ForEach-Object { Get-Random -Maximum 256 }))` |
| Cualquiera con Python | `python -c "import secrets; print(secrets.token_hex(32))"` |

`POSTGRES_PASSWORD` va dentro de una URL: no uses `@ : / ? # %` (el hexadecimal es seguro).

> `docker compose config` imprime los valores del `.env`, secretos incluidos. No pegues su salida en ningún lado.

### 3.3 Arrancar, ver logs, detener

```bash
docker compose up --build          # primera vez (tarda: compila Angular)
# abre http://localhost:8080
docker compose up -d               # en segundo plano
docker compose logs -f backend     # logs (también: frontend, db)
docker compose ps                  # estado y healthchecks
docker compose stop                # detener (conserva datos)
docker compose down                # detener y borrar contenedores (conserva volúmenes)
docker compose down -v             # BORRA TODOS LOS DATOS (base de datos y archivos)
```

### 3.4 Modo desarrollo (recarga en caliente)

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build
```

Publica PostgreSQL en `127.0.0.1:5432` y la API en `127.0.0.1:8000` (con `/docs`), monta
`backend/app` y recarga al guardar. Puedes correr además `npm start` en `frontend/`
(http://localhost:4200). Es el único modo que expone la base, y solo en tu equipo.

### 3.5 Comprobar el aislamiento de red

```bash
docker compose exec db wget -T 3 -qO- https://example.com
# debe FALLAR (la base no tiene salida a internet)
docker compose exec backend python -c "import urllib.request as u;print(u.urlopen('https://example.com',timeout=5).status)"
# debe imprimir 200
docker compose ps
# solo frontend muestra puertos publicados (127.0.0.1:8080->80, 127.0.0.1:8443->443)
```

### 3.6 Base de datos y cambios de modelo

- Las tablas las crea el backend al arrancar (`create_all` bajo `pg_advisory_lock`).
- `create_all` **no modifica tablas existentes**. Tras cambiar un modelo en desarrollo:
  `docker compose exec backend python -m app.scripts.reiniciar_tablas` (borra los datos) o
  `docker compose down -v`. En producción un cambio de esquema requiere migración (Alembic,
  hoja de ruta) y un respaldo previo.
- Pool: `DB_POOL_SIZE` (5) + `DB_MAX_OVERFLOW` (10) = 15 conexiones como máximo con un solo
  contenedor de backend, por debajo de `max_connections` = 100 de PostgreSQL. Si agregas réplicas
  o subes esos valores, mantén `réplicas × (pool + overflow) + scripts < 100`.

---

## 4. Ruta B — Local sin Docker

### 4.1 Instalar herramientas

**Windows (PowerShell)**

```powershell
winget install Python.Python.3.11
winget install OpenJS.NodeJS.LTS
winget install PostgreSQL.PostgreSQL.16
winget install Git.Git
# Abre una terminal NUEVA para refrescar el PATH.
```

**Linux (Ubuntu/Debian)**

```bash
sudo apt update && sudo apt install -y python3.11 python3.11-venv postgresql git
# Si python3.11 no existe en tu versión:
#   sudo add-apt-repository ppa:deadsnakes/ppa && sudo apt update && sudo apt install -y python3.11 python3.11-venv
# Node con nvm (consulta la versión vigente del instalador en https://github.com/nvm-sh/nvm):
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
source ~/.nvm/nvm.sh && nvm install --lts
```

Otras distribuciones: `sudo dnf install python3.11 postgresql-server nodejs git` (Fedora) ·
`sudo pacman -S python postgresql nodejs npm git` (Arch).

**macOS (Homebrew)**

```bash
brew install python@3.11 node postgresql@16 git
brew services start postgresql@16
```

### 4.2 Crear la base de datos

Abre `psql`:

| Sistema | Comando |
|---|---|
| Windows | `& "C:\Program Files\PostgreSQL\16\bin\psql.exe" -U postgres` (o "SQL Shell (psql)") |
| Linux | `sudo -u postgres psql` |
| macOS | `psql postgres` |

Y ejecuta (las mismas sentencias en los tres):

```sql
CREATE USER tutoria WITH PASSWORD 'cambia-esto';
CREATE DATABASE tutoria OWNER tutoria;
\q
```

### 4.3 Backend

**Windows (PowerShell)**

```powershell
cd backend
py -3.11 -m venv .venv
.venv\Scripts\Activate.ps1
# Si está bloqueado: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
# En cmd: .venv\Scripts\activate.bat
```

**Linux / macOS**

```bash
cd backend
python3.11 -m venv .venv
source .venv/bin/activate
```

**En los tres:**

```bash
pip install --upgrade pip
pip install -r requirements-dev.txt
cp .env.example .env            # PowerShell: Copy-Item .env.example .env
```

En `backend/.env` ajusta `DATABASE_URL=postgresql+psycopg://tutoria:cambia-esto@localhost:5432/tutoria`
y, para trabajar sin red, borra las líneas `FUENTES_PROVEEDORES` e `IMAGENES_PROVEEDORES` (así se
usan los proveedores simulados). Luego:

```bash
uvicorn app.main:app --reload --port 8000
```

Verifica en http://localhost:8000/docs.

**Dependencias:** `requirements.txt` es lo que va a producción (y a la imagen Docker);
`requirements-dev.txt` lo incluye y añade pytest, ruff, mypy y moto. `tzdata` solo se instala en
Windows (marcador de entorno), porque Linux y macOS traen la base de zonas horarias del sistema.

### 4.4 Frontend

```bash
cd frontend
npm ci
npm start
```

Abre http://localhost:4200. El proxy de desarrollo (`proxy.conf.json`) reenvía `/api` a
`http://localhost:8000`, así que front y API comparten origen y la cookie de sesión funciona.

---

## 5. Primer recorrido de prueba

Con `LLM_PROVIDER=fake` y todo en simulado:

1. Regístrate como **mayor de edad** → elige un tema → responde el diagnóstico → revisa el plan.
2. Conversa con el tutor. Las palabras de prueba **"video"**, **"imagen"** y **"futbol"**
   disparan cada comportamiento (video, recurso visual y desvío fuera del ámbito académico).
3. Termina la sesión y revisa las referencias → abre "Cómo aprendo".
4. Regístrate como **menor**: la cuenta queda pendiente. Abre `/autorizacion` como acudiente y
   completa el formulario. Con `CORREO_PROVEEDOR=fake`, el enlace de confirmación aparece en los
   logs del backend (solo en desarrollo):

   ```bash
   docker compose logs backend | grep -i autoriz
   ```

   Ábrelo en el navegador para confirmar la autorización.
5. Con el nivel **Avanzado**, sube un archivo (PDF, imagen o texto de hasta 5 MB).

---

## 6. Conectar los proveedores de IA

| Proveedor | Qué necesitas | Qué hace el proyecto |
|---|---|---|
| **Anthropic (Claude)** | Cuenta de API comercial, llave, condiciones comerciales aceptadas, modelos habilitados, límite de gasto | Aviso visible de que es una IA y de su precisión, solo ámbito académico, `probar_llm` |
| **OpenAI** | Cuenta con facturación, llave de proyecto, límite de gasto, verificación de organización si el modelo de imágenes la pide | Moderación (gratuita) de entradas y archivos; imágenes solo como último recurso, calidad baja, `safety_identifier`; consentimiento parental para menores de 18 y edad mínima de 13 |
| **YouTube** | Llave de API solo si `VIDEOS_BUSQUEDA_DINAMICA=true` (cuota diaria baja) | Incrustación nocookie, sin autoplay, metadatos < 30 días, canales de confianza |
| **AWS** | Cuenta, dominio, SES fuera del sandbox | §10 |

### Activar el modo real

1. En la consola de cada proveedor crea la llave y configura **límite de gasto y presupuesto mensual**.
2. En `.env`: `LLM_PROVIDER=anthropic`, `LLM_API_KEY=...`, `MODERACION_PROVEEDOR=openai`,
   `OPENAI_API_KEY=...`. Verifica los identificadores `LLM_MODEL_SENCILLO` / `LLM_MODEL_COMPLEJO`
   en la documentación de Anthropic (cambian con el tiempo).
3. Fuentes e imágenes reales: copia `FUENTES_PROVEEDORES` e `IMAGENES_PROVEEDORES` de
   `backend/.env.example` (una sola línea JSON cada una) y pon un contacto real en
   `FUENTES_USER_AGENT` / `IMAGENES_USER_AGENT`.
4. Recrea el backend: `docker compose up -d`.
5. Comprueba:

   ```bash
   docker compose exec backend python -m app.scripts.probar_llm
   docker compose exec backend python -m app.scripts.probar_proveedores
   ```

   Sin Docker, con el entorno virtual activado (`.venv\Scripts\Activate.ps1` o
   `source .venv/bin/activate`): `python -m app.scripts.probar_llm`.

| Resultado | Significa |
|---|---|
| "llave inválida" / 401 | La llave está mal copiada, revocada o es de otra organización |
| "sin conexión" / timeout | No hay salida HTTPS hacia el proveedor (firewall, proxy, DNS) |
| "modelo no disponible" / 404 | El identificador del modelo no existe o tu cuenta no tiene acceso |

**Egreso necesario** (si hay firewall corporativo o universitario): `api.anthropic.com`,
`api.openai.com`, `www.googleapis.com` (solo con YouTube), endpoints de AWS de la región (KMS,
S3, SES) y los dominios de cada proveedor activo de fuentes e imágenes. Los navegadores solo
necesitan `www.youtube-nocookie.com`.

**Si una llave se filtra:** revócala en la consola del proveedor, genera otra, actualiza `.env`
y ejecuta `docker compose up -d` (recrea el backend). Las llaves solo llegan al servicio backend;
nunca se suben al repositorio, a la imagen ni a los logs.

**Cadena de timeouts:** Caddy `response_header_timeout` (120 s) > `CHAT_TIMEOUT_TURNO_SEGUNDOS`
(100) > `LLM_TIMEOUT_SEGUNDOS` (45). Si subes uno, sube también los de su izquierda (el de Caddy
está en `frontend/Caddyfile`).

---

## 7. Protección de datos (Ley 1581 de 2012)

> ⚠️ Las plantillas legales y este resumen **no son asesoría legal**. Un abogado debe revisarlas
> antes de producción.

- **Responsable del tratamiento:** se configura con `RESPONSABLE_RAZON_SOCIAL`,
  `RESPONSABLE_NIT`, `RESPONSABLE_DOMICILIO` y `RESPONSABLE_CORREO_DATOS` **solo en el `.env`**
  (nunca en el repositorio, que es público). En producción el backend no arranca si faltan.
- **Textos legales:** `backend/app/legal/politica_tratamiento_v1.md` y
  `consentimientos_v1.json`. En producción el backend no arranca si quedan marcadores `{{...}}`.
  Al cambiar la política, sube `POLITICA_VERSION` (y `POLITICA_VERSION_MINIMA_ACEPTADA` si debe
  volver a aceptarse).
- **Finalidades y casillas separadas:** cada finalidad se acepta por separado; las opcionales no
  condicionan el servicio.
- **Prueba de la autorización:** se guarda la versión aceptada, la fecha y un seudónimo de la IP
  (HMAC con `INDICE_CIEGO_CLAVE`).
- **Derechos del titular** (conocer, actualizar, rectificar, suprimir, revocar): desde la sección
  de privacidad de la app. Plazos de referencia: **10 días hábiles** para consultas y **15** para
  reclamos (a verificar con el abogado). Con la instancia bajo demanda, los plazos corren aunque
  esté apagada: enciéndela y ejecuta
  `docker compose exec backend python -m app.scripts.listar_solicitudes_vencidas` con la
  frecuencia que exija el plazo, y atiende el buzón `RESPONSABLE_CORREO_DATOS`.
- **Menores:** autorización del representante legal por correo (enlace con token de un solo uso,
  vigencia `AUTORIZACION_TOKEN_HORAS`); hasta que se confirma, la cuenta no puede usar el tutor.
- **Transferencia internacional:** los mensajes viajan a Anthropic y OpenAI (EE. UU.) y, en AWS,
  se procesan en la región elegida. Debe informarse en la política.
- **Incidentes de seguridad:** contener (rotar llaves y secretos, apagar la instancia si hace
  falta), evaluar el alcance, notificar a la SIC en el plazo que fija la norma y a los titulares
  afectados; documentar.
- **RNBD:** verifica con el abogado si hay que inscribir las bases de datos en el Registro
  Nacional de Bases de Datos.
- **Supresión de cuenta:** se eliminan datos de perfil, conversaciones, archivos y plan; se
  conservan solo los registros que la ley exige (prueba de autorización, consumo agregado) por el
  tiempo de retención configurado.

---

## 8. Datos personales, menores y cifrado

- **Qué se guarda:** cuenta (correo, nombre, fecha de nacimiento), datos del acudiente,
  diagnóstico, plan, conversaciones, archivos del nivel Avanzado (en S3, con expiración),
  alertas de seguridad infantil y consumo de IA.
- **Qué se cifra (columnas, con DEK envuelta por KMS):** datos personales de `usuario`, correos
  de `autorizacion_acudiente`, tema y resumen de `conversacion`, contenido y bloques de
  `mensaje`, respuestas de `actividad`, tema del diagnóstico, preferencias del perfil de
  aprendizaje, nombre original de los archivos, detalle de `alerta_seguridad` y de
  `solicitud_titular` (lista exacta: columnas `TextoCifrado`/`JsonCifrado` en
  `backend/app/models/`). El correo además tiene un índice ciego (HMAC) para buscar sin
  descifrar. Disco EBS, buckets y respaldos cifrados con KMS.
- **Qué se envía a cada proveedor:** a Anthropic, el contexto de la conversación (sin correo ni
  nombre); a OpenAI, el texto o archivo a moderar y los prompts de ilustración con un
  `safety_identifier` seudónimo; a YouTube, solo términos de búsqueda.
- **Retención:** `ARCHIVO_RETENCION_DIAS`, `RETENCION_MENSAJES_DIAS`, `RETENCION_ALERTAS_DIAS`,
  `RETENCION_CONSUMO_DIAS`. La limpieza corre al apagar la instancia (`limpiar_datos_vencidos`).
- **Limitaciones:** el estudiante puede escribir datos personales en texto libre (se cifran pero
  se envían al LLM); los datos están en claro en memoria mientras se usan.

> ⚠️ El tratamiento de datos de menores, la autorización parental, la transferencia internacional
> y la norma que cite el Plan de Negocios requieren **revisión legal antes del lanzamiento
> comercial**.

**Alertas de seguridad infantil:** la tabla `alerta_seguridad` requiere revisión humana
periódica. Define quién la revisa y con qué frecuencia; con el modo bajo demanda hay que encender
el sistema para hacerlo:

```bash
docker compose exec backend python -m app.scripts.listar_alertas
```

---

## 9. Consumo y costos de IA

Cada llamada a un proveedor se registra en `consumo_ia` (modelo, tokens, costo calculado y
`es_estimacion`). Para consultar:

```bash
docker compose exec db psql -U tutoria -d tutoria
```

```sql
-- Costo por día
SELECT date_trunc('day', fecha) AS dia, round(sum(costo_estimado_usd), 4) AS usd
FROM consumo_ia GROUP BY 1 ORDER BY 1 DESC LIMIT 30;

-- Por proveedor, modelo y operación en el mes actual
SELECT proveedor, modelo, operacion, count(*) AS llamadas,
       sum(tokens_entrada) AS entrada, sum(tokens_salida) AS salida, sum(imagenes) AS imagenes,
       round(sum(costo_estimado_usd), 4) AS usd, bool_or(es_estimacion) AS hay_estimaciones
FROM consumo_ia WHERE fecha >= date_trunc('month', now())
GROUP BY 1, 2, 3 ORDER BY usd DESC;

-- Llamadas fallidas recientes (cuentan en el costo si el proveedor cobró)
SELECT fecha, proveedor, modelo, operacion FROM consumo_ia WHERE NOT exito ORDER BY fecha DESC LIMIT 20;
```

Las tarifas se ajustan en
`TARIFAS_IA` (JSON, USD por millón de tokens; verifícalas en las páginas de precios) y el tope de
ilustraciones en `PRESUPUESTO_IMAGENES_MENSUAL_USD`. El gasto real se limita además en la consola
de cada proveedor y con AWS Budgets (§10).

---

## 10. Ruta D — Despliegue en AWS (EC2 bajo demanda)

> Tú ejecutas todo lo de esta sección en tu cuenta. Ningún archivo del repositorio contiene
> cuentas, ARN, dominios ni IP reales: sustituye los marcadores `<...>`.

### 10.1 Qué se despliega y por qué

- **Una EC2** con Docker Compose (los mismos tres contenedores de §1.1). Para un proyecto con
  pocos usuarios evita los costos fijos de balanceador, NAT y base de datos administrada.
- **Bajo demanda:** un cron en la instancia la apaga tras 30 min sin uso real (con respaldo); una
  **Lambda despertador** con Function URL la enciende y muestra una página de espera.
- **Elastic IP** obligatoria (sin ella la IP cambia en cada encendido y el DNS y el certificado
  dejan de coincidir). **Sin puerto 22**: administración con Session Manager.
- **IMDSv2 con `HttpPutResponseHopLimit=2`:** los contenedores están un salto más allá del host;
  con 1, el backend no obtiene credenciales del rol. Por eso el backend bloquea
  `169.254.169.254` y los rangos privados/link-local en la descarga de imágenes (protección SSRF,
  con prueba en `backend/tests/services/test_adaptadores_externos.py`).
- **Con la instancia detenida siguen cobrando:** el disco EBS, la Elastic IP (AWS cobra las IPv4
  públicas, también asociadas a instancias detenidas — **verifica** la tarifa vigente) y lo
  almacenado en S3; la Lambda no tiene un cargo relevante con poco uso. **No hay cifras aquí:**
  calcula con la [calculadora de precios de AWS](https://calculator.aws/).

### 10.2 Variables del `.env` de producción

| Variable | Valor |
|---|---|
| `APP_ENV` | `production` |
| `SITE_ADDRESS` | `tutoria.<tu-dominio>` |
| `APP_ORIGIN` | `https://tutoria.<tu-dominio>` (sin comodines) |
| `FRONTEND_URL` | URL del despertador (§10.8) o, si no se usa, igual a `APP_ORIGIN` |
| `WEB_BIND` / `WEB_PORT` / `WEB_HTTPS_PORT` | `0.0.0.0` / `80` / `443` |
| `COOKIE_SECURE` / `COOKIE_DOMAIN` | `true` / vacío |
| `CIFRADO_PROVEEDOR` | `kms` (+ `KMS_KEY_ID=alias/tutoria-prod`, `CIFRADO_DEK_ENVUELTA`) |
| `ALMACEN_PROVEEDOR` | `s3` (+ `S3_BUCKET`, `S3_REGION`) |
| `CORREO_PROVEEDOR` | `ses` (+ `SES_REGION`, `CORREO_REMITENTE=no-responder@<tu-dominio>`) |
| `LLM_PROVIDER` / `MODERACION_PROVEEDOR` | `anthropic` / `openai` |
| `VIDEOS_PROVEEDOR` | `youtube` |
| `FUENTES_PROVEEDORES` / `IMAGENES_PROVEEDORES` | Listas JSON reales (sin `fake`) |
| `RESPONSABLE_*` | Datos reales del Responsable |

El backend rechaza arrancar en `production` con proveedores `fake`/`local`, secretos cortos,
`CORS_ORIGINS` con comodines, `RESPONSABLE_*` incompletos o marcadores `{{...}}` en los textos
legales. `/docs` y `/openapi.json` quedan desactivados.

### 10.3 Pasos únicos de la cuenta

Convenciones: prefijo `tutoria-`, etiqueta `Proyecto=tutoria`, región `us-east-1` por defecto.
`sa-east-1` (São Paulo) reduce latencia desde Colombia pero suele costar más: verifica que KMS,
SES, EC2 y Lambda estén disponibles y usa la misma región para todo. Los datos igualmente viajan
a los proveedores de IA en EE. UU.

1. Crea la cuenta de AWS, activa **MFA en el usuario raíz**, crea un administrador con **IAM
   Identity Center** y no uses el raíz para nada más.
2. Instala AWS CLI v2 y el plugin de Session Manager:

   | Sistema | Comando |
   |---|---|
   | Windows | `winget install Amazon.AWSCLI` y `winget install Amazon.SessionManagerPlugin` |
   | macOS | `brew install awscli` y `brew install --cask session-manager-plugin` |
   | Linux | [instalador oficial de AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) y el `.deb`/`.rpm` del [plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) |

3. `aws configure sso` (perfil `tutoria`) y en cada terminal:
   `export AWS_PROFILE=tutoria` (bash) · `$env:AWS_PROFILE="tutoria"` (PowerShell).
4. **Presupuesto** con avisos al 50 %, 80 % y 100 % (Billing → Budgets → Create budget →
   monthly cost budget), con tu correo.
5. Recomendado: activa **CloudTrail** (trail de administración en S3).

### 10.4 Clave KMS, buckets y roles

Los comandos son bash. En PowerShell cambia `\` final por `` ` ``, y `VAR=valor` por `$VAR="valor"`.

```bash
REGION=us-east-1
CUENTA=$(aws sts get-caller-identity --query Account --output text)
B_ARCHIVOS=tutoria-archivos-$CUENTA
B_RESPALDOS=tutoria-respaldos-$CUENTA

# 1. Clave KMS con rotación anual y alias
KEY_ID=$(aws kms create-key --region $REGION --description "TutorIA prod" \
  --tags TagKey=Proyecto,TagValue=tutoria --query KeyMetadata.KeyId --output text)
aws kms enable-key-rotation --region $REGION --key-id $KEY_ID
aws kms create-alias --region $REGION --alias-name alias/tutoria-prod --target-key-id $KEY_ID
```

Copia `deploy/iam/*.json` a una carpeta fuera del repositorio, sustituye los marcadores
(`<cuenta>`, `<region>`, `<kms-key-id>`, buckets, `<dominio>`) y continúa desde esa carpeta:

```bash
# 2. Buckets privados, cifrados con KMS, sin tráfico sin TLS y con expiración
for B in $B_ARCHIVOS $B_RESPALDOS; do
  aws s3api create-bucket --bucket $B --region $REGION   # fuera de us-east-1 añade: --create-bucket-configuration LocationConstraint=$REGION
  aws s3api put-public-access-block --bucket $B \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  aws s3api put-bucket-encryption --bucket $B --server-side-encryption-configuration file://s3-cifrado.json
  aws s3api put-bucket-tagging --bucket $B --tagging 'TagSet=[{Key=Proyecto,Value=tutoria}]'
done
aws s3api put-bucket-policy --bucket $B_ARCHIVOS --policy file://s3-archivos-politica-bucket.json
aws s3api put-bucket-policy --bucket $B_RESPALDOS --policy file://s3-respaldos-politica-bucket.json
aws s3api put-bucket-lifecycle-configuration --bucket $B_ARCHIVOS --lifecycle-configuration file://s3-archivos-ciclo-vida.json
aws s3api put-bucket-lifecycle-configuration --bucket $B_RESPALDOS --lifecycle-configuration file://s3-respaldos-ciclo-vida.json

# 3. Rol y perfil de la instancia
aws iam create-role --role-name tutoria-ec2 --assume-role-policy-document file://ec2-confianza.json \
  --tags Key=Proyecto,Value=tutoria
aws iam attach-role-policy --role-name tutoria-ec2 \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam put-role-policy --role-name tutoria-ec2 --policy-name tutoria-ec2 --policy-document file://ec2-politica.json
aws iam create-instance-profile --instance-profile-name tutoria-ec2
aws iam add-role-to-instance-profile --instance-profile-name tutoria-ec2 --role-name tutoria-ec2

# 4. Política de la clave (después del rol: KMS exige que el principal exista)
aws kms put-key-policy --region $REGION --key-id $KEY_ID --policy-name default \
  --policy file://kms-politica-clave.json
```

La regla de expiración de `s3-archivos-ciclo-vida.json` (180 días) debe coincidir con
`ARCHIVO_RETENCION_DIAS`.

### 10.5 Grupo de seguridad, instancia, IP y DNS

```bash
VPC=$(aws ec2 describe-vpcs --region $REGION --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
SG=$(aws ec2 create-security-group --region $REGION --group-name tutoria-web \
  --description "TutorIA: solo 80 y 443" --vpc-id $VPC --query GroupId --output text)
aws ec2 authorize-security-group-ingress --region $REGION --group-id $SG \
  --ip-permissions 'IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0}],Ipv6Ranges=[{CidrIpv6=::/0}]' \
                   'IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[{CidrIp=0.0.0.0/0}],Ipv6Ranges=[{CidrIpv6=::/0}]'
```

Edita las tres primeras variables de `deploy/ec2/user-data.sh` (`BUCKET_RESPALDOS`,
`KMS_KEY_ID`, `AWS_REGION`; no son secretos) y lanza la instancia. AMI: Ubuntu 24.04 LTS por el
parámetro público de Canonical (para ARM/t4g cambia `amd64` por `arm64`):

```bash
INSTANCIA=$(aws ec2 run-instances --region $REGION \
  --image-id resolve:ssm:/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
  --instance-type t3.small \
  --iam-instance-profile Name=tutoria-ec2 \
  --security-group-ids $SG \
  --user-data file://deploy/ec2/user-data.sh \
  --metadata-options HttpTokens=required,HttpPutResponseHopLimit=2,HttpEndpoint=enabled \
  --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=30,VolumeType=gp3,Encrypted=true,KmsKeyId=alias/tutoria-prod,DeleteOnTermination=false}" \
  --disable-api-termination \
  --instance-initiated-shutdown-behavior stop \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=tutoria},{Key=Proyecto,Value=tutoria}]' \
                       'ResourceType=volume,Tags=[{Key=Proyecto,Value=tutoria}]' \
  --query 'Instances[0].InstanceId' --output text)
echo $INSTANCIA

ALLOC=$(aws ec2 allocate-address --region $REGION --domain vpc \
  --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Proyecto,Value=tutoria}]' --query AllocationId --output text)
aws ec2 wait instance-running --region $REGION --instance-ids $INSTANCIA
aws ec2 associate-address --region $REGION --instance-id $INSTANCIA --allocation-id $ALLOC
aws ec2 describe-addresses --region $REGION --allocation-ids $ALLOC --query 'Addresses[0].PublicIp' --output text
```

- `t3.small` (2 GB) es el mínimo; `t3.medium` compila más rápido. Verifica precios.
- `--instance-initiated-shutdown-behavior stop` hace que `shutdown` **detenga** (no termine) la instancia.
- `--disable-api-termination` y `DeleteOnTermination=false` protegen el disco y los datos.

**DNS:** crea un registro **A** `tutoria.<tu-dominio>` → la Elastic IP. En Route 53:
Hosted zones → tu dominio → Create record. En otro proveedor (GoDaddy, Cloudflare, etc.): un
registro A con nombre `tutoria` y la IP; en Cloudflare, con el proxy **desactivado** (nube gris)
para que Caddy pueda obtener el certificado.

### 10.6 Instalar la aplicación (Session Manager)

```bash
aws ssm start-session --region $REGION --target $INSTANCIA
```

Dentro de la sesión (no hay SSH):

```bash
sudo -iu ubuntu
cloud-init status --wait                       # espera a que termine user-data.sh
git clone https://github.com/alebenavidezr05/tutorIa-compose.git ~/tutoria
cd ~/tutoria
bash deploy/clonar.sh                          # trae backend/ y frontend/
sudo bash deploy/ec2/instalar.sh               # scripts, tutoria.service y cron
cp .env.example .env && chmod 600 .env
nano .env                                      # valores de §10.2
```

Genera la DEK de la aplicación (una vez):

```bash
docker compose build backend
docker compose run --rm --no-deps backend python -m app.scripts.generar_dek_kms --kms-key-id alias/tutoria-prod
# o: aws kms generate-data-key --key-id alias/tutoria-prod --key-spec AES_256 --query CiphertextBlob --output text
```

Pega el bloque cifrado en `CIFRADO_DEK_ENVUELTA=` del `.env` y **guarda una copia fuera de la
instancia** (gestor de contraseñas). Luego:

```bash
sudo systemctl start tutoria                   # compila y levanta (la primera vez tarda)
docker compose ps
curl -fsS https://tutoria.<tu-dominio>/api/v1/health/ready
```

Caddy obtiene el certificado en el primer arranque si el DNS ya apunta a la Elastic IP.

> ⚠️ **Dependencia crítica:** perder o borrar la clave KMS, o perder `CIFRADO_DEK_ENVUELTA` sin
> copia, hace **irrecuperables** los datos cifrados (también en los respaldos). Si programas el
> borrado de la clave, AWS aplica una espera de 7 a 30 días durante la cual se puede cancelar.
> Rotación de la DEK: `docker compose exec backend python -m app.scripts.rotar_cifrado`
> (ver la ayuda del script; respalda antes).

### 10.7 Correo con SES

1. SES → Identities → Create identity → **dominio** `<tu-dominio>` con **Easy DKIM**; crea en tu
   DNS los registros CNAME que muestra. Añade SPF (MAIL FROM personalizado opcional) y un registro
   **DMARC** `_dmarc.<tu-dominio>` TXT `v=DMARC1; p=quarantine; rua=mailto:<buzón>`.
2. Configuration set `tutoria` con destino de eventos de rebotes y quejas a SNS o CloudWatch.
3. Remitente: `CORREO_REMITENTE=no-responder@<tu-dominio>` (igual que en la política del rol).

> ⚠️ **Sandbox de SES:** las cuentas nuevas solo pueden enviar a direcciones verificadas y con
> cuota baja. **Sin salir del sandbox, los correos de autorización a los acudientes no llegan.**
> Antes del lanzamiento solicita el acceso a producción (SES → Account dashboard → Request
> production access) describiendo el caso de uso y cómo manejas rebotes y quejas. Entretanto,
> verifica cada correo de prueba en SES → Identities → Email address.

### 10.8 Despertador (Lambda con Function URL)

```bash
cd deploy/despertador && zip ../../despertador.zip lambda_function.py && cd ../..
#   PowerShell: Compress-Archive deploy/despertador/lambda_function.py despertador.zip

aws iam create-role --role-name tutoria-despertador --assume-role-policy-document file://despertador-confianza.json
aws iam attach-role-policy --role-name tutoria-despertador \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam put-role-policy --role-name tutoria-despertador --policy-name tutoria-despertador \
  --policy-document file://despertador-politica.json

aws lambda create-function --region $REGION --function-name tutoria-despertador \
  --runtime python3.12 --handler lambda_function.handler --memory-size 128 --timeout 10 \
  --role arn:aws:iam::$CUENTA:role/tutoria-despertador --zip-file fileb://despertador.zip \
  --environment "Variables={INSTANCE_ID=$INSTANCIA,APP_URL=https://tutoria.<tu-dominio>}" \
  --tags Proyecto=tutoria
aws lambda put-function-concurrency --region $REGION --function-name tutoria-despertador \
  --reserved-concurrent-executions 5

aws lambda create-function-url-config --region $REGION --function-name tutoria-despertador --auth-type NONE
# URL pública: la política de recursos debe conceder lambda:InvokeFunctionUrl Y lambda:InvokeFunction
aws lambda add-permission --region $REGION --function-name tutoria-despertador \
  --statement-id url-publica --action lambda:InvokeFunctionUrl --principal "*" \
  --function-url-auth-type NONE
aws lambda add-permission --region $REGION --function-name tutoria-despertador \
  --statement-id url-publica-invoke --action lambda:InvokeFunction --principal "*" \
  --invoked-via-function-url
aws lambda get-function-url-config --region $REGION --function-name tutoria-despertador --query FunctionUrl --output text
```

(Requisito de doble permiso confirmado en la documentación de Lambda; si tu versión de la CLI no
reconoce `--invoked-via-function-url`, actualízala o crea la URL desde la consola, que añade la
política sola.) Si la reserva de concurrencia falla por la cuota de la cuenta, omítela.

Prueba: detén la instancia (`aws ec2 stop-instances --instance-ids $INSTANCIA`) y abre la URL
de la Function. Debe mostrar "Encendiendo TutorIA…" y redirigir a la app. Luego pon
`FRONTEND_URL=<url de la Function>` en el `.env` y ejecuta `docker compose up -d`: así los
enlaces de los correos pasan por el despertador (el backend solo usa `FRONTEND_URL` para
construir enlaces; no lo compara con `CORS_ORIGINS`).

> Riesgo asumido: cualquiera con la URL puede encender la instancia. Límites: concurrencia
> reservada, solo enciende si está detenida, el apagado automático la vuelve a detener y hay
> presupuesto con alertas. No publiques la URL fuera de los usuarios.

Alternativa o complemento por horario: `deploy/scheduler/README.md` (EventBridge Scheduler).

### 10.9 Contenido curado (opcional)

```bash
docker compose exec backend python -m app.scripts.cargar_fuentes_curadas data/fuentes_curadas.ejemplo.json
docker compose exec backend python -m app.scripts.cargar_videos data/videos_curados.ejemplo.json
# Con tu propio archivo: docker compose cp mis_fuentes.json backend:/tmp/ y usa /tmp/mis_fuentes.json
```

### 10.10 Verificación posterior (lista de aceptación)

- [ ] `https://tutoria.<tu-dominio>/api/v1/health/ready` responde 200 con certificado válido.
- [ ] `https://tutoria.<tu-dominio>/docs` responde 404.
- [ ] `curl -s -o /dev/null -w '%{http_code}' https://tutoria.<tu-dominio>/api/v1/auth/me` → `401`.
- [ ] Registro de un mayor y de un menor con acudiente (correo real recibido), un turno del
      tutor y la subida de un archivo en nivel Avanzado (aparece en el bucket de archivos).
- [ ] El backend usa el rol de la instancia:
      `docker compose exec backend python -c "import boto3;print(boto3.client('sts').get_caller_identity()['Arn'])"`
      imprime `...assumed-role/tutoria-ec2/...`.
- [ ] **Cifrado:** `docker compose exec db psql -U tutoria -d tutoria -c "SELECT * FROM usuario LIMIT 3;"`
      y lo mismo con `mensaje`: correo, nombre y contenido **no** son legibles.
- [ ] **Redes:** `docker compose exec db wget -T 3 -qO- https://example.com` falla; desde backend funciona.
- [ ] **SSRF:** la prueba automática vive en el CI del backend
      (`tests/services/test_adaptadores_externos.py`: la descarga de imágenes rechaza
      `http://169.254.169.254/` y rangos privados o link-local). Con IMDS en salto 2 es
      obligatorio que esa prueba esté en verde antes de desplegar.
- [ ] **Apagado automático:** sin uso, a los ~30 min (y pasados 20 de encendida) la instancia se
      detiene sola y aparece un respaldo nuevo en `s3://<respaldos>/bd/`;
      `journalctl -t tutoria` lo registra. Con solo `curl` a rutas que dan 401/404 o a
      `/api/v1/health`, se apaga igual. Con un usuario activo, no se apaga.
- [ ] **Despertador:** con la instancia detenida, la URL de la Function la enciende y redirige
      conservando ruta y `#fragmento`.
- [ ] **Reinicio:** `sudo reboot`; al volver, `docker compose ps` muestra los tres servicios healthy.
- [ ] **Respaldo y restauración probados** (§10.11). Un respaldo que nunca se restauró no cuenta.

### 10.11 Operación diaria

```bash
# Entrar
aws ssm start-session --target <instance-id>
sudo -iu ubuntu && cd ~/tutoria

# Logs
docker compose logs -f backend          # app
docker compose logs -f frontend         # accesos (Caddy, JSON)
journalctl -t tutoria                   # apagado automático, respaldos
systemctl status tutoria ; journalctl -u tutoria

# Actualizar (respaldo + git pull de los 3 repos + build + up + verificación)
bash deploy/ec2/actualizar.sh

# Respaldar y restaurar
sudo respaldar-bd.sh
aws s3 ls s3://<respaldos>/bd/
sudo BD_DESTINO=tutoria_prueba restaurar-bd.sh tutoria-AAAAMMDDTHHMMSSZ.sql.gz   # restauración de prueba
sudo restaurar-bd.sh tutoria-AAAAMMDDTHHMMSSZ.sql.gz                             # sobre la base real (pide escribir BORRAR)

# Siempre encendida (pagos reales, demo) / volver al modo bajo demanda
sudo touch /etc/tutoria/siempre-encendido
sudo rm /etc/tutoria/siempre-encendido
```

Desde tu equipo:

```bash
aws ec2 start-instances --instance-ids <instance-id>
aws ec2 stop-instances --instance-ids <instance-id>     # sin respaldo: prefiere sudo shutdown -h now dentro
aws ec2 describe-instances --instance-ids <instance-id> --query 'Reservations[0].Instances[0].State.Name'
```

Para restaurar los datos cifrados hacen falta la misma clave KMS y la misma
`CIFRADO_DEK_ENVUELTA`. Mejora opcional: instantáneas del disco EBS con Data Lifecycle Manager.

**Despliegue desde GitHub (opcional):** `.github/workflows/deploy.yml` (manual, entorno
`produccion` con aprobación, OIDC sin llaves). Crea el proveedor OIDC de GitHub en IAM, el rol con
`deploy/iam/github-oidc-*.json` y en el entorno las variables `AWS_REGION`, `AWS_ROLE_ARN`,
`EC2_INSTANCE_ID` y `APP_DOMINIO`. Si prefieres actualizar a mano, ignóralo. Si algún día los
repositorios se vuelven privados, añade una *deploy key* de solo lectura por repositorio.

### 10.12 Límites del modo bajo demanda

- **Primer ingreso lento:** encender y levantar los contenedores toma minutos.
- **Pagos reales con webhooks:** con el servidor apagado la notificación puede perderse. Antes de
  activar una pasarela real: `siempre-encendido` o conciliar pagos al arrancar. Con la pasarela
  simulada no aplica.
- **Tareas programadas:** la limpieza de datos vencidos corre al apagar, no a hora fija.
- **Ley 1581:** los plazos corren con la instancia apagada (§7).
- **Una sola instancia:** sin alta disponibilidad. Aceptable para el MVP.

### 10.13 Borrar todo

```bash
aws ec2 modify-instance-attribute --instance-id <instance-id> --no-disable-api-termination
aws ec2 terminate-instances --instance-ids <instance-id>
aws ec2 delete-volume --volume-id <vol-id>                 # DeleteOnTermination=false: bórralo aparte
aws ec2 release-address --allocation-id <alloc-id>
aws ec2 delete-security-group --group-id <sg-id>
aws lambda delete-function --function-name tutoria-despertador
aws s3 rb s3://<archivos> --force ; aws s3 rb s3://<respaldos> --force
aws iam remove-role-from-instance-profile --instance-profile-name tutoria-ec2 --role-name tutoria-ec2
aws iam delete-instance-profile --instance-profile-name tutoria-ec2
# borra las políticas en línea y adjuntas de cada rol y luego: aws iam delete-role --role-name ...
aws kms schedule-key-deletion --key-id alias/tutoria-prod --pending-window-in-days 30   # ¡último paso!
```

---

## 11. Ruta C — AWS administrado (opcional)

No generada. ECS Fargate + RDS + CloudFront (Anexo A del prompt 03) se construye solo si se pide,
cuando haga falta alta disponibilidad o muchos usuarios simultáneos.

---

## 12. Pruebas y calidad

```bash
# Backend (con el entorno virtual activado)
cd backend
pytest
ruff check . && ruff format --check .
mypy app

# Frontend
cd frontend
npm run lint
npm run test:ci

# Caddyfile
docker run --rm -e SITE_ADDRESS=:80 -v "$PWD/frontend/Caddyfile:/etc/caddy/Caddyfile:ro" \
  caddy:2.11-alpine caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
```

CI: `backend.yml` (Windows, Linux y macOS + trabajo con PostgreSQL), `frontend.yml` y, en este
repositorio, `docker.yml` (compose completo, salud, redes, puertos, 401 y cookies fuera del log).
Ninguna prueba usa llaves reales.

---

## 13. Solución de problemas

| Síntoma | Causa probable | Solución |
|---|---|---|
| `Activate.ps1 cannot be loaded` | Política de ejecución de PowerShell | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| `python` no se reconoce / abre Microsoft Store | PATH o alias de la tienda | Usar `py -3.11`; desactivar el alias en Configuración → Aplicaciones → Alias de ejecución |
| `connection refused` a PostgreSQL | Servicio apagado o puerto ocupado | Windows: servicio `postgresql-x64-16`; Linux: `sudo systemctl start postgresql`; macOS: `brew services start postgresql@16` |
| Puerto 8000/4200/8080 ocupado | Otro proceso lo usa | Windows `netstat -ano \| findstr :8000`; Linux/macOS `lsof -i :8000`; cambia `WEB_PORT` o el puerto |
| Todas las peticiones dan 401 `SESION_INVALIDA` tras iniciar sesión | La cookie no se envía (Secure sobre HTTP, SameSite, dominio) o cambió `version_token` | Revisar `COOKIE_SECURE` (false en HTTP local), HTTPS en producción, volver a iniciar sesión |
| Mutaciones dan 403 `ORIGEN_NO_PERMITIDO` | El `Origin` del navegador no es `APP_ORIGIN` | Ajustar `APP_ORIGIN` al origen exacto (esquema, host y puerto) |
| El backend no arranca: "marcadores sin reemplazar" o faltan `RESPONSABLE_*` | Plantillas legales o datos del responsable incompletos | Completar `RESPONSABLE_*` y `backend/app/legal/` |
| El backend no arranca: error al leer `CORS_ORIGINS`, `FUENTES_PROVEEDORES`… | Variable de lista vacía o JSON inválido en `.env` | Quita la línea (usa el valor por defecto) o pon JSON válido en una sola línea |
| `exec ... no such file or directory` en un contenedor | Finales de línea CRLF | Verificar `.gitattributes` y volver a clonar |
| Docker lento o fallos en volúmenes (Windows/macOS) | Sistema de archivos compartido | Clonar dentro de WSL 2; usar el modo desarrollo solo cuando haga falta |
| `no matching manifest for linux/arm64` | Imagen sin soporte ARM | Las imágenes usadas son multi-arquitectura; actualizar Docker y revisar `platform:` |
| Error compilando bcrypt/psycopg | pip viejo o Python no soportado | `pip install --upgrade pip`, Python 3.11, paquetes `-binary` |
| `npm ci` falla por versión de Node | Node por debajo de lo que pide Angular 22 | Instalar Node 22.22.3+ o 24 LTS con nvm/winget/brew |
| 502/504 en el chat | Timeouts incoherentes | Caddy 120 > turno 100 > LLM 45 (§6) |
| `LLM_NO_CONFIGURADO` o no arranca con `LLM_PROVIDER=anthropic` | Llave o modelo ausentes/ inválidos | Revisar `.env`, `probar_llm`, verificar el modelo |
| No arranca por el cifrado | Falta `CIFRADO_DEK_ENVUELTA`, el rol no puede usar KMS o `CIFRADO_PROVEEDOR=local` en producción | §10.6 y permisos del rol (`deploy/iam/`) |
| `Unable to locate credentials` / `AccessDenied` en la EC2 | Límite de saltos IMDS en 1, rol sin asociar o permiso faltante | `aws ec2 modify-instance-metadata-options --instance-id <id> --http-tokens required --http-put-response-hop-limit 2`; revisar el perfil de instancia |
| Caddy no obtiene el certificado | DNS no apunta a la Elastic IP, 80/443 cerrados o límite de Let's Encrypt | Revisar registro A, grupo de seguridad y `docker compose logs frontend`; **no borrar** el volumen `caddy_data` |
| Tras reiniciar la instancia no hay app | `tutoria.service` no habilitado o falló | `systemctl status tutoria`, `journalctl -u tutoria`, repetir `instalar.sh` |
| La instancia se apaga con gente usándola | El filtro no coincide con el formato del log o los usuarios solo reciben errores | `docker compose logs frontend`, filtro `jq` de `apagar-si-inactivo.sh`, `journalctl -t tutoria` |
| La instancia nunca se apaga | Existe `/etc/tutoria/siempre-encendido`, cron no instalado o robots con 2xx | Revisar el archivo, `/etc/cron.d/tutoria-apagado` y el log |
| La página del despertador no avanza | La instancia no pasa de `pending`, DNS o la app no responde | Estado en la consola EC2, `APP_URL`, `/api/v1/health/ready`; si vuelve a `stopped`, falta `kms:CreateGrant` (deploy/iam/README.md) |
| La compilación del frontend se queda sin memoria | RAM insuficiente | Verificar el swap (`swapon --show`) o usar `t3.medium` |
| El acudiente no recibe el correo | SES en sandbox, identidad sin verificar, spam o `CORREO_PROVEEDOR=fake` | Salir del sandbox, verificar dominio y DKIM, revisar rebotes |
| El enlace del correo no abre nada | El servidor estaba apagado y `FRONTEND_URL` apunta directo a la app | `FRONTEND_URL` = URL del despertador (§10.8) |
| Las imágenes del tutor no aparecen | `IMAGENES_PROVEEDORES` en fake, sin egreso, licencia rechazada o fallo de la descarga | Activar un proveedor, revisar egreso y logs del trabajo visual; el CSP solo necesita `'self'` |
| El video no se reproduce | CSP sin `frame-src` de youtube-nocookie, video retirado o no incrustable | Revisar la cabecera CSP y el video |
| La ilustración IA nunca llega | Presupuesto o cupo agotado, `IMAGENES_IA_ACTIVA=false` o moderación | Revisar `consumo_ia`, límites y logs |
| El respaldo falla | Permisos S3/KMS, `pg_dump` con error o disco lleno | `journalctl -t tutoria`, `sudo respaldar-bd.sh`, `df -h` |

---

## 14. Estructura, convenciones y hoja de ruta

```
tutorIa-compose/
├── backend/ · frontend/        clones (ignorados por este repo)
├── deploy/
│   ├── clonar.sh               trae backend y frontend
│   ├── ec2/                    user-data, instalar, servicio systemd, apagado, respaldo, restauración, actualizar
│   ├── despertador/            Lambda con Function URL
│   ├── iam/                    políticas de referencia (sin ARN reales)
│   └── scheduler/              encendido/apagado por horario (opcional)
├── docs/brand/
├── .github/workflows/          docker.yml (integración), deploy.yml (opcional)
├── docker-compose.yml          desarrollo y producción
├── docker-compose.dev.yml      overrides de desarrollo
└── .env.example
```

**Convenciones:** una responsabilidad por clase/módulo; capas `routers → services →
repositories`; excepciones propias traducidas a errores HTTP en un solo lugar; cada proveedor
externo con adaptador real y simulado; LF en todos los archivos; nada de secretos ni datos del
Responsable en los repositorios.

**Hoja de ruta:** migraciones con Alembic · caché Redis por tema+nivel · pasarela real
(Wompi/Stripe) · secretos en Parameter Store/Secrets Manager · proxy de salida con lista de
dominios · Bedrock como proveedor alterno · verificación semántica de citas · panel de revisión
de alertas.

Logs: a stdout, sin datos personales, prompts, archivos ni correos; rotación de Docker
(`10m` × 3 por contenedor). El registro de acceso de Caddy guarda la IP del cliente (dato
personal) y su retención queda limitada por esa rotación.
