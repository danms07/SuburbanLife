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
      'Puedes iniciar el proceso de reclamo de dirección aquí o pedirle a un residente que te agregue como cohabitante desde su aplicación.';

  @override
  String get roommateOnboardingInstructions =>
      'Pídele a tus cohabitantes que se registren en la aplicación y compartan su correo electrónico para que los puedas agregar a tu grupo familiar.';

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
}
