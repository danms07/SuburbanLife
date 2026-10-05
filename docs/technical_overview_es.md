# Suburban Life — Descripción Técnica General

*Última actualización: Septiembre de 2026*

---

## Tabla de Contenidos

1. [Resumen Ejecutivo](#1-resumen-ejecutivo)
2. [¿Qué Hace Suburban Life?: Funcionalidades Clave por Rol de Usuario](#2-qué-hace-suburban-life-a67ab-funcionalidades-clave-por-rol-de-usuario)
   - [2.1 Para Residentes y Miembros del Hogar](#21-para-residentes-y-miembros-del-hogar)
   - [2.2 Para Personal de Seguridad y Casetas de Acceso](#22-para-personal-de-seguridad-y-casetas-de-acceso)
   - [2.3 Para Administradores](#23-para-administradores)
3. [Pila Tecnológica: Construido con Flutter](#3-pila-tecnológica-construido-con-flutter)
   - [3.1 ¿Qué es Flutter?](#31-qué-es-flutter)
   - [3.2 ¿Por qué Elegir Flutter para Suburban Life?](#32-por-qué-elegir-flutter-para-suburban-life-a67ab)
4. [Infraestructura en la Nube: Servicios de Firebase en Acción](#4-infraestructura-en-la-nube-servicios-de-firebase-en-acción)
   - [4.1 Firebase Authentication (Identidad y Roles)](#41-firebase-authentication-identidad-y-roles)
   - [4.2 Cloud Firestore (Base de Datos en Tiempo Real)](#42-cloud-firestore-base-de-datos-en-tiempo-real)
   - [4.3 Firebase Cloud Storage (Almacenamiento Seguro de Archivos)](#43-firebase-cloud-storage-almacenamiento-seguro-de-archivos)
   - [4.4 Cloud Functions para Firebase (Lógica del Servidor)](#44-cloud-functions-para-firebase-lógica-del-servidor)
   - [4.5 Firebase App Check](#45-firebase-app-check)
   - [4.6 Firebase Hosting y Actualizaciones Automáticas Web](#46-firebase-hosting-y-actualizaciones-automáticas-web)
   - [4.7 Firebase Crashlytics y Telemetría](#47-firebase-crashlytics-y-telemetría)
5. [Medidas de Seguridad y Arquitectura de Protección](#5-medidas-de-seguridad-y-arquitectura-de-protección)
   - [5.1 Firebase Authentication y Control de Acceso Basado en Roles (RBAC)](#51-firebase-authentication-y-control-de-acceso-basado-en-roles-rbac)
   - [5.2 Reglas Declarativas de Seguridad (Firestore y Cloud Storage)](#52-reglas-declarativas-de-seguridad-firestore-y-cloud-storage)
   - [5.3 Restricciones de Claves API a Nivel de Aplicación](#53-restricciones-de-claves-api-a-nivel-de-aplicación)
   - [5.4 Protección contra Ataques de Reenvío (Replay Protection) en Cloud Functions](#54-protección-contra-ataques-de-reenvío-replay-protection-en-cloud-functions)
   - [5.5 App Check con reCAPTCHA Enterprise y Atestación de Dispositivos](#55-app-check-con-recaptcha-enterprise-y-atestación-de-dispositivos)
6. [Recopilación, Procesamiento y Privacidad de Datos](#6-recopilación-procesamiento-y-privacidad-de-datos)
   - [6.1 ¿Qué Información se Recopila?](#61-qué-información-se-recopila)
   - [6.2 ¿Cómo se Procesa y Utiliza la Información?](#62-cómo-se-procesa-y-utiliza-la-información)
   - [6.3 Cumplimiento Normativo y Derechos ARCO (LFPDPPP)](#63-cumplimiento-normativo-y-derechos-arco-lfpdppp)
   - [6.4 Eliminación de Cuenta y Purga de Datos](#64-eliminación-de-cuenta-y-purga-de-datos)
7. [Resumen y Confiabilidad Operativa](#7-resumen-y-confiabilidad-operativa)

---

## 1. Resumen Ejecutivo

**Suburban Life** es una plataforma integral para la gestión residencial de condominios, fraccionamientos privados y comunidades cerradas.

Al integrar a **Residentes**, **Personal de Seguridad** y **Administradores del Condominio** en un único ecosistema digital seguro y accesible, Suburban Life sustituye las bitácoras físicas de papel, los grupos de mensajería desorganizados y las hojas de cálculo manuales por un flujo de trabajo digital automatizado, transparente y confiable.

Este documento ofrece una visión técnica estructurada y redactada en un lenguaje claro para usuarios no técnicos (miembros del comité vecinal, administradores, residentes y personal directivo), explicando el funcionamiento del sistema, las tecnologías que lo respaldan, las múltiples capas de seguridad implementadas y el tratamiento responsable de la privacidad.

---

## 2. ¿Qué Hace Suburban Life?: Funcionalidades Clave por Rol de Usuario

Suburban Life ofrece interfaces y herramientas diseñadas a la medida para tres perfiles de usuario principales:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Suburban Life                               │
│                         Plataforma Residencial                          │
└──────────────┬──────────────────────────┬───────────────────────────────┘
               │                          │
               ▼                          ▼
┌───────────────────────────┐ ┌───────────────────────────┐ ┌─────────────▼───────────────┐
│   Residentes y Familiares │ │    Caseta de Seguridad    │ │   Administración Condominal │
│  • Pases QR de Invitados  │ │  • Escaneo Rápido de QR   │ │  • Directorio de Casas/User │
│  • Reserva de Amenidades  │ │  • Fotos de ID y Placas   │ │  • Aprobación de Pagos      │
│  • Carga de Comprobantes  │ │  • Bitácora en Vivo       │ │  • Validación de Propiedad  │
│  • Avisos Comunitarios    │ │  • Decisión Permitir/Nego │ │  • Configuración Amenidades │
│  • Portal de Transparencia│ └───────────────────────────┘ │  • Avisos Multilingües IA   │
│  • Invitación a Familia   │                               │  • Importación CSV y SMTP   │
└───────────────────────────┘                               └─────────────────────────────┘
```

### 2.1 Para Residentes y Miembros del Hogar

* **Pases Digitales de Acceso QR**: Los residentes pueden generar códigos QR al instante para visitantes esperados, familiares recurrentes o proveedores de servicios y paquetería. Los pases pueden configurarse como **de un solo uso** o **temporales (con fecha y hora de vencimiento específicas)**, agregando datos opcionales del vehículo (automóvil, motocicleta, número de placa) y número de pasajeros.
* **Reserva de Amenidades y Áreas Comunes**: Los residentes pueden consultar y reservar espacios compartidos (salón de eventos, alberca, asadores o equipo recreativo). El sistema valida la disponibilidad en tiempo real para evitar empalmes de horarios y gestiona los flujos de aprobación.
* **Seguimiento de Cuotas de Mantenimiento y Carga de Comprobantes**: Los residentes pueden verificar el estado de su cuenta (Al día / Pagado, Pendiente, En Revisión o Restringido), consultar el historial mensual de cuotas y subir fotografías de fichas de depósito o transferencias bancarias (próximamente) directamente desde la cámara o galería del teléfono.
* **Tablero de Avisos Comunitarios**: Un muro interactivo muestra comunicados oficiales de la administración con imágenes de alta resolución, formato destacado y traducción automática bilingüe (español e inglés).
* **Portal de Transparencia Documental**: Un explorador de archivos virtual integrado permite a los residentes autorizados consultar reglamentos internos, minutas de asambleas, estados financieros y calendarios de obras con soporte para guardado en memoria local sin re-descargas innecesarias.
* **Gestión de Familiares y Roommates**: El propietario titular puede invitar a cohabitantes o familiares a su grupo residencial mediante escaneo de código QR o por correo electrónico, permitiendo que todos los habitantes de la vivienda generen pases de acceso manteniendo una sola cuenta de cuotas unificada por dirección.

### 2.2 Para Personal de Seguridad y Casetas de Acceso

* **Escáner QR de Alta Velocidad**: Los oficiales en caseta pueden escanear el código QR presentado por el visitante utilizando la cámara de su dispositivo móvil o tableta.
* **Validación de Identidad en el Servidor**: El sistema comprueba de inmediato si el pase QR está activo y si se encuentra dentro de su ventana de vigencia autorizada.
* **Captura Fotográfica de Identificación y Placa**: El guardia puede tomar fotografías de respaldo de la credencial de identificación del visitante y de las placas del vehículo antes de autorizar el ingreso.
* **Bitácora Inmutable de Accesos**: Cada escaneo genera un registro digital con marca de tiempo exacta que detalla el nombre del visitante, la dirección del anfitrión, el guardia en turno, la resolución de acceso (Permitido o Denegado) y las fotografías de respaldo adjuntas.

### 2.3 Para Administradores

* **Directorio Residencial y Mapeo de Viviendas**: Permite buscar y filtrar a todos los residentes en toda la base de datos por nombre, correo electrónico o calle/número, con filtros por calle y herramientas para cambiar roles o restablecer contraseñas, además de lotes de 20 cuentas para navegación sin filtros.
* **Historial y Bitácora de Accesos**: Permite realizar búsquedas en todo el historial de la base de datos utilizando filtros por dirección física, rangos de fechas, categoría de visitante y búsqueda por nombre, placas, anfitrión o guardia, además de navegación en lotes de 20 eventos para exploración sin filtros.
* **Validación de Títulos y Entrega de Propiedades**: Los administradores revisan las actas de entrega o escrituras enviadas por nuevos residentes para validar la posesión legal antes de otorgar privilegios de titular residencial.
* **Aprobación de Comprobantes y Matriz Financiera**: El equipo administrativo revisa los pagos subidos, aprueba o rechaza comprobantes con retroalimentación y exporta la matriz de cobranza mensual completa en formato CSV para la contabilidad del condominio.
* **Carga Masiva de Datos mediante CSV**: Facilita la creación masiva de cientos de direcciones o cuentas de residentes en segundos a través de archivos de hoja de cálculo (CSV), generando contraseñas seguras y enviando correos de bienvenida automáticamente.
* **Configuración Dinámica de Amenidades**: Permite dar de alta espacios comunes, definir si son de uso exclusivo o de capacidad múltiple, establecer horarios y aplicar reglas de reserva.
* **Publicación de Avisos Asistida por Inteligencia Artificial**: Los administradores pueden redactar boletines en español o inglés; el sistema traduce automáticamente los títulos y contenidos mediante Google Gemini AI sin exponer claves confidenciales.
* **Servicio de Correo SMTP Personalizado**: Envío automatizado de credenciales de acceso e información de bienvenida a través del servidor de correo institucional del condominio.

---

## 3. Pila Tecnológica: Construido con Flutter

Suburban Life está desarrollado utilizando **Flutter**, el framework multiplataforma de código abierto creado por Google.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Código Único en Flutter (Dart)                      │
└──────────────┬──────────────────────────┬───────────────────────────────┘
               │                          │
               ▼                          ▼
┌───────────────────────────┐ ┌───────────────────────────┐ ┌─────────────▼───────────────┐
│    Aplicación Android     │ │      Aplicación iOS       │ │     Aplicación Web          │
│   (Google Play / APK)     │ │        (App Store)        │ │  (Navegadores de Escritorio)│
└───────────────────────────┘ └───────────────────────────┘ └─────────────────────────────┘
```

### 3.1 ¿Qué es Flutter?

Flutter permite programar la aplicación una sola vez utilizando el lenguaje **Dart** y compilarla de forma nativa para **Android**, **iOS** y **Navegadores Web**.

A diferencia de las soluciones web empaquetadas tradicionales que dependen de motores de navegación lentos, Flutter dibuja cada componente de la pantalla directamente a través de motores gráficos nativos de alto rendimiento (Skia e Impeller), logrando transiciones fluidas, animaciones ágiles y un comportamiento idéntico al de una aplicación nativa.

### 3.2 ¿Por qué Elegir Flutter para Suburban Life?

1. **Disponibilidad Multiplataforma Real**: Los usuarios acceden a Suburban Life desde teléfonos Android, iPhones, iPads o navegadores de computadora con la misma experiencia visual y operativa.
2. **Equidad Total de Funcionalidades**: Al contar con una sola base de código, las nuevas funciones, parches de seguridad y mejoras se publican al mismo tiempo en todas las plataformas.
3. **Diseño Responsivo Adaptable**: La interfaz se adapta automáticamente a pantallas pequeñas de celulares, pantallas medianas de tabletas en caseta y monitores panorámicos en las oficinas administrativas.
4. **Resiliencia Fuera de Línea (Offline)**: Datos clave como comunicados recientes y documentos del condominio se almacenan en el caché local del dispositivo, permitiendo operar incluso en casetas con señal intermitente.
5. **Actualizaciones Web Transparentes**: La versión web integra un servicio de detección de versiones en segundo plano (`AppUpdateService`) que actualiza la aplicación de forma automática e imperceptible cuando el usuario está inactivo o cambia de pestaña.

> [!NOTE]
> **Aviso sobre Distribución en Tiendas de Aplicaciones (App Stores)**:
> Aunque existen versiones nativas para **Android** e **iOS** desarrolladas y funcionales dentro del proyecto, su publicación y distribución oficial en **Google Play Store** y **Apple App Store** requiere de cuentas de desarrollador institucionales (con sus respectivos costos de suscripción y registro). La decisión sobre la adquisición de dichas cuentas y la asignación del presupuesto correspondiente debe ser presentada y aprobada formalmente en **Asamblea de Condóminos**. Mientras tanto, la plataforma se encuentra 100% operativa y accesible para todos los residentes, guardias y administradores a través de la aplicación Web móvil y de escritorio.

---

## 4. Infraestructura en la Nube: Servicios de Firebase en Acción

Suburban Life utiliza la infraestructura en la nube de **Google Firebase**, garantizando alta disponibilidad, sincronización instantánea y cero necesidad de mantenimiento de servidores físicos.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Nube de Suburban Life (Firebase)                  │
├───────────────────┬───────────────────┬────────────────┬────────────────┤
│   Firebase Auth   │  Cloud Firestore  │ Cloud Storage  │ Cloud Functions│
│ (Identidad/Roles) │ (NoSQL en Vivo)   │(Archivos S3)   │ (Lógica Nube)  │
├───────────────────┼───────────────────┼────────────────┼────────────────┤
│     App Check     │ Firebase Hosting  │  Crashlytics   │ Google Gemini  │
│(Filtro Antifraude)│  (CDN Mundial)    │ (Diagnósticos) │  (Vertex AI)   │
└───────────────────┴───────────────────┴────────────────┴────────────────┘
```

### 4.1 Firebase Authentication (Identidad y Roles)
* **Función**: Actúa como el centro digital de autenticación e identidad.
* **Operación**: Administra el inicio de sesión, el cifrado de contraseñas, la recuperación de credenciales y la emisión de credenciales de rol criptográficas (`admin`, `guard`, `resident`).

### 4.2 Cloud Firestore (Base de Datos en Tiempo Real)
* **Función**: Base de datos NoSQL distribuida en la nube que sincroniza la información en milisegundos en todos los dispositivos conectados.
* **Colecciones Principales**:
  * `users`: Perfiles de residentes, guardias y administradores.
  * `addresses`: Catálogo de viviendas, propietarios vinculados y estatus de cuota mensual.
  * `qr_codes`: Pases de acceso generados, nombres de invitados y vigencias.
  * `bookings`: Calendario de reservas de áreas comunes y estados de aprobación.
  * `announcements`: Boletines comunitarios, imágenes y traducciones bilingües.
  * `documents` y `document_folders`: Estructura jerárquica de archivos normativos y financieros.
  * `access_logs`: Historial de accesos en caseta con fotos y registros de guardia.
  * `payments`: Comprobantes de pago cargados, periodos mensuales (`AAAA-MM`) e importes.
  * `ownership_claims`: Solicitudes de vinculación de propiedad en revisión.
  * `facilities`: Catálogo de amenidades configurables.
  * `config`: Parámetros de corte de pago, días de gracia y configuración del Administrador.

### 4.3 Firebase Cloud Storage (Almacenamiento Seguro de Archivos)
* **Función**: Bóveda de almacenamiento de archivos en la nube con cifrado en reposo.
* **Operación**: Almacena documentos de acreditación de propiedad, comprobantes de pago de mantenimiento, fotografías de identificación y placas tomadas en caseta, archivos de transparencia e imágenes de avisos.

### 4.4 Cloud Functions para Firebase (Lógica del Servidor)
* **Función**: Ejecuta procesos de negocio críticos en contenedores aislados en el servidor, garantizando que operaciones sensibles no dependan del dispositivo del usuario:
  * **Validación Atómica de Accesos QR** (`validateAndRegisterQrAccess`): Verifica reglas de acceso y escribe el registro en la bitácora en una única transacción protegida.
  * **Traducción Automática con IA** (`translateAnnouncement`): Conecta de forma segura y sin claves manuales con Google Vertex AI (Gemini) para traducir boletines entre español e inglés.
  * **Recalculación Automática de Estatus de Pago** (`onPaymentWritten`): Actualiza el estatus de la vivienda inmediatamente después de que un administrador aprueba un comprobante.
  * **Creación Masiva de Residentes y Direcciones** (`adminBulkImportResidents`, `adminBulkImportAddresses`): Procesa archivos CSV en el servidor, asignando roles y generando contraseñas seguras.
  * **Despacho de Correos Institucionales**: Se comunica de forma segura con el servidor SMTP para enviar contraseñas y avisos de bienvenida.

### 4.5 Firebase App Check
* **Función**: Cortafuegos de seguridad que garantiza que las solicitudes a la base de datos y al servidor provengan exclusivamente de la aplicación oficial y no de programas maliciosos o atacantes externos.

### 4.6 Firebase Hosting y Actualizaciones Automáticas Web
* **Función**: Red de distribución de contenido (CDN) global con cifrado SSL/HTTPS para la versión web, asegurando tiempos de carga inmediatos y actualización automática de nuevas versiones.

### 4.7 Firebase Crashlytics y Telemetría
* **Función**: Monitor de salud técnica que registra fallas inesperadas y métricas de estabilidad para que el equipo de soporte técnico solucione cualquier eventualidad con rapidez.

---

## 5. Medidas de Seguridad y Arquitectura de Protección

La seguridad y la confidencialidad de la información son pilares fundamentales de Suburban Life. El sistema aplica un esquema de **defensa en profundidad**, donde los datos están resguardados por múltiples capas independientes de protección.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     5 Capas de Seguridad Integradas                     │
├─────────────────────────────────────────────────────────────────────────┤
│ 1. Atestación de App    │ App Check con reCAPTCHA Enterprise            │
├─────────────────────────┼───────────────────────────────────────────────┤
│ 2. Blindaje de Claves   │ Restricciones de API por Plataforma           │
├─────────────────────────┼───────────────────────────────────────────────┤
│ 3. Identidad Segura     │ Firebase Auth con Roles Criptográficos (RBAC) │
├─────────────────────────┼───────────────────────────────────────────────┤
│ 4. Antirreenvío (Replay)│ Consumo de Token de Un Solo Uso en Funciones  │
├─────────────────────────┼───────────────────────────────────────────────┤
│ 5. Control de Acceso BD │ Reglas Declarativas en Firestore y Storage    │
└─────────────────────────┴───────────────────────────────────────────────┘
```

### 5.1 Firebase Authentication y Control de Acceso Basado en Roles (RBAC)

* **Políticas de Contraseña Rigurosas**: El sistema exige contraseñas seguras (mínimo 8 caracteres, requiriendo al menos una letra mayúscula, una minúscula, un dígito numérico y un símbolo especial). En las importaciones masivas, el servidor genera de forma automática contraseñas aleatorias criptográficas de 12 caracteres.
* **Privilegios Asignados en el Servidor (Custom Claims)**: Los roles de usuario no son simples campos en una base de datos que puedan ser manipulados localmente. Se emiten como **Claims Criptográficos** firmados por el servidor (`{ admin: true }`, `{ guard: true }`, `{ resident: true }`), los cuales son verificados en cada lectura, escritura y ejecución de funciones.

### 5.2 Reglas Declarativas de Seguridad (Firestore y Cloud Storage)

La seguridad de Suburban Life reside **en los servidores de la nube**, no en el teléfono del usuario. Aunque alguien intente modificar el código de la app en su dispositivo, las reglas del servidor rechazan cualquier acción indebida:

* **Principio de Privilegio Mínimo**:
  * Los **Residentes** solo pueden ver su perfil personal, los pases QR de su domicilio, sus propios comprobantes de pago y los avisos comunitarios.
  * Los **Residentes no pueden** modificar su propio rol, cambiar el estatus de pago de su casa, ver comprobantes de otros vecinos ni alterar las bitácoras de acceso.
  * El **Personal de Seguridad** solo puede consultar la validez de los pases QR y registrar entradas, sin acceso a información financiera, cambio de contraseñas ni configuración del sistema.
  * Los **Administradores** cuentan con permisos validados para aprobar residentes, verificar pagos y administrar el condominio.
* **Protección de Archivos**: Los comprobantes de pago, identificaciones de visitantes y escrituras se almacenan en carpetas privadas no indexables públicamente, requiriendo autenticación y permisos válidos para su visualización.
* **Aislamiento de Configuraciones Críticas**: Credenciales sensibles como contraseñas SMTP del correo están restringidas exclusivamente a administradores verificados.

### 5.3 Restricciones de Claves API a Nivel de Aplicación

Toda aplicación móvil moderna utiliza claves de API de Google Cloud para comunicarse con su proyecto en la nube. Para evitar que terceros extraigan estas claves y las usen fuera del sistema, **las claves de Suburban Life están estrictamente restringidas en Google Cloud**:

* **Restricción en Android**: La clave de Android está limitada al identificador único del paquete (`com.example.suburban_life`) y a la huella digital del certificado de firma SHA-1 del desarrollador. Peticiones de cualquier otra app o dispositivo son rechazadas al instante.
* **Restricción en iOS**: La clave de iOS está bloqueada exclusivamente para el Bundle Identifier oficial (`com.example.suburban_life`).
* **Restricción en Web**: La clave Web está restringida a los dominios y orígenes web autorizados (`suburban-life-a67ab.web.app` y dominios del condominio). Peticiones provenientes de sitios ajenos o herramientas externas (como Postman o curl) son bloqueadas automáticamente.

### 5.4 Protección contra Ataques de Reenvío (Replay Protection) en Cloud Functions

Un **ataque de reenvío (replay attack)** ocurre cuando un usuario malintencionado intercepta una solicitud de red legítima y la envía repetidamente (por ejemplo, intentando usar un pase de acceso vencido por segunda vez o duplicando un movimiento).

Para prevenir esta vulnerabilidad:
* Las funciones del servidor están configuradas con **`consumeAppCheckToken: true`**.
* La aplicación en Flutter invoca las funciones utilizando **`limitedUseAppCheckToken: true`**.
* **Mecanismo de acción**: Cada vez que se realiza una operación importante, el sistema genera un token de seguridad de un solo uso. Al procesar la solicitud, el servidor **consume e invalida el token inmediatamente**. Si un atacante intercepta la petición e intenta reenviarla, el servidor la rechaza automáticamente por carecer de un token válido.

### 5.5 App Check con reCAPTCHA Enterprise y Atestación de Dispositivos

**Firebase App Check** previene el acceso de robots, scripts automatizados y herramientas de extracción masiva de datos:

* **Versión Web (reCAPTCHA Enterprise)**: Analiza señales de navegación de forma transparente sin obligar a los residentes a resolver acertijos visuales, confirmando que la interacción proviene de una persona real en el dominio web oficial.
* **Dispositivos Android (reCAPTCHA Enterprise)**: Evalúa señales de riesgo y la autenticidad del cliente a través del proveedor de reCAPTCHA Enterprise para Android, bloqueando accesos no autorizados y scripts automatizados.
* **Dispositivos iOS (DeviceCheck y Apple App Attest)**: Valida criptográficamente que la app esté corriendo en un dispositivo Apple genuino y sin alteraciones.

---

## 6. Recopilación, Procesamiento y Privacidad de Datos

### 6.1 ¿Qué Información se Recopila?

Para prestar los servicios de control de acceso, administración condominal y seguridad, la aplicación recopila:

| Categoría | Datos Específicos | Finalidad |
| :--- | :--- | :--- |
| **Datos de Cuenta** | Nombre completo, correo electrónico, contraseña cifrada, rol asignado. | Autenticación y asignación de permisos según el perfil. |
| **Información de Inmueble** | Nombre de calle, número de casa, vivienda vinculada. | Vincular al usuario con su domicilio físico en el condominio. |
| **Acreditación de Propiedad** | Fotos de escrituras o actas de entrega, fecha de entrega de la casa. | Validar la posesión legal antes de otorgar permisos de titular. |
| **Registros Financieros** | Comprobantes de pago (imágenes), montos, fechas y periodos de cuota. | Conciliación de cuotas de mantenimiento y actualización de saldos. |
| **Control de Visitas** | Nombres de invitados, tipo de vehículo, placas, horarios autorizados. | Generación de pases QR de acceso y preautorización en caseta. |
| **Bitácora de Caseta** | Marcas de tiempo de ingreso, resultado (Permitido/Denegado), fotos de identificación o placa. | Preservar la seguridad comunitaria y contar con auditoría de accesos. |
| **Telemetría Técnica** | Registros de fallas anónimos y diagnósticos de rendimiento (Crashlytics/Analytics). | Identificar errores de software, prevenir cierres imprevistos y optimizar la app. |

### 6.2 ¿Cómo se Procesa y Utiliza la Información?

* **Finalidad Exclusiva**: La información personal se utiliza únicamente para la gobernanza residencial, la seguridad en casetas de control y la gestión contable del condominio.
* **No Comercialización**: Suburban Life **nunca** vende, renta ni comercializa datos personales con terceros, anunciantes o agencias publicitarias.
* **Uso Seguro de Inteligencia Artificial**: Las traducciones automáticas con Google Vertex AI (Gemini) se aplican únicamente sobre el texto de los comunicados comunitarios públicos. **Ningún dato personal de usuarios, registros contables o documentos privados se envía a modelos de IA.**

### 6.3 Cumplimiento Normativo y Derechos ARCO (LFPDPPP)

En apego a la legislación mexicana de protección de datos personales (**LFPDPPP**), cada titular conserva el control sobre su información mediante sus **Derechos ARCO**:

* **Acceso**: Conocer qué datos personales suyos existen en el sistema y el tratamiento que se les da.
* **Rectificación**: Solicitar la corrección o actualización de información inexacta o incompleta.
* **Cancelación**: Solicitar que sus datos personales y documentos sean dados de baja de los registros del sistema.
* **Oposición**: Oponerse al uso de sus datos para fines específicos no esenciales.

El ejercicio de los Derechos ARCO puede realizarse ante la Administración del Condominio o directamente desde el panel de perfil en la aplicación.

### 6.4 Eliminación de Cuenta y Purga de Datos

* **Mecanismos de Eliminación**: El usuario puede solicitar la eliminación de su cuenta en cualquier momento mediante el botón **"Eliminar Cuenta"** dentro de la app o solicitándolo a la Administración.
* **Purga Definitiva e Irreversible**: Al ejecutarse la eliminación, las credenciales en Firebase Authentication, el registro del usuario en Cloud Firestore y sus archivos de acreditación en Cloud Storage son **destruidos de forma permanente e irrecuperable**.

---

## 7. Resumen y Confiabilidad Operativa

| Objetivo | Solución Arquitectónica en Suburban Life |
| :--- | :--- |
| **Accesibilidad Total** | Base de código única en Flutter compatible con Android, iOS y Navegadores Web. |
| **Velocidad y Disponibilidad** | Base de datos Cloud Firestore con sincronización en vivo y funcionamiento offline. |
| **Gestión de Identidad** | Firebase Authentication con políticas de contraseñas robustas y roles criptográficos. |
| **Protección de Datos** | Reglas de seguridad en Firestore y Storage que garantizan acceso por privilegio mínimo. |
| **Blindaje de APIs** | Restricciones de claves en Google Cloud para Android (SHA-1/Paquete), iOS (Bundle ID) y Web (Orígenes HTTP). |
| **Protección contra Bots** | Firebase App Check con reCAPTCHA Enterprise y atestación de hardware (reCAPTCHA Enterprise / App Attest). |
| **Defensa Antirreenvío** | Consumo de token de un solo uso (`consumeAppCheckToken`) en todas las Cloud Functions. |
| **Privacidad y Cumplimiento** | Cumplimiento total de Derechos ARCO (LFPDPPP) y eliminación irreversible de cuentas. |

Suburban Life combina la versatilidad de las tecnologías móviles modernas con la solidez de la infraestructura en la nube de Google, ofreciendo a las comunidades residenciales una plataforma segura, confiable y fácil de usar.
