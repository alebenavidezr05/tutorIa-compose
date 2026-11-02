"""Despertador de TutorIA: enciende la EC2 si está detenida y redirige a la app cuando responde.

Lambda (Python 3.12) con Function URL pública (AuthType NONE).
Variables de entorno: INSTANCE_ID (i-...) y APP_URL (https://tutoria.<dominio>).
Rutas:
  GET  /estado    -> {"estado": "<estado de la EC2>"}
  POST /encender  -> inicia la instancia solo si está "stopped"
  otra            -> página HTML de espera (conserva ruta, query y #fragmento al redirigir)
No toca datos de usuarios. Handler: lambda_function.handler
"""

import json
import os

import boto3

ec2 = boto3.client("ec2")
ID = os.environ["INSTANCE_ID"]
APP = os.environ["APP_URL"].rstrip("/")

PAGINA = """<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Encendiendo TutorIA</title>
<style>
  :root { color-scheme: light dark; --fondo: #f6f7fb; --texto: #1d2140; --suave: #5b6080; --acento: #4b3fd1; }
  @media (prefers-color-scheme: dark) { :root { --fondo: #14162a; --texto: #eef0ff; --suave: #a9adc9; --acento: #9b93ff; } }
  * { box-sizing: border-box; }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 16px;
         background: var(--fondo); color: var(--texto);
         font: 16px/1.5 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
  main { max-width: 32rem; text-align: center; }
  h1 { font-size: 1.5rem; margin: 0 0 .5rem; }
  p { color: var(--suave); margin: .25rem 0; }
  .giro { width: 48px; height: 48px; margin: 1.5rem auto; border-radius: 50%;
          border: 5px solid color-mix(in srgb, var(--acento) 25%, transparent);
          border-top-color: var(--acento); animation: g 1s linear infinite; }
  @keyframes g { to { transform: rotate(360deg); } }
  @media (prefers-reduced-motion: reduce) { .giro { animation: none; } }
  a { color: var(--acento); }
</style>
</head>
<body>
<main>
  <h1>Encendiendo TutorIA…</h1>
  <div class="giro" aria-hidden="true"></div>
  <p id="estado" role="status" aria-live="polite">Comprobando el servidor…</p>
  <p>Para ahorrar costos, el servidor se apaga cuando nadie lo usa. Encenderlo toma de 1 a 3 minutos.
     Esta página te llevará automáticamente cuando esté listo.</p>
  <p><a id="enlace" href="#">Ir a TutorIA</a></p>
</main>
<script>
(function () {
  var APP = __APP__;
  // Conserva ruta, query y #fragmento (el token de autorización del acudiente va en el fragmento).
  var destino = APP + location.pathname + location.search + location.hash;
  var texto = document.getElementById("estado");
  document.getElementById("enlace").href = destino;
  var pedido = false;

  function decir(t) { texto.textContent = t; }

  function appResponde() {
    // no-cors: la respuesta es opaca, pero la promesa solo se resuelve si el servidor contesta.
    return fetch(APP + "/api/v1/health/ready", { mode: "no-cors", cache: "no-store" })
      .then(function () { return true; }, function () { return false; });
  }

  function ciclo() {
    fetch("/estado", { cache: "no-store" })
      .then(function (r) { return r.json(); })
      .then(function (d) {
        var e = d.estado;
        if (e === "stopped" && !pedido) {
          pedido = true;
          decir("Encendiendo TutorIA… (1–3 min)");
          return fetch("/encender", { method: "POST" });
        }
        if (e === "running") {
          decir("Servidor encendido. Iniciando la aplicación…");
          return appResponde().then(function (ok) {
            if (ok) { decir("¡Listo! Abriendo TutorIA…"); location.replace(destino); }
          });
        }
        if (e === "stopping") { pedido = false; decir("El servidor se está apagando; lo volveremos a encender…"); return; }
        decir("Encendiendo TutorIA… (1–3 min)");
      })
      .catch(function () { decir("Reintentando…"); })
      .then(function () { setTimeout(ciclo, 4000); });
  }
  ciclo();
})();
</script>
</body>
</html>
"""


def _estado() -> str:
    r = ec2.describe_instances(InstanceIds=[ID])
    return r["Reservations"][0]["Instances"][0]["State"]["Name"]


def _json(codigo: int, cuerpo: dict) -> dict:
    return {
        "statusCode": codigo,
        "headers": {"content-type": "application/json", "cache-control": "no-store"},
        "body": json.dumps(cuerpo),
    }


def handler(event, context):
    http = event.get("requestContext", {}).get("http", {})
    ruta, metodo = http.get("path", "/"), http.get("method", "GET")
    if ruta == "/estado" and metodo == "GET":
        return _json(200, {"estado": _estado()})
    if ruta == "/encender" and metodo == "POST":
        estado = _estado()
        if estado == "stopped":
            ec2.start_instances(InstanceIds=[ID])
            estado = "pending"
        return _json(200, {"estado": estado})
    if ruta in ("/estado", "/encender"):
        return _json(405, {"error": "método no permitido"})
    csp = (
        "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; "
        f"connect-src 'self' {APP}; base-uri 'none'; frame-ancestors 'none'"
    )
    return {
        "statusCode": 200,
        "headers": {
            "content-type": "text/html; charset=utf-8",
            "cache-control": "no-store",
            "content-security-policy": csp,
            "referrer-policy": "no-referrer",
            "x-content-type-options": "nosniff",
        },
        "body": PAGINA.replace("__APP__", json.dumps(APP)),
    }
