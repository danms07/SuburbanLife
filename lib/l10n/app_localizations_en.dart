// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Suburban Life';

  @override
  String get welcome => 'Welcome to Suburban Life';

  @override
  String welcomeUser(String name) {
    return 'Hello, $name!';
  }

  @override
  String get bookFacility => 'Book a Facility';

  @override
  String get transparencyDocs => 'Transparency Documents';

  @override
  String get monthlyPayment => 'Monthly Payment';

  @override
  String get logout => 'Logout';

  @override
  String get login => 'Sign In';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get loginSuccess => 'Login successful';

  @override
  String get loginFailed => 'Login failed';

  @override
  String get scanQr => 'Scan QR Access';

  @override
  String get generateQr => 'Generate Access QR';

  @override
  String get type => 'Type';

  @override
  String get expires => 'Expires';

  @override
  String get facilityBooking => 'Amenities Booking';

  @override
  String get reserveFacility => 'Reserve a Facility';

  @override
  String get selectFacility => 'Select Facility';

  @override
  String get confirmBooking => 'Confirm Booking';

  @override
  String get upcomingBookings => 'Upcoming Bookings';

  @override
  String get date => 'Date';

  @override
  String get from => 'From';

  @override
  String get to => 'To';

  @override
  String get noBookings => 'No upcoming bookings for this facility.';

  @override
  String get filterByCategory => 'Filter by Category: ';

  @override
  String get noDocuments => 'No documents available in this category.';

  @override
  String get maintenancePayment => 'Maintenance Payment';

  @override
  String get monthlyQuota => 'Monthly Maintenance Quota';

  @override
  String get currentStatus => 'Current Status';

  @override
  String get takePhotoReceipt => 'Take Photo of Receipt';

  @override
  String get receiptNotice =>
      'Note: Only direct camera captures of maintenance receipts are allowed to ensure authenticity.';

  @override
  String get announcements => 'Announcements';

  @override
  String get createAnnouncement => 'Create Announcement';

  @override
  String get titleSpanish => 'Title (Spanish)';

  @override
  String get contentSpanish => 'Content (Spanish)';

  @override
  String get cancel => 'Cancel';

  @override
  String get create => 'Create';

  @override
  String get errorAnnouncements => 'Error loading announcements';

  @override
  String get noAnnouncements => 'No announcements yet';

  @override
  String get attachImage => 'Attach Image';

  @override
  String get pasteFromClipboard => 'Paste from Clipboard';

  @override
  String get changeImage => 'Change Image';

  @override
  String get removeImage => 'Remove Image';

  @override
  String get imagePastedSuccess => 'Image attached from clipboard!';

  @override
  String get noImageInClipboard =>
      'No image found in clipboard. Please copy an image first.';

  @override
  String get pasteImageHint => 'Or press Ctrl+V / Cmd+V to paste an image';

  @override
  String get emojisLabel => 'Quick Emojis:';

  @override
  String get insertEmojiHint => 'Tap an emoji to insert it into the message';

  @override
  String get viewFullImage => 'View Image';

  @override
  String imageUploadError(String error) {
    return 'Failed to upload image: $error';
  }

  @override
  String get announcementCreatedSuccess =>
      'Announcement published successfully!';

  @override
  String get fillRequiredFields => 'Please fill in both title and content.';

  @override
  String get multipurposeRoom => 'Multipurpose Room';

  @override
  String get bicycle1 => 'Bicycle 1';

  @override
  String get roofGarden => 'Roof Garden';

  @override
  String get noticesGrid => 'Notices';

  @override
  String get transparencyGrid => 'Transparency';

  @override
  String get generateQrGrid => 'Generate QR';

  @override
  String get familyGroupGrid => 'Family Group';

  @override
  String get allInOrder => 'All in order';

  @override
  String get noDebts => 'No debts';

  @override
  String get paymentUnderReview => 'Payment under review';

  @override
  String get paymentRequired => 'Payment required';

  @override
  String get receiptUnderReview => 'Your receipt is being reviewed';

  @override
  String get pleaseMakePayment => 'Please make your payment';

  @override
  String get accessRestricted => 'Access restricted';

  @override
  String get accountRestrictedMsg =>
      'Your account is restricted due to missing payment';

  @override
  String get pendingReview => 'Pending Review';

  @override
  String get approvedUpcoming => 'Approved (Upcoming)';

  @override
  String get approvedInUse => 'Approved (In Use)';

  @override
  String get closed => 'Closed';

  @override
  String get rejected => 'Rejected';

  @override
  String get active => 'Active';

  @override
  String get deactivated => 'Deactivated';

  @override
  String get deactivatedRevoked => 'Deactivated (Revoked)';

  @override
  String get deactivatedExpired => 'Deactivated (Expired)';

  @override
  String get deactivatedValidated => 'Deactivated (Validated)';

  @override
  String get shareQrVisitor => 'Share this QR code with your visitor.';

  @override
  String get addRoommate => 'Add Member';

  @override
  String get enterEmail => 'Enter email address';

  @override
  String get noRoommates => 'No members in your family group.';

  @override
  String get roommateRemovedSuccess => 'Family member removed successfully.';

  @override
  String get guestName => 'Guest Name';

  @override
  String get vehiclePlates => 'Vehicle Plates (Optional)';

  @override
  String get signUpOption => 'Don\'t have an account? Sign Up';

  @override
  String get forgotPasswordOption => 'Forgot Password?';

  @override
  String get signUpTitle => 'Resident Sign Up';

  @override
  String get fullName => 'Full Name';

  @override
  String get signUpButton => 'Sign Up';

  @override
  String get signUpSuccess => 'Account created successfully. Welcome!';

  @override
  String get signUpFailed => 'Failed to create account. Please try again.';

  @override
  String get resetPasswordTitle => 'Reset Password';

  @override
  String get resetPasswordInstructions =>
      'Enter your email address and we will send you instructions to reset your password.';

  @override
  String get sendResetLinkButton => 'Send Reset Link';

  @override
  String get resetLinkSent => 'Password reset link sent to your email.';

  @override
  String get resetLinkFailed =>
      'Failed to send reset link. Check your email and try again.';

  @override
  String get backToLogin => 'Back to Sign In';

  @override
  String get selectAddressTitle => 'Select Your Address';

  @override
  String get searchAddressPlaceholder => 'Search street name...';

  @override
  String get noUnclaimedAddresses => 'No unclaimed addresses found.';

  @override
  String get addressLinkedSuccess =>
      'Address successfully linked to your account!';

  @override
  String get validatingQr => 'Validating QR Code...';

  @override
  String get invalidQrNotFound => 'Invalid QR Code (Not found)';

  @override
  String get qrInvalidated => 'QR Code has been invalidated';

  @override
  String get qrExpired => 'QR Code has expired';

  @override
  String get accessGrantedHeader => 'Access Validation';

  @override
  String get captureIdPhoto => 'Capture ID Photo';

  @override
  String get capturePlatePhoto => 'Capture Plate Photo';

  @override
  String get uploadingImages => 'Processing and uploading images...';

  @override
  String get allowAccessButton => 'Allow Access';

  @override
  String get denyAccessButton => 'Deny Access';

  @override
  String get accessRegisteredSuccess => 'Access registered successfully';

  @override
  String get scanAgainButton => 'Scan Again';

  @override
  String get visitorDetails => 'Visitor Details';

  @override
  String get reasonOptional => 'Reason (Optional)';

  @override
  String get homepage => 'Homepage';

  @override
  String get manageBookings => 'Manage Bookings';

  @override
  String get managePayments => 'Manage Payments';

  @override
  String get manageQrCodes => 'Manage QR Codes';

  @override
  String get noQrCodes => 'No QR codes found.';

  @override
  String get statusPaid => 'Paid';

  @override
  String get statusPending => 'Pending';

  @override
  String get statusReviewing => 'Under Review';

  @override
  String get statusRestricted => 'Restricted';

  @override
  String get qrTypePermanent => 'Permanent';

  @override
  String get qrTypeTemporary => 'Temporary';

  @override
  String get shareCodeButton => 'Share Code';

  @override
  String get guardPanelTitle => 'Security Guard Panel';

  @override
  String get guardInstructions =>
      'Scan visitor QR codes to validate entry and register access.';

  @override
  String get vehicleType => 'Entry Type';

  @override
  String get vehicleCar => 'Car';

  @override
  String get vehicleMotorcycle => 'Motorcycle';

  @override
  String get vehicleWalking => 'Walking';

  @override
  String get passengersCount => 'Number of Passengers';

  @override
  String get copyCodeButton => 'Copy Code';

  @override
  String get copyCodeSuccess => 'Code copied to clipboard';

  @override
  String get downloadCodeButton => 'Download Code';

  @override
  String get downloadCodeSuccess => 'Code downloaded successfully';

  @override
  String get selectStreetLabel => 'Select Street';

  @override
  String get selectNumberLabel => 'Select Number';

  @override
  String get confirmAddressButton => 'Confirm Address';

  @override
  String get accessCategory => 'Access Category';

  @override
  String get categoryVisitor => 'Visitor';

  @override
  String get categorySupplier => 'Supplier';

  @override
  String get ownershipProofTitle => 'Proof of Ownership';

  @override
  String get ownershipProofInstructions =>
      'Please upload a clear photo of your proof of ownership. This can be the house deeds, \'Property Handover Certificate\', or a previous maintenance receipt.';

  @override
  String get captureProofPhoto => 'Take Photo';

  @override
  String get selectProofPhoto => 'Select from Gallery';

  @override
  String get uploadProofButton => 'Submit for Review';

  @override
  String get uploadingProof => 'Uploading proof of ownership...';

  @override
  String get proofUploadedSuccess =>
      'Proof submitted successfully. Awaiting admin approval.';

  @override
  String get accountUnderReviewTitle => 'Account Under Review';

  @override
  String get accountUnderReviewMessage =>
      'Your proof of ownership is currently being reviewed by an administrator. You will receive access to the app\'s features once approved.';

  @override
  String get cancelReviewButton => 'Cancel Review';

  @override
  String get reviewCancelledSuccess =>
      'Review cancelled. You can now claim a different address.';

  @override
  String get approveResidentsMenu => 'Approve Residents';

  @override
  String get noResidentsToApprove => 'No residents pending approval.';

  @override
  String get approveResidentButton => 'Approve Resident';

  @override
  String get rejectResidentButton => 'Reject';

  @override
  String get residentApprovedSuccess => 'Resident approved successfully.';

  @override
  String get claimAnotherAddressMenu => 'Claim Another Address';

  @override
  String get adminPanelTitle => 'Admin Panel';

  @override
  String get manageTransparencyDocs => 'Manage Transparency Docs';

  @override
  String get manageAnnouncements => 'Manage Announcements';

  @override
  String get registerResidentMenu => 'Register Resident / Roommate';

  @override
  String get reviewPaymentsMenu => 'Review Payments';

  @override
  String get uploadPaymentOnBehalfMenu => 'Upload Payment on Behalf';

  @override
  String get manageUsersMenu => 'User Directory & Roles';

  @override
  String get manageFacilitiesMenu => 'Manage Amenities';

  @override
  String get adminSettingsMenu => 'Maintenance Settings';

  @override
  String get resignAdminRole => 'Resign Admin Role';

  @override
  String get resignAdminConfirm =>
      'Are you sure you want to step down as an Admin? This action will revoke your admin privileges immediately.';

  @override
  String get revokeAdminButton => 'Revoke Admin';

  @override
  String get promoteAdminButton => 'Promote to Admin';

  @override
  String get userPromotedSuccess => 'User promoted to Admin successfully';

  @override
  String get userRevokedSuccess => 'Admin access revoked successfully';

  @override
  String get roleResident => 'Resident';

  @override
  String get roleRoommate => 'Roommate';

  @override
  String get roleAdmin => 'Admin';

  @override
  String get roleGuard => 'Guard';

  @override
  String get adminOffice => 'Admin office';

  @override
  String get noActiveAddressLinked => 'No active address linked.';

  @override
  String get registerResidentTitle => 'Direct Registration';

  @override
  String get addressAlreadyClaimedError =>
      'This address is already claimed by another primary resident.';

  @override
  String get roommateRequiresResidentError =>
      'A roommate can only be added to an address that is already assigned to a primary resident.';

  @override
  String get userRegisteredSuccess =>
      'User successfully registered and assigned to address.';

  @override
  String get selectResidentLabel => 'Select Resident';

  @override
  String get paymentApprovedSuccess =>
      'Payment approved successfully. Status updated to paid.';

  @override
  String get paymentRejectedSuccess => 'Payment proof rejected.';

  @override
  String get selfApprovalBlockedError =>
      'You cannot approve a payment proof that you uploaded yourself.';

  @override
  String get addFacilityTitle => 'Add Amenity';

  @override
  String get facilityIdLabel => 'Amenity ID (e.g., multipurpose_room)';

  @override
  String get facilityNameLabel => 'Display Name';

  @override
  String get isUniqueAmenityLabel => 'Unique Amenity (Single capacity)';

  @override
  String get quantityLabel => 'Available Quantity';

  @override
  String get facilityAddedSuccess => 'Amenity successfully added.';

  @override
  String get settingsSavedSuccess => 'Settings successfully updated.';

  @override
  String get paymentCutoffDayLabel => 'Payment Cutoff Day of Month';

  @override
  String get gracePeriodDaysLabel => 'Grace Period (Days)';

  @override
  String get uploadDocumentTitle => 'Upload Document';

  @override
  String get documentTitleLabel => 'Document Title';

  @override
  String get categoryLabel => 'Category';

  @override
  String get uploadButton => 'Upload';

  @override
  String get uploadingDocument => 'Uploading document...';

  @override
  String get documentUploadedSuccess => 'Document uploaded successfully!';

  @override
  String get untitledDocument => 'Untitled Document';

  @override
  String get downloadingDocument => 'Downloading document...';

  @override
  String get downloadReportMenu => 'Download Payment Report';

  @override
  String get generateReportTitle => 'Payment Matrix Report';

  @override
  String get startMonthLabel => 'Start Month';

  @override
  String get endMonthLabel => 'End Month';

  @override
  String get generatingReport => 'Generating CSV report matrix...';

  @override
  String get reportSavedSuccess => 'Report file saved successfully!';

  @override
  String get statusPastDue => 'Past Due';

  @override
  String get manageGuardsMenu => 'Manage Security Guards';

  @override
  String get provisionGuardTitle => 'Provision Security Guard';

  @override
  String get guardNameLabel => 'Guard Name';

  @override
  String get guardEmailLabel => 'Guard Email';

  @override
  String get guardPasswordLabel => 'Initial Password';

  @override
  String get provisionButton => 'Provision Account';

  @override
  String get guardProvisionedSuccess =>
      'Security guard account provisioned successfully.';

  @override
  String get removeGuardButton => 'Remove Account';

  @override
  String get guardRemovedSuccess =>
      'Security guard account removed successfully.';

  @override
  String get changePasswordTitle => 'Change User Password';

  @override
  String get newPasswordLabel => 'New Password';

  @override
  String get passwordUpdatedSuccess => 'User password updated successfully.';

  @override
  String get privacyNoticeProofDeletion =>
      'Privacy Notice: To protect your personal data, this proof of ownership document will be permanently removed from our storage servers and database immediately upon admin approval.';

  @override
  String get noDataAlertTitle => 'No Data Found';

  @override
  String get noDataAlertMessage =>
      'No payment records exist for the selected period.';

  @override
  String claimingAddress(String address) {
    return 'Claiming: $address';
  }

  @override
  String get cooldownUnitLabel => 'Booking Cooldown Unit';

  @override
  String get cooldownValueLabel => 'Cooldown Duration';

  @override
  String get cooldownUnrestricted => 'Unrestricted (No Cooldown)';

  @override
  String get cooldownDays => 'Days';

  @override
  String get cooldownMonths => 'Months';

  @override
  String get cooldownYears => 'Years';

  @override
  String get addressClaimInstructions =>
      'You can claim a property as a primary resident or show your Household QR Code to be linked by a primary resident.';

  @override
  String get roommateOnboardingInstructions =>
      'Ask family members to show their Household QR Code or share their User ID/email so you can add them to your family group.';

  @override
  String get deliveryDateLabel => 'Property Handover Date';

  @override
  String get selectDeliveryDate => 'Select delivery date';

  @override
  String get selectPeriodLabel => 'Select maintenance period';

  @override
  String get periodPlaceholder => 'e.g. May 2026';

  @override
  String get noPendingPeriods => 'You have no pending periods of payment.';

  @override
  String get resignAddressLabel => 'Unbind Address';

  @override
  String get resignConfirmText =>
      'Are you sure you want to unbind your account and all roommates from this address?';

  @override
  String get deleteAccountLabel => 'Delete Account';

  @override
  String get deleteAccountConfirmText =>
      'This action is permanent and will delete all your credentials. Do you want to proceed?';

  @override
  String get addCategoryTitle => 'Add Category';

  @override
  String get categoryNameLabel => 'Category Name';

  @override
  String get targetAudienceLabel => 'Target Audience';

  @override
  String get audienceAll => 'All Users';

  @override
  String get audienceResidents => 'Residents Only';

  @override
  String get joinAsRoommateTitle => 'Join Household as Roommate';

  @override
  String get joinAsRoommateTab => 'Join as Roommate';

  @override
  String get claimPropertyTab => 'Claim Property';

  @override
  String get showQrToResidentInstructions =>
      'Show this QR code to the primary resident of your household. They can scan it from their app to link your account.';

  @override
  String get myRoommateQrCode => 'My Household QR Code';

  @override
  String get copyUidButton => 'Copy User ID';

  @override
  String get uidCopiedSnackbar => 'User ID copied to clipboard.';

  @override
  String get scanRoommateQrButton => 'Scan QR Code';

  @override
  String get enterEmailOrUidLabel => 'Enter Roommate Email or User ID (UID)';

  @override
  String get roommateQrScannerTitle => 'Scan Roommate QR Code';

  @override
  String get invalidRoommateQrCode => 'Invalid Roommate QR Code scanned.';

  @override
  String get roommateAddedSuccess => 'Family member added successfully.';

  @override
  String get waitingToBeLinked =>
      'Waiting for a resident to scan or link your account...';

  @override
  String get bulkUserImportMenu => 'Bulk User Creation (CSV)';

  @override
  String get bulkUserImportTitle => 'Bulk Resident Creation';

  @override
  String get uploadCsvButton => 'Upload CSV File';

  @override
  String get copyCsvTemplateButton => 'Copy CSV Template';

  @override
  String processImportButton(int count) {
    return 'Create Accounts ($count)';
  }

  @override
  String get importSuccessTitle => 'Import Completed';

  @override
  String importSummaryText(int successCount, int failureCount) {
    return '$successCount accounts created successfully, $failureCount failed.';
  }

  @override
  String get noFileSelected => 'No file selected.';

  @override
  String get invalidCsvFormat => 'Invalid CSV format or missing headers.';

  @override
  String get copyPasswordsButton => 'Copy Passwords';

  @override
  String get passwordsCopiedSnackbar => 'Passwords copied to clipboard.';

  @override
  String get csvColumnsHint =>
      'Expected CSV columns: name, email, password (optional), street (optional), number (optional)';

  @override
  String get csvTemplateCopiedSnackbar => 'CSV template copied to clipboard.';

  @override
  String get downloadResultCsvButton => 'Download Result CSV';

  @override
  String get copyResultCsvButton => 'Copy Result CSV';

  @override
  String get csvDownloadedSuccess => 'Result CSV downloaded successfully.';

  @override
  String get csvCopiedSuccess => 'Result CSV copied to clipboard.';

  @override
  String get bulkAddressImportMenu => 'Bulk Address Creation (CSV)';

  @override
  String get bulkAddressImportTitle => 'Bulk Address Creation';

  @override
  String get addressCsvColumnsHint =>
      'Expected CSV columns: streetName, initialNumber, finalNumber, exclusions (optional)';

  @override
  String importAddressesButton(int count) {
    return 'Import Addresses ($count)';
  }

  @override
  String addressesImportedSuccess(int created, int skipped) {
    return 'Successfully created $created addresses ($skipped skipped/duplicates).';
  }

  @override
  String get importAnotherFileButton => 'Import Another File';

  @override
  String get paymentSettingsSection => 'Payment & Grace Period';

  @override
  String get smtpSettingsSection => 'SMTP Email Service';

  @override
  String get smtpEnabledLabel => 'Enable Automatic Welcome Emails';

  @override
  String get smtpEnabledSubtitle =>
      'Send account credentials to new residents upon creation or bulk import';

  @override
  String get smtpHostLabel => 'SMTP Host Server';

  @override
  String get smtpHostHint => 'e.g. smtp.gmail.com or smtp.sendgrid.net';

  @override
  String get smtpPortLabel => 'Port';

  @override
  String get smtpPortHint => '587, 465, 25';

  @override
  String get smtpSecureLabel => 'Use SSL/TLS (Secure)';

  @override
  String get smtpSecureSubtitle =>
      'Enable for port 465, disable for STARTTLS (port 587)';

  @override
  String get smtpUserLabel => 'Username / Auth Email';

  @override
  String get smtpUserHint => 'e.g. notifications@yourdomain.com';

  @override
  String get smtpPassLabel => 'Password / API Key';

  @override
  String get smtpPassHint => 'SMTP password or App Password';

  @override
  String get smtpSenderEmailLabel => 'Sender Email (Optional)';

  @override
  String get smtpSenderEmailHint => 'e.g. no-reply@yourdomain.com';

  @override
  String get smtpSenderNameLabel => 'Sender Display Name (Optional)';

  @override
  String get smtpSenderNameHint => 'e.g. Suburban Life Admin';

  @override
  String get testSmtpButton => 'Test Connection & Send Email';

  @override
  String get testRecipientLabel => 'Test Destination Email';

  @override
  String get testRecipientHint => 'your-email@example.com';

  @override
  String get smtpHostRequired => 'Please enter the SMTP Host server.';

  @override
  String get smtpUserRequired =>
      'Please enter the SMTP Username or Auth Email.';

  @override
  String get smtpPassRequired => 'Please enter the SMTP Password or API Key.';

  @override
  String get smtpTestRecipientRequired =>
      'Please enter a valid test destination email address.';

  @override
  String get testSmtpSuccess =>
      'SMTP connection verified! Test email sent successfully.';

  @override
  String testSmtpFailure(String error) {
    return 'SMTP test failed: $error';
  }

  @override
  String get smtpBadgeActive => 'SMTP Welcome Emails Active';

  @override
  String get smtpBadgeInactive => 'SMTP Inactive (No emails will be sent)';

  @override
  String get saveSettingsButton => 'Save Settings';

  @override
  String get emailSentStatus => 'Email Sent';

  @override
  String get emailFailedStatus => 'Email Failed';

  @override
  String get emailSkippedStatus => 'Email Skipped (SMTP Disabled)';

  @override
  String get customWelcomeEmailSection => 'Custom Welcome Message Template';

  @override
  String get customWelcomeEmailSubtitle =>
      'Customize the welcome email sent to new accounts. Use placeholders to insert account details dynamically.';

  @override
  String get emailSubjectLabel => 'Email Subject';

  @override
  String get emailSubjectHint => 'e.g. Welcome to %appName%! Login Credentials';

  @override
  String get emailBodyLabel => 'Email Message Body';

  @override
  String get emailBodyHint => 'Enter your welcome message template here...';

  @override
  String get availablePlaceholdersLabel =>
      'Available Placeholders (click to insert):';

  @override
  String get resetDefaultTemplateButton => 'Reset to Default Template';

  @override
  String get defaultWelcomeSubject => 'Welcome to %appName%! Login Credentials';

  @override
  String get defaultWelcomeBody =>
      'Hello %name%,\n\nYour %role% account has been created successfully. Below are your login credentials:\n\n- Email: %email%\n- Password: %password%\n- Address: %address%\n\nWe recommend logging in and updating your password.\n\nBest regards,\nAdministration of %appName%';

  @override
  String get createUserMenu => 'Create User';

  @override
  String get createUserTitle => 'Create User Account';

  @override
  String get userTypeLabel => 'User Type';

  @override
  String get guardInfoBanner =>
      'Security guard accounts have permissions to scan visitor QR passes, log entry access, and verify guest IDs.';

  @override
  String get adminInfoBanner =>
      'Administrator accounts have full control. This user will be automatically linked to the \'Admin office\' address.';

  @override
  String get userCreatedSuccess => 'User account created successfully!';

  @override
  String get createUserButton => 'Create User Account';

  @override
  String get generatePasswordButton => 'Generate Password';

  @override
  String get selectStreetPrompt => 'Select Street';

  @override
  String get selectNumberPrompt => 'Select House Number';

  @override
  String get noAvailableAddressesError =>
      'No available unclaimed addresses found on this street.';

  @override
  String get addressMustBeSelected =>
      'Please select a street and house number for the resident.';

  @override
  String get fullNameLabel => 'Full Name';

  @override
  String get fullNameHint => 'e.g. John Doe';

  @override
  String get emailAddressLabel => 'Email Address';

  @override
  String get emailAddressHint => 'e.g. user@example.com';

  @override
  String get passwordLabel => 'Password';

  @override
  String get passwordHint => 'Min 6 characters';

  @override
  String get selectAddressLabel => 'Assigned Address';

  @override
  String get userManagementMenu => 'User Account Details';

  @override
  String get shareQrAccessMessage => 'Here is your access QR code!';

  @override
  String get supplierSingleDayValidity => 'Valid today only (Single use)';

  @override
  String get cardGuestName => 'Guest Name';

  @override
  String get cardAuthorizedAddress => 'Authorized Address';

  @override
  String get cardAccessCategory => 'Access Category';

  @override
  String get cardValidity => 'Validity';

  @override
  String get cardVehicleDetails => 'Vehicle Details';

  @override
  String get passwordComplexityRequirements =>
      'Password must be at least 8 characters long and contain at least 1 uppercase letter, 1 lowercase letter, and 1 number.';

  @override
  String get passwordComplexityHelper =>
      'Min. 8 characters (1 uppercase, 1 lowercase, 1 number)';

  @override
  String get passwordComplexityError =>
      'The password does not meet the security requirements.';

  @override
  String get ok => 'OK';

  @override
  String get close => 'Close';

  @override
  String get save => 'Save';

  @override
  String errorPrefix(String error) {
    return 'Error: $error';
  }

  @override
  String get userNotLoggedIn => 'User not logged in';

  @override
  String get guestFallback => 'Guest';

  @override
  String get switchToResidentViewTooltip => 'Switch to Resident View';

  @override
  String get switchToAdminViewTooltip => 'Switch to Admin View';

  @override
  String get notificationHistoryTitle => 'Notification History';

  @override
  String get notificationHistoryPlaceholder =>
      'History will be displayed here (FCM).';

  @override
  String qrItemCreated(String date) {
    return 'Created: $date';
  }

  @override
  String qrItemPlates(String plates) {
    return 'Plates: $plates';
  }

  @override
  String get qrInvalidatedSuccess => 'QR Code invalidated.';

  @override
  String get enterGuestNamePrompt => 'Please enter the guest name';

  @override
  String get qrGenerationFailed => 'Failed to generate QR code';

  @override
  String qrSharingError(String error) {
    return 'Error sharing/downloading: $error';
  }

  @override
  String get bookingCreatedSuccess => 'Booking successfully created!';

  @override
  String bookingStatusLabel(String status) {
    return 'Status: $status';
  }

  @override
  String get bookingCancelledSuccess => 'Booking cancelled.';

  @override
  String get editRejectedBookingTitle => 'Edit Rejected Booking';

  @override
  String get bookingResubmittedSuccess => 'Booking resubmitted for review.';

  @override
  String get resubmitButton => 'Resubmit';

  @override
  String get addressDetailsNotFound => 'Address details not found.';

  @override
  String get passwordMinLengthValidation =>
      'Password must be at least 6 characters.';

  @override
  String get addressUnlinkedSuccess => 'Address unlinked successfully.';

  @override
  String get resetPasswordButton => 'Reset Pwd';

  @override
  String get guardFormValidation =>
      'Please provide a valid name, email, and password (min 6 chars).';

  @override
  String errorProvisioningGuard(String error) {
    return 'Error provisioning guard: $error';
  }

  @override
  String errorRemovingGuard(String error) {
    return 'Error removing guard: $error';
  }

  @override
  String get noGuardsProvisioned => 'No security guards provisioned yet.';

  @override
  String errorDeletingFacility(String error) {
    return 'Error deleting: $error';
  }

  @override
  String get noAmenitiesRegistered => 'No amenities registered yet.';

  @override
  String get approvePaymentButton => 'Approve Payment';

  @override
  String errorReadingFile(String error) {
    return 'Error reading file: $error';
  }

  @override
  String importError(String error) {
    return 'Import error: $error';
  }

  @override
  String errorSavingFile(String error) {
    return 'Error saving file: $error';
  }

  @override
  String userSummaryEmail(String email) {
    return 'Email: $email';
  }

  @override
  String userSummaryStatus(String status) {
    return 'Status: $status';
  }

  @override
  String userSummaryAssignedPassword(String password) {
    return 'Assigned Password: $password';
  }

  @override
  String userSummaryLinkedAddress(String address) {
    return 'Linked Address: $address';
  }

  @override
  String addressExclusionsLabel(String exclusions) {
    return 'Exclusions: $exclusions';
  }

  @override
  String get accessLogsMenu => 'Access History & Logs';

  @override
  String get accessLogsTitle => 'Access Logs';

  @override
  String get filterByAddress => 'Filter by Address';

  @override
  String get allAddresses => 'All Addresses';

  @override
  String get filterByDate => 'Date Filter';

  @override
  String get allDates => 'All Dates';

  @override
  String get today => 'Today';

  @override
  String get thisWeek => 'This Week';

  @override
  String get thisMonth => 'This Month';

  @override
  String get customDateRange => 'Custom Date Range';

  @override
  String get filterByType => 'Visitor Type';

  @override
  String get allTypes => 'All Types';

  @override
  String get visitorTypeGuest => 'Guest';

  @override
  String get visitorTypeSupplier => 'Provider';

  @override
  String get searchVisitorOrPlate => 'Search visitor name, plate or reason...';

  @override
  String get totalAccesses => 'Total Events';

  @override
  String get allowedAccesses => 'Allowed';

  @override
  String get deniedAccesses => 'Denied';

  @override
  String get providerAccesses => 'Providers';

  @override
  String get noAccessLogsFound => 'No access logs match the selected filters.';

  @override
  String get verifiedByGuard => 'Guard';

  @override
  String get invitedByResident => 'Resident';

  @override
  String get destinationAddress => 'Destination';

  @override
  String get vehicleDetails => 'Vehicle';

  @override
  String get viewVisitorIdPhoto => 'Visitor ID Photo';

  @override
  String get viewPlatePhoto => 'Vehicle Plate Photo';

  @override
  String get reasonOrNotes => 'Notes / Reason';

  @override
  String get accessAllowed => 'Allowed';

  @override
  String get accessDenied => 'Denied';

  @override
  String logPassengersCount(int count) {
    return 'Passengers: $count';
  }
}
