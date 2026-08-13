# Suburban Life — Manual de Usuario para Administradores

Bienvenido al **Manual de Usuario para Administradores de Suburban Life**. Este documento proporciona una guía operativa completa para administradores residenciales, administradores de propiedades y miembros de la junta directiva para gestionar la infraestructura comunitaria, el registro de residentes, la aprobación de pagos, el control de acceso y la reserva de amenidades.

---

## Índice

1. [Acceso al Sistema y Panel de Administración](#1-acceso-al-sistema-y-panel-de-administración)
2. [Gestión de Propiedades y Direcciones](#2-gestión-de-propiedades-y-direcciones)
   - [2.1 Importación Masiva de Direcciones vía CSV](#21-importación-masiva-de-direcciones-vía-csv)
   - [2.2 Directorio de Direcciones y Control de Estado](#22-directorio-de-direcciones-y-control-de-estado)
3. [Registro de Residentes y Gestión de Usuarios](#3-registro-de-residentes-y-gestión-de-usuarios)
   - [3.1 Creación Masiva de Residentes vía CSV](#31-creación-masiva-de-residentes-vía-csv)
   - [3.2 Registro Individual de Residentes y Coinquilinos](#32-registro-individual-de-residentes-y-coinquilinos)
   - [3.3 Aprobación de Solicitudes de Titularidad / Propiedad](#33-aprobación-de-solicitudes-de-titularidad--propiedad)
   - [3.4 Directorio de Usuarios y Gestión de Roles](#34-directorio-de-usuarios-y-gestión-de-roles)
4. [Aprobaciones Financieras y Pagos](#4-aprobaciones-financieras-y-pagos)
   - [4.1 Revisión de Comprobantes de Pago y Recálculo de Estado](#41-revisión-de-comprobantes-de-pago-y-recálculo-de-estado)
   - [4.2 Registro de Pagos a Nombre de Residentes](#42-registro-de-pagos-a-nombre-de-residentes)
   - [4.3 Reportes Matriz de Pago en CSV](#43-reportes-matriz-de-pago-en-csv)
5. [Seguridad y Control de Acceso](#5-seguridad-y-control-de-acceso)
   - [5.1 Gestión de Cuentas de Guardias de Seguridad](#51-gestión-de-cuentas-de-guardias-de-seguridad)
   - [5.2 Generador de Pases QR Administrativos](#52-generador-de-pases-qr-administrativos)
6. [Gestión de Amenidades e Instalaciones](#6-gestión-de-amenidades-e-instalaciones)
   - [6.1 Configurador Dinámico de Amenidades](#61-configurador-dinámico-de-amenidades)
   - [6.2 Reglas de Capacidad y Tiempo de Espera (Cooldown)](#62-reglas-de-capacidad-y-tiempo-de-espera-cooldown)
7. [Configuración del Sistema y Reglas](#7-configuración-del-sistema-y-reglas)
   - [7.1 Día de Corte de Mantenimiento y Días de Gracia](#71-día-de-corte-de-mantenimiento-y-días-de-gracia)
8. [Anuncios Comunitarios y Traducción con IA](#8-anuncios-comunitarios-y-traducción-con-ia)

---

## 1. Acceso al Sistema y Panel de Administración

Los administradores inician sesión utilizando credenciales configuradas con la marca de acceso personalizado (custom claim) **`admin`** (`{ admin: true }`).

### Vista General del Panel de Administración
Al iniciar sesión, los administradores ingresan al **Panel de Administración**, el cual incluye:
* **Insignias de Estado en Tiempo Real**: Contadores dinámicos sobre los botones de acción ("Aprobar Residentes", "Revisar Pagos") que muestran en tiempo real las solicitudes pendientes de revisión.
* **Cuadrícula de Navegación**: Acceso directo a todos los módulos administrativos.
* **Menú Lateral de Acceso Rápido**: Menú desplegable para cambiar de pantalla o acceder a la configuración.

---

## 2. Gestión de Propiedades y Direcciones

Antes de que los residentes puedan vincular sus cuentas a una vivienda física, las direcciones deben existir en la base de datos.

### 2.1 Importación Masiva de Direcciones vía CSV
Para inicializar o ampliar el directorio de viviendas, los administradores pueden importar calles y números de casas de forma masiva utilizando un archivo CSV.

* **Navegación**: Panel $\rightarrow$ **Importación Masiva de Direcciones (CSV)** (`AdminBulkAddressImportScreen`).
* **Formato del Archivo CSV**:
  ```csv
  streetName,initialNumber,finalNumber,exclusions
  "Avenida Olmos",1,50,"12,14"
  "Calle Robles",10,30,""
  "Paseo del Valle",101,120,"105,115"
  ```

#### Descripción de Campos:
* **`streetName`**: Nombre completo de la calle o avenida.
* **`initialNumber`**: Número inicial del rango de viviendas (ej. `1`).
* **`finalNumber`**: Número final del rango de viviendas (ej. `50`).
* **`exclusions`**: Lista separada por comas de números de casas a omitir (ej. `"12,14"`).

#### Pasos para Importar:
1. Presione **Copiar Plantilla CSV** para copiar una estructura de ejemplo al portapapeles, o prepare un archivo `.csv`.
2. Presione **Subir Archivo CSV** y seleccione su documento.
3. Revise la **Vista Previa de Rangos de Direcciones** que muestra los números generados y las exclusiones.
4. Presione **Importar Direcciones**. El sistema creará los registros en transacciones por lotes y mostrará un resumen del proceso.

---

## 3. Registro de Residentes y Gestión de Usuarios

### 3.1 Creación Masiva de Residentes vía CSV
Permite a los administradores crear múltiples cuentas de residentes sin necesidad de que estos envíen documentos de comprobante de propiedad manualmente.

* **Navegación**: Panel $\rightarrow$ **Creación Masiva de Usuarios (CSV)** (`AdminBulkUserImportScreen`).
* **Formato CSV**:
  ```csv
  name,email,password,street,number
  "Juan Pérez",juan.perez@ejemplo.com,,Avenida Olmos,101
  "María García",maria.garcia@ejemplo.com,ClaveSegura123!,Calle Robles,12
  ```

#### Características:
* **Permisos Inmediatos**: A las cuentas creadas se les asigna inmediatamente el permiso `{ resident: true }` y el rol `role: 'resident'`.
* **Contraseñas Temporales Deterministas**: Si la columna `password` se omite o se deja vacía, el sistema genera una contraseña temporal determinista: `Suburban#<localPartEmail>2026` (ej. `juan.perez@ejemplo.com` $\rightarrow$ `Suburban#juan.perez2026`).
* **Verificación de Dirección**: Si se especifica `street` y `number`, el sistema valida que la dirección exista en la base de datos, asigna el campo `residentUid` y actualiza el estado a `paymentStatus: 'paid'`. Si la dirección no existe en la base de datos, la fila es rechazada mostrando un mensaje de error claro.
* **Exportación de Resultados CSV**: Al finalizar, el administrador puede presionar **Descargar CSV de Resultados** o **Copiar CSV de Resultados** para guardar la lista con el estado de ejecución (`ok`/`error`), contraseñas asignadas y mensajes de error detallados.

### 3.2 Creación Unificada de Cuentas de Usuario
* **Navegación**: Panel $\rightarrow$ **Crear Usuario** (`AdminCreateUserScreen`).
* Proporciona una interfaz centralizada y dinámica para que los administradores den de alta cuentas en cualquier nivel del sistema:
  * **Selector de Tipo de Usuario**: Permite elegir entre **Residente** (por defecto), **Guardia de Seguridad** y **Administrador**.
  * **Cuentas de Residente**: Captura nombre, correo, contraseña (con generador automático) y selectores desplegables en cascada de calle y número con prevención de colisiones para vincular la vivienda de inmediato con permiso `{ resident: true }` y estado `paymentStatus: 'paid'`.
  * **Cuentas de Guardia de Seguridad**: Captura credenciales otorgando el permiso `{ guard: true }` para el escaneo de pases QR en casetas de acceso.
  * **Cuentas de Administrador**: Captura credenciales y vincula automáticamente la cuenta a la dirección comunitaria fija **"Oficina de administración"** (creando el registro de dirección automáticamente si aún no existe).
  * **Notificación de Bienvenida**: Si el servicio SMTP está activo, envía automáticamente un correo de bienvenida con las credenciales de inicio de sesión directamente al buzón del usuario.

### 3.3 Aprobación de Solicitudes de Titularidad / Propiedad
Cuando los residentes se registran por su cuenta en la aplicación móvil, envían fotografías de comprobantes de propiedad y la fecha de entrega de la vivienda.

* **Navegación**: Panel $\rightarrow$ **Aprobar Residentes** (`AdminResidentApprovalScreen`).
* **Proceso de Revisión**:
  1. Inspeccione la imagen del comprobante (escrituras o recibo de servicios).
  2. Verifique la fecha de entrega de la propiedad.
  3. Presione **Aprobar**: Asigna el permiso `{ resident: true }`, vincula la dirección, establece `paymentStatus: 'paid'` y guarda la fecha de entrega (`deliveryDate`).
  4. Presione **Rechazar**: Notifica al residente para que reenvíe un comprobante válido.

### 3.4 Directorio de Usuarios y Gestión de Roles
* **Navegación**: Panel $\rightarrow$ **Gestión de Usuarios** (`AdminUserManagementScreen`).
* **Tabla de Usuarios**: Muestra todas las cuentas registradas, UID de usuario, rol asignado y permisos activos.
* **Modificación de Roles**: Promueva o deggrade cuentas entre **Residente**, **Guardia de Seguridad** y **Administrador**.
* **Desvincular Dirección**: Desvincula una dirección si el residente se muda o cambia la titularidad.

---

## 4. Aprobaciones Financieras y Pagos

### 4.1 Revisión de Comprobantes de Pago y Recálculo de Estado
Los residentes suben sus comprobantes de mantenimiento mensual para mantenerse al día.

* **Navegación**: Panel $\rightarrow$ **Revisar Pagos** (`AdminPaymentApprovalScreen`).
* **Proceso de Revisión**:
  1. Visualice el comprobante cargado y el periodo correspondiente (ej. `2026-07`).
  2. Presione **Aprobar**: Marca el comprobante como aprobado, actualiza la fecha `lastPaymentApproval` y recalcula automáticamente el estado de la vivienda (`paid`, `pending` o `restricted`).
  3. Presione **Rechazar**: Permite ingresar un motivo de rechazo para notificar al residente.

### 4.2 Registro de Pagos a Nombre de Residentes
Permite registrar pagos manualmente cuando los residentes realizan pagos en efectivo o transferencia bancaria directa.

* **Navegación**: Panel $\rightarrow$ **Subir Pago a Nombre de Residente** (`AdminUploadPaymentScreen`).
* Seleccione la calle y el número mediante los desplegables en cascada.
* Suba la imagen del recibo y especifique el periodo correspondiente para actualizar el estado del inmueble inmediatamente.

### 4.3 Reportes Matriz de Pago en CSV
* **Navegación**: Panel $\rightarrow$ **Reportes de Pago** (`AdminPaymentReportScreen`).
* Seleccione el periodo inicial y final deseado.
* Presione **Exportar Matriz de Pagos CSV**: Descarga una hoja de cálculo completa con el estado de pago (`al día`, `pendiente`, `atrasado`) de cada vivienda en la comunidad.

---

## 5. Seguridad y Control de Acceso

### 5.1 Gestión de Cuentas de Guardias de Seguridad
El personal de vigilancia utiliza la app para escanear códigos QR de visitantes y registrar entradas.

* **Navegación**: Panel $\rightarrow$ **Gestionar Guardias** (`AdminGuardManagementScreen`).
* **Crear Guardia**: Genera cuentas asignando el permiso `{ guard: true }`.
* **Desactivar Guardia**: Elimina o revoca accesos de seguridad de inmediato.

### 5.2 Generador de Pases QR Administrativos
* **Navegación**: Panel $\rightarrow$ **Generar Acceso QR** (`QrGeneratorScreen`).
* Al iniciar sesión como administrador, la generación de pases QR asigna automáticamente la ubicación predeterminada **"Oficina de administración"**, permitiendo emitir pases de entrada a visitantes sin vincular una casa residencial personal.

---

## 6. Gestión de Amenidades e Instalaciones

### 6.1 Configurador Dinámico de Amenidades
Permite definir las áreas comunes de la comunidad (ej. Casa Club, Cancha de Tenis, Alberca, Asadores).

* **Navegación**: Panel $\rightarrow$ **Gestionar Amenidades** (`AdminFacilitiesScreen`).
* **Tipos de Amenidades**:
  * **Amenidad Única**: Capacidad de una sola reserva simultánea (ej. Casa Club).
  * **Amenidad Multi-ítem**: Capacidad para múltiples ítems o canchas (ej. 4 Canchas de Tenis o 10 Asadores).

### 6.2 Reglas de Capacidad y Tiempo de Espera (Cooldown)
Establece límites para asegurar un acceso equitativo a las instalaciones:
* **Unidades de Cooldown**: Defina el periodo de restricción en **Días**, **Meses**, **Años** o **Sin restricción**.
* **Aplicación de Reglas**: Evita que un residente vuelva a reservar la misma amenidad hasta que venza su periodo de espera.

---

## 7. Configuración del Sistema y Reglas

### 7.1 Día de Corte de Mantenimiento y Días de Gracia
* **Navegación**: Panel $\rightarrow$ **Configuración del Sistema** (`AdminSettingsScreen`).
* **Día de Corte**: Día del mes (ej. día `5`) en que vence la cuota de mantenimiento.
* **Días de Gracia**: Días de tolerancia (ej. `5 días`) antes de que el estado pase de `pendiente` a `restringido`.

### 7.2 Servicio de Correo SMTP y Notificaciones de Bienvenida
Permite configurar un servidor de correo SMTP propio para enviar credenciales automáticamente a los nuevos usuarios registrados.
* **Navegación**: Panel $\rightarrow$ **Configuración del Sistema** (`AdminSettingsScreen`) $\rightarrow$ **Servicio de Correo SMTP**.
* **Parámetros de Configuración**:
  * **Habilitar Correos de Bienvenida Automáticos**: Interruptor general para activar/desactivar el envío.
  * **Servidor Host y Puerto**: Dirección del servidor (ej. `smtp.gmail.com`) y presets de puertos (`587` TLS, `465` SSL, `25`).
  * **Interruptor SSL/TLS**: Activar para puerto 465 (SSL) o desactivar para STARTTLS (puerto 587).
  * **Autenticación**: Usuario/correo y contraseña (o contraseña de aplicación / API Key).
  * **Información del Remitente**: Correo remitente y nombre visible opcionales.
* **Prueba de Conexión Interactiva**: Permite ingresar un correo de destino y presionar **Probar Conexión y Enviar Correo** para validar el handshake y recibir un correo de prueba visualizando la plantilla personalizada.
* **Plantilla de Mensaje de Bienvenida Personalizada**:
  * **Asunto del Correo**: Línea de asunto personalizada compatible con `%appName%`.
  * **Cuerpo del Mensaje**: Editor de mensaje multilínea. Presione los chips de marcadores para insertar datos dinámicos:
    * `%name%`: Nombre completo del residente o guardia.
    * `%email%`: Correo de inicio de sesión.
    * `%password%`: Contraseña inicial asignada.
    * `%address%`: Dirección física vinculada (o N/A).
    * `%role%`: Rol asignado (ej. Residente o Guardia de Seguridad).
    * `%appName%`: Nombre de la aplicación / comunidad.
  * **Restablecer Plantilla**: Restaura la plantilla recomendada por defecto.
* **Envío Automático de Bienvenida**: Al estar habilitado, cada residente creado mediante **Importación Masiva CSV** o guardia dado de alta en **Gestionar Guardias** recibe un correo con su diseño personalizado y sus credenciales de acceso.

---

## 8. Anuncios Comunitarios y Traducción con IA

Permite publicar avisos e información oficial para toda la comunidad.

* **Navegación**: Menú Lateral $\rightarrow$ **Anuncios** (`AnnouncementsScreen`).
* **Traducción Bilingüe**: Integrado con la IA **Gemini**. Los anuncios publicados en español se traducen automáticamente al inglés (y viceversa) para garantizar una comunicación fluida.

---

*Fin del Manual de Usuario para Administradores.*
