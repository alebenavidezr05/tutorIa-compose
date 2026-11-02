# Encendido/apagado por horario (opcional) — EventBridge Scheduler

Útil para una demo o una clase con horario fijo. **No sustituye** al apagado por inactividad
(`deploy/ec2/apagar-si-inactivo.sh`): si nadie entra, la instancia se apaga igual tras 30 min
de inactividad (pasado el periodo de gracia). Usa destinos universales
(`arn:aws:scheduler:::aws-sdk:ec2:startInstances`); **verifica la sintaxis vigente** en la
documentación de EventBridge Scheduler.

Sustituye `<cuenta>`, `<region>`, `<instance-id>` y `<kms-key-id>` en los JSON de esta carpeta
(en una copia local, no en el repositorio).

## 1. Rol de ejecución

```bash
aws iam create-role --role-name tutoria-scheduler \
  --assume-role-policy-document file://deploy/scheduler/scheduler-confianza.json
aws iam put-role-policy --role-name tutoria-scheduler --policy-name tutoria-scheduler \
  --policy-document file://deploy/scheduler/scheduler-politica.json
```

## 2. Encender de lunes a viernes a las 7:00 (hora de Colombia)

Crea `encender.json`:

```json
{
  "Arn": "arn:aws:scheduler:::aws-sdk:ec2:startInstances",
  "RoleArn": "arn:aws:iam::<cuenta>:role/tutoria-scheduler",
  "Input": "{\"InstanceIds\": [\"<instance-id>\"]}"
}
```

```bash
aws scheduler create-schedule --name tutoria-encender-clase \
  --schedule-expression "cron(0 7 ? * MON-FRI *)" \
  --schedule-expression-timezone America/Bogota \
  --flexible-time-window Mode=OFF \
  --target file://encender.json
```

## 3. Parada de seguridad nocturna (23:00 todos los días)

La parada externa **no hace respaldo** (el apagado por inactividad sí). Es solo una red de
seguridad. Crea `parar.json` igual que el anterior pero con
`"Arn": "arn:aws:scheduler:::aws-sdk:ec2:stopInstances"`.

```bash
aws scheduler create-schedule --name tutoria-parada-nocturna \
  --schedule-expression "cron(0 23 * * ? *)" \
  --schedule-expression-timezone America/Bogota \
  --flexible-time-window Mode=OFF \
  --target file://parar.json
```

Los comandos funcionan igual en PowerShell (cambia `\` por `` ` `` al final de cada línea).

## Borrar

```bash
aws scheduler delete-schedule --name tutoria-encender-clase
aws scheduler delete-schedule --name tutoria-parada-nocturna
```
