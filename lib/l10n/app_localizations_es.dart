// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appName => 'Suburban Life';

  @override
  String get welcome => 'Bienvenido a Suburban Life';

  @override
  String welcomeUser(String name) {
    return '¡Hola, $name!';
  }

  @override
  String get bookFacility => 'Reservar amenidades';

  @override
  String get transparencyDocs => 'Documentos de Transparencia';

  @override
  String get monthlyPayment => 'Pago Mensual';

  @override
  String get logout => 'Cerrar sesión';

  @override
  String get login => 'Iniciar sesión';

  @override
  String get email => 'Correo electrónico';

  @override
  String get password => 'Contraseña';

  @override
  String get loginSuccess => 'Inicio de sesión exitoso';

  @override
  String get loginFailed => 'Inicio de sesión fallido';

  @override
  String get scanQr => 'Escanear acceso QR';

  @override
  String get generateQr => 'Generar QR de acceso';

  @override
  String get type => 'Tipo';

  @override
  String get expires => 'Vence';

  @override
  String get facilityBooking => 'Reserva de Amenidades';

  @override
  String get reserveFacility => 'Reservar una instalación';

  @override
  String get selectFacility => 'Seleccionar instalación';

  @override
  String get confirmBooking => 'Confirmar reserva';

  @override
  String get upcomingBookings => 'Próximas reservas';

  @override
  String get date => 'Fecha';

  @override
  String get from => 'Desde';

  @override
  String get to => 'Hasta';

  @override
  String get noBookings => 'No hay próximas reservas para esta instalación.';

  @override
  String get filterByCategory => 'Filtrar por categoría: ';

  @override
  String get noDocuments => 'No hay documentos disponibles en esta categoría.';

  @override
  String get maintenancePayment => 'Pago de Mantenimiento';

  @override
  String get monthlyQuota => 'Cuota Mensual de Mantenimiento';

  @override
  String get currentStatus => 'Estado Actual';

  @override
  String get takePhotoReceipt => 'Tomar foto del recibo';

  @override
  String get receiptNotice =>
      'Nota: Solo se permiten capturas directas con la cámara de los recibos de mantenimiento para garantizar la autenticidad.';

  @override
  String get announcements => 'Anuncios';

  @override
  String get createAnnouncement => 'Crear Anuncio';

  @override
  String get titleSpanish => 'Título (Español)';

  @override
  String get contentSpanish => 'Contenido (Español)';

  @override
  String get cancel => 'Cancelar';

  @override
  String get create => 'Crear';

  @override
  String get errorAnnouncements => 'Error al cargar los anuncios';

  @override
  String get noAnnouncements => 'Aún no hay anuncios';

  @override
  String get attachImage => 'Adjuntar Imagen';

  @override
  String get pasteFromClipboard => 'Pegar del portapapeles';

  @override
  String get changeImage => 'Cambiar Imagen';

  @override
  String get removeImage => 'Eliminar Imagen';

  @override
  String get imagePastedSuccess => '¡Imagen adjuntada desde el portapapeles!';

  @override
  String get noImageInClipboard =>
      'No se encontró ninguna imagen en el portapapeles. Copia una imagen primero.';

  @override
  String get pasteImageHint =>
      'O presiona Ctrl+V / Cmd+V para pegar una imagen';

  @override
  String get emojisLabel => 'Emojis Rápidos:';

  @override
  String get insertEmojiHint => 'Toca un emoji para insertarlo en el mensaje';

  @override
  String get viewFullImage => 'Ver Imagen';

  @override
  String imageUploadError(String error) {
    return 'Error al subir la imagen: $error';
  }

  @override
  String get announcementCreatedSuccess => '¡Anuncio publicado con éxito!';

  @override
  String get fillRequiredFields =>
      'Por favor completa tanto el título como el contenido.';

  @override
  String get multipurposeRoom => 'Salón de Usos Múltiples';

  @override
  String get bicycle1 => 'Bicicleta 1';

  @override
  String get roofGarden => 'Roof Garden';

  @override
  String get noticesGrid => 'Avisos';

  @override
  String get transparencyGrid => 'Transparencia';

  @override
  String get generateQrGrid => 'Generar QR';

  @override
  String get familyGroupGrid => 'Grupo Familiar';

  @override
  String get allInOrder => 'Todo en orden';

  @override
  String get noDebts => 'No tienes adeudos';

  @override
  String get paymentUnderReview => 'Pago en revisión';

  @override
  String get paymentRequired => 'Pago requerido';

  @override
  String get receiptUnderReview => 'Tu comprobante está siendo revisado';

  @override
  String get pleaseMakePayment => 'Por favor realiza tu pago';

  @override
  String get accessRestricted => 'Acceso restringido';

  @override
  String get accountRestrictedMsg =>
      'Tu cuenta está restringida por falta de pago';

  @override
  String get pendingReview => 'Pendiente de revisión';

  @override
  String get approvedUpcoming => 'Aprobado (Próximo)';

  @override
  String get approvedInUse => 'Aprobado (En uso)';

  @override
  String get closed => 'Cerrado';

  @override
  String get rejected => 'Rechazado';

  @override
  String get active => 'Activo';

  @override
  String get deactivated => 'Desactivado';

  @override
  String get deactivatedRevoked => 'Desactivado (Revocado)';

  @override
  String get deactivatedExpired => 'Desactivado (Expirado)';

  @override
  String get deactivatedValidated => 'Desactivado (Validado)';

  @override
  String get shareQrVisitor => 'Comparte este QR con tu visitante.';

  @override
  String get addRoommate => 'Agregar miembro';

  @override
  String get enterEmail => 'Ingresa el correo electrónico';

  @override
  String get noRoommates => 'No hay miembros en tu grupo familiar.';

  @override
  String get roommateRemovedSuccess =>
      'Miembro familiar removido exitosamente.';

  @override
  String get guestName => 'Nombre del invitado';

  @override
  String get vehiclePlates => 'Placas del vehículo (Opcional)';

  @override
  String get signUpOption => '¿No tienes una cuenta? Regístrate';

  @override
  String get forgotPasswordOption => '¿Olvidaste tu contraseña?';

  @override
  String get signUpTitle => 'Registro de Residente';

  @override
  String get fullName => 'Nombre completo';

  @override
  String get signUpButton => 'Registrarse';

  @override
  String get signUpSuccess => 'Cuenta creada exitosamente. ¡Bienvenido!';

  @override
  String get signUpFailed =>
      'Error al crear la cuenta. Por favor, intenta de nuevo.';

  @override
  String get resetPasswordTitle => 'Restablecer Contraseña';

  @override
  String get resetPasswordInstructions =>
      'Ingresa tu correo electrónico y te enviaremos instrucciones para restablecer tu contraseña.';

  @override
  String get sendResetLinkButton => 'Enviar enlace de recuperación';

  @override
  String get resetLinkSent => 'Enlace de recuperación enviado a tu correo.';

  @override
  String get resetLinkFailed =>
      'Error al enviar el enlace. Verifica tu correo e intenta de nuevo.';

  @override
  String get backToLogin => 'Volver a Iniciar Sesión';

  @override
  String get selectAddressTitle => 'Selecciona tu Dirección';

  @override
  String get searchAddressPlaceholder => 'Buscar calle...';

  @override
  String get noUnclaimedAddresses =>
      'No se encontraron direcciones disponibles.';

  @override
  String get addressLinkedSuccess =>
      '¡Dirección vinculada exitosamente a tu cuenta!';

  @override
  String get validatingQr => 'Validando código QR...';

  @override
  String get invalidQrNotFound => 'Código QR inválido (No encontrado)';

  @override
  String get qrInvalidated => 'El código QR ha sido invalidado';

  @override
  String get qrExpired => 'El código QR ha expirado';

  @override
  String get accessGrantedHeader => 'Validación de Acceso';

  @override
  String get captureIdPhoto => 'Capturar Foto de Identificación';

  @override
  String get capturePlatePhoto => 'Capturar Foto de Placas';

  @override
  String get uploadingImages => 'Procesando y subiendo imágenes...';

  @override
  String get allowAccessButton => 'Permitir Acceso';

  @override
  String get denyAccessButton => 'Denegar Acceso';

  @override
  String get accessRegisteredSuccess => 'Acceso registrado exitosamente';

  @override
  String get scanAgainButton => 'Escanear de nuevo';

  @override
  String get visitorDetails => 'Detalles del Visitante';

  @override
  String get reasonOptional => 'Motivo (Opcional)';

  @override
  String get homepage => 'Inicio';

  @override
  String get manageBookings => 'Gestionar Reservas';

  @override
  String get managePayments => 'Gestionar Pagos';

  @override
  String get manageQrCodes => 'Gestionar Códigos QR';

  @override
  String get noQrCodes => 'No se encontraron códigos QR.';

  @override
  String get statusPaid => 'Pagado';

  @override
  String get statusPending => 'Pendiente';

  @override
  String get statusReviewing => 'En revisión';

  @override
  String get statusRestricted => 'Restringido';

  @override
  String get qrTypePermanent => 'Permanente';

  @override
  String get qrTypeTemporary => 'Temporal';

  @override
  String get shareCodeButton => 'Compartir código';

  @override
  String get guardPanelTitle => 'Panel de Guardia de Seguridad';

  @override
  String get guardInstructions =>
      'Escanea los códigos QR de los visitantes para validar su entrada y registrar el acceso.';

  @override
  String get vehicleType => 'Tipo de ingreso';

  @override
  String get vehicleCar => 'Automóvil';

  @override
  String get vehicleMotorcycle => 'Motocicleta';

  @override
  String get vehicleWalking => 'Peatonal';

  @override
  String get passengersCount => 'Número de pasajeros';

  @override
  String get copyCodeButton => 'Copiar código';

  @override
  String get copyCodeSuccess => 'Código copiado al portapapeles';

  @override
  String get downloadCodeButton => 'Descargar código';

  @override
  String get downloadCodeSuccess => 'Código descargado exitosamente';

  @override
  String get selectStreetLabel => 'Seleccionar calle';

  @override
  String get selectNumberLabel => 'Seleccionar número';

  @override
  String get confirmAddressButton => 'Confirmar Dirección';

  @override
  String get accessCategory => 'Categoría de acceso';

  @override
  String get categoryVisitor => 'Visitante';

  @override
  String get categorySupplier => 'Proveedor';

  @override
  String get ownershipProofTitle => 'Comprobante de Propiedad';

  @override
  String get ownershipProofInstructions =>
      'Por favor, sube una foto clara de tu comprobante de propiedad. Puede ser el Acta de entrega, las escrituras de la casa o un recibo de mantenimiento anterior.';

  @override
  String get captureProofPhoto => 'Tomar Foto';

  @override
  String get selectProofPhoto => 'Seleccionar de Galería';

  @override
  String get uploadProofButton => 'Enviar para Revisión';

  @override
  String get uploadingProof => 'Subiendo comprobante de propiedad...';

  @override
  String get proofUploadedSuccess =>
      'Comprobante enviado exitosamente. Esperando aprobación del administrador.';

  @override
  String get accountUnderReviewTitle => 'Cuenta en Revisión';

  @override
  String get accountUnderReviewMessage =>
      'Tu comprobante de propiedad está siendo revisado por un administrador. Recibirás acceso a las funciones de la aplicación una vez aprobado.';

  @override
  String get cancelReviewButton => 'Cancelar Revisión';

  @override
  String get reviewCancelledSuccess =>
      'Revisión cancelada. Ahora puedes seleccionar una dirección diferente.';

  @override
  String get approveResidentsMenu => 'Aprobar Residentes';

  @override
  String get noResidentsToApprove =>
      'No hay residentes pendientes de aprobación.';

  @override
  String get approveResidentButton => 'Aprobar Residente';

  @override
  String get rejectResidentButton => 'Rechazar';

  @override
  String get residentApprovedSuccess => 'Residente aprobado exitosamente.';

  @override
  String get claimAnotherAddressMenu => 'Reclamar Otra Dirección';

  @override
  String get adminPanelTitle => 'Panel de Administrador';

  @override
  String get manageTransparencyDocs => 'Gestionar Documentos de Transparencia';

  @override
  String get manageAnnouncements => 'Gestionar Anuncios';

  @override
  String get registerResidentMenu => 'Registrar Residente / Miembro';

  @override
  String get reviewPaymentsMenu => 'Revisar Pagos';

  @override
  String get uploadPaymentOnBehalfMenu => 'Subir Pago a Nombre de Usuario';

  @override
  String get manageUsersMenu => 'Directorio de Usuarios y Roles';

  @override
  String get manageFacilitiesMenu => 'Gestionar Amenidades';

  @override
  String get adminSettingsMenu => 'Configuración de Mantenimiento';

  @override
  String get resignAdminRole => 'Renunciar al Rol de Administrador';

  @override
  String get resignAdminConfirm =>
      '¿Estás seguro de que deseas renunciar como Administrador? Esta acción revocará tus privilegios de administrador de inmediato.';

  @override
  String get revokeAdminButton => 'Revocar Administrador';

  @override
  String get promoteAdminButton => 'Promover a Administrador';

  @override
  String get userPromotedSuccess =>
      'Usuario promovido a Administrador exitosamente';

  @override
  String get userRevokedSuccess =>
      'Acceso de administrador revocado exitosamente';

  @override
  String get roleResident => 'Residente';

  @override
  String get roleRoommate => 'Miembro';

  @override
  String get roleAdmin => 'Administrador';

  @override
  String get roleGuard => 'Guardia';

  @override
  String get adminOffice => 'Oficina de administración';

  @override
  String get noActiveAddressLinked => 'No hay dirección activa vinculada.';

  @override
  String get registerResidentTitle => 'Registro Directo';

  @override
  String get addressAlreadyClaimedError =>
      'Esta dirección ya está asignada a un residente principal.';

  @override
  String get roommateRequiresResidentError =>
      'Un miembro solo puede agregarse a una dirección que ya tiene un residente principal asignado.';

  @override
  String get userRegisteredSuccess =>
      'Usuario registrado y asignado a la dirección exitosamente.';

  @override
  String get selectResidentLabel => 'Seleccionar Residente';

  @override
  String get paymentApprovedSuccess =>
      'Pago aprobado exitosamente. Estado actualizado a pagado.';

  @override
  String get paymentRejectedSuccess => 'Comprobante de pago rechazado.';

  @override
  String get selfApprovalBlockedError =>
      'No puedes aprobar un comprobante de pago que tú mismo subiste.';

  @override
  String get addFacilityTitle => 'Agregar Amenidad';

  @override
  String get facilityIdLabel => 'ID de Amenidad (ej. salon_usos_multiples)';

  @override
  String get facilityNameLabel => 'Nombre a Mostrar';

  @override
  String get isUniqueAmenityLabel => 'Amenidad Única (Capacidad simple)';

  @override
  String get quantityLabel => 'Cantidad Disponible';

  @override
  String get facilityAddedSuccess => 'Amenidad agregada exitosamente.';

  @override
  String get settingsSavedSuccess => 'Configuración actualizada exitosamente.';

  @override
  String get paymentCutoffDayLabel => 'Día de Corte de Pago del Mes';

  @override
  String get gracePeriodDaysLabel => 'Período de Gracia (Días)';

  @override
  String get uploadDocumentTitle => 'Subir Documento';

  @override
  String get documentTitleLabel => 'Título del Documento';

  @override
  String get categoryLabel => 'Categoría';

  @override
  String get uploadButton => 'Subir';

  @override
  String get uploadingDocument => 'Subiendo documento...';

  @override
  String get documentUploadedSuccess => '¡Documento subido exitosamente!';

  @override
  String get untitledDocument => 'Documento sin título';

  @override
  String get downloadingDocument => 'Descargando documento...';

  @override
  String get downloadReportMenu => 'Descargar Reporte de Pagos';

  @override
  String get generateReportTitle => 'Reporte Matriz de Pagos';

  @override
  String get startMonthLabel => 'Mes de Inicio';

  @override
  String get endMonthLabel => 'Mes de Fin';

  @override
  String get generatingReport => 'Generando matriz de reporte CSV...';

  @override
  String get reportSavedSuccess => '¡Archivo de reporte guardado exitosamente!';

  @override
  String get statusPastDue => 'Vencido';

  @override
  String get manageGuardsMenu => 'Gestionar Guardias de Seguridad';

  @override
  String get provisionGuardTitle => 'Provisión de Guardia de Seguridad';

  @override
  String get guardNameLabel => 'Nombre del Guardia';

  @override
  String get guardEmailLabel => 'Correo del Guardia';

  @override
  String get guardPasswordLabel => 'Contraseña Inicial';

  @override
  String get provisionButton => 'Aprovisionar Cuenta';

  @override
  String get guardProvisionedSuccess =>
      'Cuenta de guardia de seguridad aprovisionada exitosamente.';

  @override
  String get removeGuardButton => 'Eliminar Cuenta';

  @override
  String get guardRemovedSuccess =>
      'Cuenta de guardia de seguridad eliminada exitosamente.';

  @override
  String get changePasswordTitle => 'Cambiar Contraseña de Usuario';

  @override
  String get newPasswordLabel => 'Nueva Contraseña';

  @override
  String get passwordUpdatedSuccess =>
      'Contraseña de usuario actualizada exitosamente.';

  @override
  String get privacyNoticeProofDeletion =>
      'Aviso de Privacidad: Para proteger tus datos personales, este documento de comprobante de propiedad será eliminado permanentemente de nuestros servidores de almacenamiento y base de datos inmediatamente tras la aprobación del administrador.';

  @override
  String get noDataAlertTitle => 'Sin Datos';

  @override
  String get noDataAlertMessage =>
      'No se encontraron registros de pago para el período seleccionado.';

  @override
  String claimingAddress(String address) {
    return 'Reclamando: $address';
  }

  @override
  String get cooldownUnitLabel => 'Unidad de Límite de Reserva';

  @override
  String get cooldownValueLabel => 'Duración del Límite';

  @override
  String get cooldownUnrestricted => 'Sin Límite (Sin Cooldown)';

  @override
  String get cooldownDays => 'Días';

  @override
  String get cooldownMonths => 'Meses';

  @override
  String get cooldownYears => 'Años';

  @override
  String get addressClaimInstructions =>
      'Puedes reclamar una propiedad como residente principal o mostrar tu Código QR de Hogar para ser vinculado por un residente principal.';

  @override
  String get roommateOnboardingInstructions =>
      'Pide a los miembros de tu familia que muestren su Código QR de Hogar o compartan su ID de usuario/correo para agregarlos a tu grupo familiar.';

  @override
  String get deliveryDateLabel => 'Fecha de entrega de la propiedad';

  @override
  String get selectDeliveryDate => 'Selecciona la fecha de entrega';

  @override
  String get selectPeriodLabel => 'Seleccionar período de mantenimiento';

  @override
  String get periodPlaceholder => 'Ej. Mayo 2026';

  @override
  String get noPendingPeriods => 'No tienes períodos pendientes de pago.';

  @override
  String get resignAddressLabel => 'Desvincular Dirección';

  @override
  String get resignConfirmText =>
      '¿Estás seguro de que deseas desvincular tu cuenta y la de todos tus cohabitantes de esta dirección?';

  @override
  String get deleteAccountLabel => 'Eliminar mi Cuenta';

  @override
  String get deleteAccountConfirmText =>
      'Esta acción es permanente y eliminará todas tus credenciales. ¿Deseas continuar?';

  @override
  String get addCategoryTitle => 'Agregar categoría';

  @override
  String get categoryNameLabel => 'Nombre de la categoría';

  @override
  String get targetAudienceLabel => 'Público objetivo';

  @override
  String get audienceAll => 'Todos los usuarios';

  @override
  String get audienceResidents => 'Solo residentes';

  @override
  String get joinAsRoommateTitle => 'Unirse al Hogar como Coinquilino';

  @override
  String get joinAsRoommateTab => 'Unirse como Coinquilino';

  @override
  String get claimPropertyTab => 'Reclamar Propiedad';

  @override
  String get showQrToResidentInstructions =>
      'Muestra este código QR al residente principal de tu hogar. Puede escanearlo desde su aplicación para vincular tu cuenta.';

  @override
  String get myRoommateQrCode => 'Mi Código QR de Hogar';

  @override
  String get copyUidButton => 'Copiar ID de Usuario';

  @override
  String get uidCopiedSnackbar => 'ID de usuario copiado al portapapeles.';

  @override
  String get scanRoommateQrButton => 'Escanear Código QR';

  @override
  String get enterEmailOrUidLabel => 'Ingresa Correo o ID de Usuario (UID)';

  @override
  String get roommateQrScannerTitle => 'Escanear QR de Coinquilino';

  @override
  String get invalidRoommateQrCode => 'Código QR de coinquilino no válido.';

  @override
  String get roommateAddedSuccess =>
      'Miembro de la familia agregado exitosamente.';

  @override
  String get waitingToBeLinked =>
      'Esperando a que un residente escanee o vincule tu cuenta...';

  @override
  String get bulkUserImportMenu => 'Creación Masiva de Usuarios (CSV)';

  @override
  String get bulkUserImportTitle => 'Creación Masiva de Residentes';

  @override
  String get uploadCsvButton => 'Subir Archivo CSV';

  @override
  String get copyCsvTemplateButton => 'Copiar Plantilla CSV';

  @override
  String processImportButton(int count) {
    return 'Crear Cuentas ($count)';
  }

  @override
  String get importSuccessTitle => 'Importación Completada';

  @override
  String importSummaryText(int successCount, int failureCount) {
    return '$successCount cuentas creadas exitosamente, $failureCount fallidas.';
  }

  @override
  String get noFileSelected => 'Ningún archivo seleccionado.';

  @override
  String get invalidCsvFormat =>
      'Formato CSV inválido o encabezados faltantes.';

  @override
  String get copyPasswordsButton => 'Copiar Contraseñas';

  @override
  String get passwordsCopiedSnackbar => 'Contraseñas copiadas al portapapeles.';

  @override
  String get csvColumnsHint =>
      'Columnas CSV esperadas: name, email, password (opcional), street (opcional), number (opcional)';

  @override
  String get csvTemplateCopiedSnackbar =>
      'Plantilla CSV copiada al portapapeles.';

  @override
  String get downloadResultCsvButton => 'Descargar CSV de Resultados';

  @override
  String get copyResultCsvButton => 'Copiar CSV de Resultados';

  @override
  String get csvDownloadedSuccess =>
      'CSV de resultados descargado exitosamente.';

  @override
  String get csvCopiedSuccess => 'CSV de resultados copiado al portapapeles.';

  @override
  String get bulkAddressImportMenu => 'Creación Masiva de Direcciones (CSV)';

  @override
  String get bulkAddressImportTitle => 'Creación Masiva de Direcciones';

  @override
  String get addressCsvColumnsHint =>
      'Columnas CSV esperadas: streetName, initialNumber, finalNumber, exclusions (opcional)';

  @override
  String importAddressesButton(int count) {
    return 'Importar Direcciones ($count)';
  }

  @override
  String addressesImportedSuccess(int created, int skipped) {
    return 'Se crearon $created direcciones exitosamente ($skipped omitidas/duplicadas).';
  }

  @override
  String get importAnotherFileButton => 'Importar Otro Archivo';

  @override
  String get paymentSettingsSection => 'Pagos y Período de Gracia';

  @override
  String get smtpSettingsSection => 'Servicio de Correo SMTP';

  @override
  String get smtpEnabledLabel => 'Habilitar Correos de Bienvenida Automáticos';

  @override
  String get smtpEnabledSubtitle =>
      'Enviar credenciales de acceso a nuevos residentes al crearse o importarse';

  @override
  String get smtpHostLabel => 'Servidor Host SMTP';

  @override
  String get smtpHostHint => 'ej. smtp.gmail.com o smtp.sendgrid.net';

  @override
  String get smtpPortLabel => 'Puerto';

  @override
  String get smtpPortHint => '587, 465, 25';

  @override
  String get smtpSecureLabel => 'Usar SSL/TLS (Seguro)';

  @override
  String get smtpSecureSubtitle =>
      'Habilitar para puerto 465, deshabilitar para STARTTLS (puerto 587)';

  @override
  String get smtpUserLabel => 'Usuario / Correo de Autenticación';

  @override
  String get smtpUserHint => 'ej. notificaciones@tudominio.com';

  @override
  String get smtpPassLabel => 'Contraseña / Clave API';

  @override
  String get smtpPassHint => 'Contraseña SMTP o Contraseña de Aplicación';

  @override
  String get smtpSenderEmailLabel => 'Correo del Remitente (Opcional)';

  @override
  String get smtpSenderEmailHint => 'ej. no-responder@tudominio.com';

  @override
  String get smtpSenderNameLabel => 'Nombre del Remitente (Opcional)';

  @override
  String get smtpSenderNameHint => 'ej. Administración Suburban Life';

  @override
  String get testSmtpButton => 'Probar Conexión y Enviar Correo';

  @override
  String get testRecipientLabel => 'Correo Destinatario de Prueba';

  @override
  String get testRecipientHint => 'tu-correo@ejemplo.com';

  @override
  String get smtpHostRequired => 'Por favor ingresa el servidor Host SMTP.';

  @override
  String get smtpUserRequired =>
      'Por favor ingresa el usuario o correo de autenticación SMTP.';

  @override
  String get smtpPassRequired =>
      'Por favor ingresa la contraseña o clave API de SMTP.';

  @override
  String get smtpTestRecipientRequired =>
      'Por favor ingresa un correo destinatario de prueba válido.';

  @override
  String get testSmtpSuccess =>
      '¡Conexión SMTP verificada! Correo de prueba enviado con éxito.';

  @override
  String testSmtpFailure(String error) {
    return 'Prueba SMTP fallida: $error';
  }

  @override
  String get smtpBadgeActive => 'Correos de Bienvenida SMTP Activos';

  @override
  String get smtpBadgeInactive => 'SMTP Inactivo (No se enviarán correos)';

  @override
  String get saveSettingsButton => 'Guardar Configuración';

  @override
  String get emailSentStatus => 'Correo Enviado';

  @override
  String get emailFailedStatus => 'Fallo de Correo';

  @override
  String get emailSkippedStatus => 'Correo Omitido (SMTP Desactivado)';

  @override
  String get customWelcomeEmailSection =>
      'Plantilla de Mensaje de Bienvenida Personalizado';

  @override
  String get customWelcomeEmailSubtitle =>
      'Personaliza el correo de bienvenida enviado a las nuevas cuentas. Usa marcadores para insertar datos de la cuenta dinámicamente.';

  @override
  String get emailSubjectLabel => 'Asunto del Correo';

  @override
  String get emailSubjectHint =>
      'ej. ¡Bienvenido(a) a %appName%! Credenciales de Acceso';

  @override
  String get emailBodyLabel => 'Cuerpo del Mensaje de Correo';

  @override
  String get emailBodyHint =>
      'Escribe aquí la plantilla de tu mensaje de bienvenida...';

  @override
  String get availablePlaceholdersLabel =>
      'Marcadores Disponibles (clic para insertar):';

  @override
  String get resetDefaultTemplateButton =>
      'Restablecer Plantilla Predeterminada';

  @override
  String get defaultWelcomeSubject =>
      '¡Bienvenido(a) a %appName%! Credenciales de Acceso';

  @override
  String get defaultWelcomeBody =>
      'Hola %name%,\n\nTu cuenta de %role% ha sido creada exitosamente. A continuación encontrarás tus credenciales de acceso:\n\n- Correo electrónico: %email%\n- Contraseña inicial: %password%\n- Dirección asignada: %address%\n\nTe recomendamos iniciar sesión y actualizar tu contraseña.\n\nAtentamente,\nAdministración de %appName%';

  @override
  String get createUserMenu => 'Crear Usuario';

  @override
  String get createUserTitle => 'Crear Cuenta de Usuario';

  @override
  String get userTypeLabel => 'Tipo de Usuario';

  @override
  String get guardInfoBanner =>
      'Las cuentas de guardia de seguridad tienen permisos para escanear pases QR de visitantes, registrar accesos y verificar identificaciones en caseta.';

  @override
  String get adminInfoBanner =>
      'Las cuentas de administrador tienen control total. Este usuario será vinculado automáticamente a la dirección \'Oficina de administración\'.';

  @override
  String get userCreatedSuccess => '¡Cuenta de usuario creada con éxito!';

  @override
  String get createUserButton => 'Crear Cuenta de Usuario';

  @override
  String get generatePasswordButton => 'Generar Contraseña';

  @override
  String get selectStreetPrompt => 'Seleccionar Calle';

  @override
  String get selectNumberPrompt => 'Seleccionar Número';

  @override
  String get noAvailableAddressesError =>
      'No hay números disponibles sin asignar en esta calle.';

  @override
  String get addressMustBeSelected =>
      'Por favor selecciona una calle y número para el residente.';

  @override
  String get fullNameLabel => 'Nombre Completo';

  @override
  String get fullNameHint => 'ej. Juan Pérez';

  @override
  String get emailAddressLabel => 'Correo Electrónico';

  @override
  String get emailAddressHint => 'ej. usuario@ejemplo.com';

  @override
  String get passwordLabel => 'Contraseña';

  @override
  String get passwordHint => 'Mínimo 6 caracteres';

  @override
  String get selectAddressLabel => 'Dirección Asignada';

  @override
  String get userManagementMenu => 'Datos de la Cuenta';

  @override
  String get shareQrAccessMessage => '¡Aquí está tu código QR de acceso!';

  @override
  String get supplierSingleDayValidity => 'Válido solo hoy (Un solo uso)';

  @override
  String get cardGuestName => 'Nombre del Invitado';

  @override
  String get cardAuthorizedAddress => 'Dirección Autorizada';

  @override
  String get cardAccessCategory => 'Categoría de Acceso';

  @override
  String get cardValidity => 'Vigencia';

  @override
  String get cardVehicleDetails => 'Detalles del Vehículo';

  @override
  String get passwordComplexityRequirements =>
      'La contraseña debe tener al menos 8 caracteres y contener al menos 1 letra mayúscula, 1 minúscula y 1 número.';

  @override
  String get passwordComplexityHelper =>
      'Mín. 8 caracteres (1 mayúscula, 1 minúscula, 1 número)';

  @override
  String get passwordComplexityError =>
      'La contraseña no cumple con los requisitos de seguridad.';

  @override
  String get ok => 'Aceptar';

  @override
  String get close => 'Cerrar';

  @override
  String get save => 'Guardar';

  @override
  String errorPrefix(String error) {
    return 'Error: $error';
  }

  @override
  String get userNotLoggedIn => 'Usuario no autenticado';

  @override
  String get guestFallback => 'Invitado';

  @override
  String get switchToResidentViewTooltip => 'Cambiar a vista de residente';

  @override
  String get switchToAdminViewTooltip => 'Cambiar a vista de administrador';

  @override
  String get notificationHistoryTitle => 'Historial de Notificaciones';

  @override
  String get notificationHistoryPlaceholder =>
      'El historial se mostrará aquí (FCM).';

  @override
  String qrItemCreated(String date) {
    return 'Creado: $date';
  }

  @override
  String qrItemPlates(String plates) {
    return 'Placas: $plates';
  }

  @override
  String get qrInvalidatedSuccess => 'Código QR invalidado.';

  @override
  String get enterGuestNamePrompt => 'Por favor ingresa el nombre del invitado';

  @override
  String get qrGenerationFailed => 'Error al generar el código QR';

  @override
  String qrSharingError(String error) {
    return 'Error al compartir/descargar: $error';
  }

  @override
  String get bookingCreatedSuccess => '¡Reservación creada exitosamente!';

  @override
  String bookingStatusLabel(String status) {
    return 'Estado: $status';
  }

  @override
  String get bookingCancelledSuccess => 'Reservación cancelada.';

  @override
  String get editRejectedBookingTitle => 'Editar Reservación Rechazada';

  @override
  String get bookingResubmittedSuccess =>
      'Reservación reenviada para revisión.';

  @override
  String get resubmitButton => 'Reenviar';

  @override
  String get addressDetailsNotFound =>
      'No se encontraron los detalles de la dirección.';

  @override
  String get passwordMinLengthValidation =>
      'La contraseña debe tener al menos 6 caracteres.';

  @override
  String get addressUnlinkedSuccess => 'Dirección desvinculada exitosamente.';

  @override
  String get resetPasswordButton => 'Restablecer Contraseña';

  @override
  String get guardFormValidation =>
      'Por favor proporciona un nombre, correo y contraseña válidos (mín. 6 caracteres).';

  @override
  String errorProvisioningGuard(String error) {
    return 'Error al registrar guardia: $error';
  }

  @override
  String errorRemovingGuard(String error) {
    return 'Error al eliminar guardia: $error';
  }

  @override
  String get noGuardsProvisioned =>
      'No hay guardias de seguridad registrados todavía.';

  @override
  String errorDeletingFacility(String error) {
    return 'Error al eliminar: $error';
  }

  @override
  String get noAmenitiesRegistered => 'No hay amenidades registradas todavía.';

  @override
  String get approvePaymentButton => 'Aprobar Pago';

  @override
  String errorReadingFile(String error) {
    return 'Error al leer el archivo: $error';
  }

  @override
  String importError(String error) {
    return 'Error de importación: $error';
  }

  @override
  String errorSavingFile(String error) {
    return 'Error al guardar el archivo: $error';
  }

  @override
  String userSummaryEmail(String email) {
    return 'Correo: $email';
  }

  @override
  String userSummaryStatus(String status) {
    return 'Estado: $status';
  }

  @override
  String userSummaryAssignedPassword(String password) {
    return 'Contraseña asignada: $password';
  }

  @override
  String userSummaryLinkedAddress(String address) {
    return 'Dirección vinculada: $address';
  }

  @override
  String addressExclusionsLabel(String exclusions) {
    return 'Exclusiones: $exclusions';
  }

  @override
  String get accessLogsMenu => 'Historial de Accesos';

  @override
  String get accessLogsTitle => 'Registro de Accesos';

  @override
  String get filterByAddress => 'Filtrar por Dirección';

  @override
  String get allAddresses => 'Todas las Direcciones';

  @override
  String get filterByDate => 'Filtrar por Fecha';

  @override
  String get allDates => 'Todas las Fechas';

  @override
  String get today => 'Hoy';

  @override
  String get thisWeek => 'Esta Semana';

  @override
  String get thisMonth => 'Este Mes';

  @override
  String get customDateRange => 'Rango Personalizado';

  @override
  String get filterByType => 'Tipo de Visitante';

  @override
  String get allTypes => 'Todos los Tipos';

  @override
  String get visitorTypeGuest => 'Invitado';

  @override
  String get visitorTypeSupplier => 'Proveedor';

  @override
  String get searchVisitorOrPlate => 'Buscar visitante, placas o motivo...';

  @override
  String get totalAccesses => 'Total de Accesos';

  @override
  String get allowedAccesses => 'Permitidos';

  @override
  String get deniedAccesses => 'Denegados';

  @override
  String get providerAccesses => 'Proveedores';

  @override
  String get noAccessLogsFound =>
      'No se encontraron registros de acceso con los filtros seleccionados.';

  @override
  String get verifiedByGuard => 'Guardia';

  @override
  String get invitedByResident => 'Residente';

  @override
  String get destinationAddress => 'Destino';

  @override
  String get vehicleDetails => 'Vehículo';

  @override
  String get viewVisitorIdPhoto => 'Foto de Identificación';

  @override
  String get viewPlatePhoto => 'Foto de Placas';

  @override
  String get reasonOrNotes => 'Notas / Motivo';

  @override
  String get accessAllowed => 'Permitido';

  @override
  String get accessDenied => 'Denegado';

  @override
  String logPassengersCount(int count) {
    return 'Pasajeros: $count';
  }
}
