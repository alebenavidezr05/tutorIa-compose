# Políticas IAM de referencia (Ruta D)

Plantillas sin datos reales. Sustituye los marcadores en una copia local antes de usarlas
(nunca subas la versión rellenada al repositorio): `<region>`, `<cuenta>`, `<kms-key-id>`,
`<instance-id>`, `<bucket-archivos>`, `<bucket-respaldos>`, `<dominio>`, `<usuario-github>`.

| Archivo | Para qué |
|---|---|
| `ec2-confianza.json` + `ec2-politica.json` | Rol `tutoria-ec2` de la instancia (+ política administrada `AmazonSSMManagedInstanceCore`) |
| `despertador-confianza.json` + `despertador-politica.json` | Rol `tutoria-despertador` de la Lambda (+ `AWSLambdaBasicExecutionRole`) |
| `kms-politica-clave.json` | Política de la clave `alias/tutoria-prod` |
| `s3-archivos-politica-bucket.json`, `s3-respaldos-politica-bucket.json` | Niegan tráfico sin TLS |
| `s3-cifrado.json` | Cifrado por defecto SSE-KMS de ambos buckets |
| `s3-archivos-ciclo-vida.json` | Expira archivos de estudiantes (debe coincidir con `ARCHIVO_RETENCION_DIAS`) |
| `s3-respaldos-ciclo-vida.json` | Expira respaldos a los 30 días |
| `github-oidc-confianza.json` + `github-oidc-politica.json` | Solo si usas `.github/workflows/deploy.yml` |

Notas:

- `ec2:DescribeInstances`, `ssm:DescribeInstanceInformation` y `ssm:GetCommandInvocation` no
  admiten restricción por recurso; por eso llevan `"*"`.
- Ninguna política tiene permisos de EC2 para la instancia misma ni llaves de acceso estáticas.
- `kms:CreateGrant` en el despertador y en el scheduler: al encender una instancia cuyo disco está
  cifrado con una clave administrada por el cliente, quien llama a `StartInstances` necesita
  poder crear la concesión para EC2 (**pendiente de verificar** en la documentación vigente de
  EBS; si la instancia pasa de `pending` a `stopped` al encenderla, es esto).
- `ses:FromAddress` debe coincidir con `CORREO_REMITENTE`.
