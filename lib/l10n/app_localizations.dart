import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Suburban Life'**
  String get appName;

  /// No description provided for @welcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Suburban Life'**
  String get welcome;

  /// No description provided for @welcomeUser.
  ///
  /// In en, this message translates to:
  /// **'Hello, {name}!'**
  String welcomeUser(String name);

  /// No description provided for @bookFacility.
  ///
  /// In en, this message translates to:
  /// **'Book a Facility'**
  String get bookFacility;

  /// No description provided for @transparencyDocs.
  ///
  /// In en, this message translates to:
  /// **'Transparency Documents'**
  String get transparencyDocs;

  /// No description provided for @monthlyPayment.
  ///
  /// In en, this message translates to:
  /// **'Monthly Payment'**
  String get monthlyPayment;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get login;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @loginSuccess.
  ///
  /// In en, this message translates to:
  /// **'Login successful'**
  String get loginSuccess;

  /// No description provided for @loginFailed.
  ///
  /// In en, this message translates to:
  /// **'Login failed'**
  String get loginFailed;

  /// No description provided for @scanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Access'**
  String get scanQr;

  /// No description provided for @generateQr.
  ///
  /// In en, this message translates to:
  /// **'Generate Access QR'**
  String get generateQr;

  /// No description provided for @type.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get type;

  /// No description provided for @expires.
  ///
  /// In en, this message translates to:
  /// **'Expires'**
  String get expires;

  /// No description provided for @facilityBooking.
  ///
  /// In en, this message translates to:
  /// **'Amenities Booking'**
  String get facilityBooking;

  /// No description provided for @reserveFacility.
  ///
  /// In en, this message translates to:
  /// **'Reserve a Facility'**
  String get reserveFacility;

  /// No description provided for @selectFacility.
  ///
  /// In en, this message translates to:
  /// **'Select Facility'**
  String get selectFacility;

  /// No description provided for @confirmBooking.
  ///
  /// In en, this message translates to:
  /// **'Confirm Booking'**
  String get confirmBooking;

  /// No description provided for @upcomingBookings.
  ///
  /// In en, this message translates to:
  /// **'Upcoming Bookings'**
  String get upcomingBookings;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @from.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get from;

  /// No description provided for @to.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get to;

  /// No description provided for @noBookings.
  ///
  /// In en, this message translates to:
  /// **'No upcoming bookings for this facility.'**
  String get noBookings;

  /// No description provided for @filterByCategory.
  ///
  /// In en, this message translates to:
  /// **'Filter by Category: '**
  String get filterByCategory;

  /// No description provided for @noDocuments.
  ///
  /// In en, this message translates to:
  /// **'No documents available in this category.'**
  String get noDocuments;

  /// No description provided for @maintenancePayment.
  ///
  /// In en, this message translates to:
  /// **'Maintenance Payment'**
  String get maintenancePayment;

  /// No description provided for @monthlyQuota.
  ///
  /// In en, this message translates to:
  /// **'Monthly Maintenance Quota'**
  String get monthlyQuota;

  /// No description provided for @currentStatus.
  ///
  /// In en, this message translates to:
  /// **'Current Status'**
  String get currentStatus;

  /// No description provided for @takePhotoReceipt.
  ///
  /// In en, this message translates to:
  /// **'Take Photo of Receipt'**
  String get takePhotoReceipt;

  /// No description provided for @receiptNotice.
  ///
  /// In en, this message translates to:
  /// **'Note: Only direct camera captures of maintenance receipts are allowed to ensure authenticity.'**
  String get receiptNotice;

  /// No description provided for @announcements.
  ///
  /// In en, this message translates to:
  /// **'Announcements'**
  String get announcements;

  /// No description provided for @createAnnouncement.
  ///
  /// In en, this message translates to:
  /// **'Create Announcement'**
  String get createAnnouncement;

  /// No description provided for @titleSpanish.
  ///
  /// In en, this message translates to:
  /// **'Title (Spanish)'**
  String get titleSpanish;

  /// No description provided for @contentSpanish.
  ///
  /// In en, this message translates to:
  /// **'Content (Spanish)'**
  String get contentSpanish;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @errorAnnouncements.
  ///
  /// In en, this message translates to:
  /// **'Error loading announcements'**
  String get errorAnnouncements;

  /// No description provided for @noAnnouncements.
  ///
  /// In en, this message translates to:
  /// **'No announcements yet'**
  String get noAnnouncements;

  /// No description provided for @attachImage.
  ///
  /// In en, this message translates to:
  /// **'Attach Image'**
  String get attachImage;

  /// No description provided for @pasteFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste from Clipboard'**
  String get pasteFromClipboard;

  /// No description provided for @changeImage.
  ///
  /// In en, this message translates to:
  /// **'Change Image'**
  String get changeImage;

  /// No description provided for @removeImage.
  ///
  /// In en, this message translates to:
  /// **'Remove Image'**
  String get removeImage;

  /// No description provided for @imagePastedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Image attached from clipboard!'**
  String get imagePastedSuccess;

  /// No description provided for @noImageInClipboard.
  ///
  /// In en, this message translates to:
  /// **'No image found in clipboard. Please copy an image first.'**
  String get noImageInClipboard;

  /// No description provided for @pasteImageHint.
  ///
  /// In en, this message translates to:
  /// **'Or press Ctrl+V / Cmd+V to paste an image'**
  String get pasteImageHint;

  /// No description provided for @emojisLabel.
  ///
  /// In en, this message translates to:
  /// **'Quick Emojis:'**
  String get emojisLabel;

  /// No description provided for @insertEmojiHint.
  ///
  /// In en, this message translates to:
  /// **'Tap an emoji to insert it into the message'**
  String get insertEmojiHint;

  /// No description provided for @viewFullImage.
  ///
  /// In en, this message translates to:
  /// **'View Image'**
  String get viewFullImage;

  /// No description provided for @imageUploadError.
  ///
  /// In en, this message translates to:
  /// **'Failed to upload image: {error}'**
  String imageUploadError(String error);

  /// No description provided for @announcementCreatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Announcement published successfully!'**
  String get announcementCreatedSuccess;

  /// No description provided for @fillRequiredFields.
  ///
  /// In en, this message translates to:
  /// **'Please fill in both title and content.'**
  String get fillRequiredFields;

  /// No description provided for @multipurposeRoom.
  ///
  /// In en, this message translates to:
  /// **'Multipurpose Room'**
  String get multipurposeRoom;

  /// No description provided for @bicycle1.
  ///
  /// In en, this message translates to:
  /// **'Bicycle 1'**
  String get bicycle1;

  /// No description provided for @roofGarden.
  ///
  /// In en, this message translates to:
  /// **'Roof Garden'**
  String get roofGarden;

  /// No description provided for @noticesGrid.
  ///
  /// In en, this message translates to:
  /// **'Notices'**
  String get noticesGrid;

  /// No description provided for @transparencyGrid.
  ///
  /// In en, this message translates to:
  /// **'Transparency'**
  String get transparencyGrid;

  /// No description provided for @generateQrGrid.
  ///
  /// In en, this message translates to:
  /// **'Generate QR'**
  String get generateQrGrid;

  /// No description provided for @familyGroupGrid.
  ///
  /// In en, this message translates to:
  /// **'Family Group'**
  String get familyGroupGrid;

  /// No description provided for @allInOrder.
  ///
  /// In en, this message translates to:
  /// **'All in order'**
  String get allInOrder;

  /// No description provided for @noDebts.
  ///
  /// In en, this message translates to:
  /// **'No debts'**
  String get noDebts;

  /// No description provided for @paymentUnderReview.
  ///
  /// In en, this message translates to:
  /// **'Payment under review'**
  String get paymentUnderReview;

  /// No description provided for @paymentRequired.
  ///
  /// In en, this message translates to:
  /// **'Payment required'**
  String get paymentRequired;

  /// No description provided for @receiptUnderReview.
  ///
  /// In en, this message translates to:
  /// **'Your receipt is being reviewed'**
  String get receiptUnderReview;

  /// No description provided for @pleaseMakePayment.
  ///
  /// In en, this message translates to:
  /// **'Please make your payment'**
  String get pleaseMakePayment;

  /// No description provided for @accessRestricted.
  ///
  /// In en, this message translates to:
  /// **'Access restricted'**
  String get accessRestricted;

  /// No description provided for @accountRestrictedMsg.
  ///
  /// In en, this message translates to:
  /// **'Your account is restricted due to missing payment'**
  String get accountRestrictedMsg;

  /// No description provided for @pendingReview.
  ///
  /// In en, this message translates to:
  /// **'Pending Review'**
  String get pendingReview;

  /// No description provided for @approvedUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Approved (Upcoming)'**
  String get approvedUpcoming;

  /// No description provided for @approvedInUse.
  ///
  /// In en, this message translates to:
  /// **'Approved (In Use)'**
  String get approvedInUse;

  /// No description provided for @closed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get closed;

  /// No description provided for @rejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get rejected;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @deactivated.
  ///
  /// In en, this message translates to:
  /// **'Deactivated'**
  String get deactivated;

  /// No description provided for @deactivatedRevoked.
  ///
  /// In en, this message translates to:
  /// **'Deactivated (Revoked)'**
  String get deactivatedRevoked;

  /// No description provided for @deactivatedExpired.
  ///
  /// In en, this message translates to:
  /// **'Deactivated (Expired)'**
  String get deactivatedExpired;

  /// No description provided for @deactivatedValidated.
  ///
  /// In en, this message translates to:
  /// **'Deactivated (Validated)'**
  String get deactivatedValidated;

  /// No description provided for @shareQrVisitor.
  ///
  /// In en, this message translates to:
  /// **'Share this QR code with your visitor.'**
  String get shareQrVisitor;

  /// No description provided for @addRoommate.
  ///
  /// In en, this message translates to:
  /// **'Add Member'**
  String get addRoommate;

  /// No description provided for @enterEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter email address'**
  String get enterEmail;

  /// No description provided for @noRoommates.
  ///
  /// In en, this message translates to:
  /// **'No members in your family group.'**
  String get noRoommates;

  /// No description provided for @roommateRemovedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Family member removed successfully.'**
  String get roommateRemovedSuccess;

  /// No description provided for @guestName.
  ///
  /// In en, this message translates to:
  /// **'Guest Name'**
  String get guestName;

  /// No description provided for @vehiclePlates.
  ///
  /// In en, this message translates to:
  /// **'Vehicle Plates (Optional)'**
  String get vehiclePlates;

  /// No description provided for @signUpOption.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? Sign Up'**
  String get signUpOption;

  /// No description provided for @forgotPasswordOption.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get forgotPasswordOption;

  /// No description provided for @signUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Resident Sign Up'**
  String get signUpTitle;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get fullName;

  /// No description provided for @signUpButton.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get signUpButton;

  /// No description provided for @signUpSuccess.
  ///
  /// In en, this message translates to:
  /// **'Account created successfully. Welcome!'**
  String get signUpSuccess;

  /// No description provided for @signUpFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create account. Please try again.'**
  String get signUpFailed;

  /// No description provided for @resetPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get resetPasswordTitle;

  /// No description provided for @resetPasswordInstructions.
  ///
  /// In en, this message translates to:
  /// **'Enter your email address and we will send you instructions to reset your password.'**
  String get resetPasswordInstructions;

  /// No description provided for @sendResetLinkButton.
  ///
  /// In en, this message translates to:
  /// **'Send Reset Link'**
  String get sendResetLinkButton;

  /// No description provided for @resetLinkSent.
  ///
  /// In en, this message translates to:
  /// **'Password reset link sent to your email.'**
  String get resetLinkSent;

  /// No description provided for @resetLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to send reset link. Check your email and try again.'**
  String get resetLinkFailed;

  /// No description provided for @backToLogin.
  ///
  /// In en, this message translates to:
  /// **'Back to Sign In'**
  String get backToLogin;

  /// No description provided for @selectAddressTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Your Address'**
  String get selectAddressTitle;

  /// No description provided for @searchAddressPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search street name...'**
  String get searchAddressPlaceholder;

  /// No description provided for @noUnclaimedAddresses.
  ///
  /// In en, this message translates to:
  /// **'No unclaimed addresses found.'**
  String get noUnclaimedAddresses;

  /// No description provided for @addressLinkedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Address successfully linked to your account!'**
  String get addressLinkedSuccess;

  /// No description provided for @validatingQr.
  ///
  /// In en, this message translates to:
  /// **'Validating QR Code...'**
  String get validatingQr;

  /// No description provided for @invalidQrNotFound.
  ///
  /// In en, this message translates to:
  /// **'Invalid QR Code (Not found)'**
  String get invalidQrNotFound;

  /// No description provided for @qrInvalidated.
  ///
  /// In en, this message translates to:
  /// **'QR Code has been invalidated'**
  String get qrInvalidated;

  /// No description provided for @qrExpired.
  ///
  /// In en, this message translates to:
  /// **'QR Code has expired'**
  String get qrExpired;

  /// No description provided for @accessGrantedHeader.
  ///
  /// In en, this message translates to:
  /// **'Access Validation'**
  String get accessGrantedHeader;

  /// No description provided for @captureIdPhoto.
  ///
  /// In en, this message translates to:
  /// **'Capture ID Photo'**
  String get captureIdPhoto;

  /// No description provided for @capturePlatePhoto.
  ///
  /// In en, this message translates to:
  /// **'Capture Plate Photo'**
  String get capturePlatePhoto;

  /// No description provided for @uploadingImages.
  ///
  /// In en, this message translates to:
  /// **'Processing and uploading images...'**
  String get uploadingImages;

  /// No description provided for @allowAccessButton.
  ///
  /// In en, this message translates to:
  /// **'Allow Access'**
  String get allowAccessButton;

  /// No description provided for @denyAccessButton.
  ///
  /// In en, this message translates to:
  /// **'Deny Access'**
  String get denyAccessButton;

  /// No description provided for @accessRegisteredSuccess.
  ///
  /// In en, this message translates to:
  /// **'Access registered successfully'**
  String get accessRegisteredSuccess;

  /// No description provided for @scanAgainButton.
  ///
  /// In en, this message translates to:
  /// **'Scan Again'**
  String get scanAgainButton;

  /// No description provided for @visitorDetails.
  ///
  /// In en, this message translates to:
  /// **'Visitor Details'**
  String get visitorDetails;

  /// No description provided for @reasonOptional.
  ///
  /// In en, this message translates to:
  /// **'Reason (Optional)'**
  String get reasonOptional;

  /// No description provided for @homepage.
  ///
  /// In en, this message translates to:
  /// **'Homepage'**
  String get homepage;

  /// No description provided for @manageBookings.
  ///
  /// In en, this message translates to:
  /// **'Manage Bookings'**
  String get manageBookings;

  /// No description provided for @managePayments.
  ///
  /// In en, this message translates to:
  /// **'Manage Payments'**
  String get managePayments;

  /// No description provided for @manageQrCodes.
  ///
  /// In en, this message translates to:
  /// **'Manage QR Codes'**
  String get manageQrCodes;

  /// No description provided for @noQrCodes.
  ///
  /// In en, this message translates to:
  /// **'No QR codes found.'**
  String get noQrCodes;

  /// No description provided for @statusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get statusPaid;

  /// No description provided for @statusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get statusPending;

  /// No description provided for @statusReviewing.
  ///
  /// In en, this message translates to:
  /// **'Under Review'**
  String get statusReviewing;

  /// No description provided for @statusRestricted.
  ///
  /// In en, this message translates to:
  /// **'Restricted'**
  String get statusRestricted;

  /// No description provided for @qrTypePermanent.
  ///
  /// In en, this message translates to:
  /// **'Permanent'**
  String get qrTypePermanent;

  /// No description provided for @qrTypeTemporary.
  ///
  /// In en, this message translates to:
  /// **'Temporary'**
  String get qrTypeTemporary;

  /// No description provided for @shareCodeButton.
  ///
  /// In en, this message translates to:
  /// **'Share Code'**
  String get shareCodeButton;

  /// No description provided for @guardPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Security Guard Panel'**
  String get guardPanelTitle;

  /// No description provided for @guardInstructions.
  ///
  /// In en, this message translates to:
  /// **'Scan visitor QR codes to validate entry and register access.'**
  String get guardInstructions;

  /// No description provided for @vehicleType.
  ///
  /// In en, this message translates to:
  /// **'Entry Type'**
  String get vehicleType;

  /// No description provided for @vehicleCar.
  ///
  /// In en, this message translates to:
  /// **'Car'**
  String get vehicleCar;

  /// No description provided for @vehicleMotorcycle.
  ///
  /// In en, this message translates to:
  /// **'Motorcycle'**
  String get vehicleMotorcycle;

  /// No description provided for @vehicleWalking.
  ///
  /// In en, this message translates to:
  /// **'Walking'**
  String get vehicleWalking;

  /// No description provided for @passengersCount.
  ///
  /// In en, this message translates to:
  /// **'Number of Passengers'**
  String get passengersCount;

  /// No description provided for @copyCodeButton.
  ///
  /// In en, this message translates to:
  /// **'Copy Code'**
  String get copyCodeButton;

  /// No description provided for @copyCodeSuccess.
  ///
  /// In en, this message translates to:
  /// **'Code copied to clipboard'**
  String get copyCodeSuccess;

  /// No description provided for @downloadCodeButton.
  ///
  /// In en, this message translates to:
  /// **'Download Code'**
  String get downloadCodeButton;

  /// No description provided for @downloadCodeSuccess.
  ///
  /// In en, this message translates to:
  /// **'Code downloaded successfully'**
  String get downloadCodeSuccess;

  /// No description provided for @selectStreetLabel.
  ///
  /// In en, this message translates to:
  /// **'Select Street'**
  String get selectStreetLabel;

  /// No description provided for @selectNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Select Number'**
  String get selectNumberLabel;

  /// No description provided for @confirmAddressButton.
  ///
  /// In en, this message translates to:
  /// **'Confirm Address'**
  String get confirmAddressButton;

  /// No description provided for @accessCategory.
  ///
  /// In en, this message translates to:
  /// **'Access Category'**
  String get accessCategory;

  /// No description provided for @categoryVisitor.
  ///
  /// In en, this message translates to:
  /// **'Visitor'**
  String get categoryVisitor;

  /// No description provided for @categorySupplier.
  ///
  /// In en, this message translates to:
  /// **'Supplier'**
  String get categorySupplier;

  /// No description provided for @ownershipProofTitle.
  ///
  /// In en, this message translates to:
  /// **'Proof of Ownership'**
  String get ownershipProofTitle;

  /// No description provided for @ownershipProofInstructions.
  ///
  /// In en, this message translates to:
  /// **'Please upload a clear photo of your proof of ownership. This can be the house deeds, \'Property Handover Certificate\', or a previous maintenance receipt.'**
  String get ownershipProofInstructions;

  /// No description provided for @captureProofPhoto.
  ///
  /// In en, this message translates to:
  /// **'Take Photo'**
  String get captureProofPhoto;

  /// No description provided for @selectProofPhoto.
  ///
  /// In en, this message translates to:
  /// **'Select from Gallery'**
  String get selectProofPhoto;

  /// No description provided for @uploadProofButton.
  ///
  /// In en, this message translates to:
  /// **'Submit for Review'**
  String get uploadProofButton;

  /// No description provided for @uploadingProof.
  ///
  /// In en, this message translates to:
  /// **'Uploading proof of ownership...'**
  String get uploadingProof;

  /// No description provided for @proofUploadedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Proof submitted successfully. Awaiting admin approval.'**
  String get proofUploadedSuccess;

  /// No description provided for @accountUnderReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Account Under Review'**
  String get accountUnderReviewTitle;

  /// No description provided for @accountUnderReviewMessage.
  ///
  /// In en, this message translates to:
  /// **'Your proof of ownership is currently being reviewed by an administrator. You will receive access to the app\'s features once approved.'**
  String get accountUnderReviewMessage;

  /// No description provided for @cancelReviewButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel Review'**
  String get cancelReviewButton;

  /// No description provided for @reviewCancelledSuccess.
  ///
  /// In en, this message translates to:
  /// **'Review cancelled. You can now claim a different address.'**
  String get reviewCancelledSuccess;

  /// No description provided for @approveResidentsMenu.
  ///
  /// In en, this message translates to:
  /// **'Approve Residents'**
  String get approveResidentsMenu;

  /// No description provided for @noResidentsToApprove.
  ///
  /// In en, this message translates to:
  /// **'No residents pending approval.'**
  String get noResidentsToApprove;

  /// No description provided for @approveResidentButton.
  ///
  /// In en, this message translates to:
  /// **'Approve Resident'**
  String get approveResidentButton;

  /// No description provided for @rejectResidentButton.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get rejectResidentButton;

  /// No description provided for @residentApprovedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Resident approved successfully.'**
  String get residentApprovedSuccess;

  /// No description provided for @claimAnotherAddressMenu.
  ///
  /// In en, this message translates to:
  /// **'Claim Another Address'**
  String get claimAnotherAddressMenu;

  /// No description provided for @adminPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Admin Panel'**
  String get adminPanelTitle;

  /// No description provided for @manageTransparencyDocs.
  ///
  /// In en, this message translates to:
  /// **'Manage Transparency Docs'**
  String get manageTransparencyDocs;

  /// No description provided for @manageAnnouncements.
  ///
  /// In en, this message translates to:
  /// **'Manage Announcements'**
  String get manageAnnouncements;

  /// No description provided for @registerResidentMenu.
  ///
  /// In en, this message translates to:
  /// **'Register Resident / Roommate'**
  String get registerResidentMenu;

  /// No description provided for @reviewPaymentsMenu.
  ///
  /// In en, this message translates to:
  /// **'Review Payments'**
  String get reviewPaymentsMenu;

  /// No description provided for @uploadPaymentOnBehalfMenu.
  ///
  /// In en, this message translates to:
  /// **'Upload Payment on Behalf'**
  String get uploadPaymentOnBehalfMenu;

  /// No description provided for @manageUsersMenu.
  ///
  /// In en, this message translates to:
  /// **'User Directory & Roles'**
  String get manageUsersMenu;

  /// No description provided for @manageFacilitiesMenu.
  ///
  /// In en, this message translates to:
  /// **'Manage Amenities'**
  String get manageFacilitiesMenu;

  /// No description provided for @adminSettingsMenu.
  ///
  /// In en, this message translates to:
  /// **'Maintenance Settings'**
  String get adminSettingsMenu;

  /// No description provided for @resignAdminRole.
  ///
  /// In en, this message translates to:
  /// **'Resign Admin Role'**
  String get resignAdminRole;

  /// No description provided for @resignAdminConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to step down as an Admin? This action will revoke your admin privileges immediately.'**
  String get resignAdminConfirm;

  /// No description provided for @revokeAdminButton.
  ///
  /// In en, this message translates to:
  /// **'Revoke Admin'**
  String get revokeAdminButton;

  /// No description provided for @promoteAdminButton.
  ///
  /// In en, this message translates to:
  /// **'Promote to Admin'**
  String get promoteAdminButton;

  /// No description provided for @userPromotedSuccess.
  ///
  /// In en, this message translates to:
  /// **'User promoted to Admin successfully'**
  String get userPromotedSuccess;

  /// No description provided for @userRevokedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Admin access revoked successfully'**
  String get userRevokedSuccess;

  /// No description provided for @roleResident.
  ///
  /// In en, this message translates to:
  /// **'Resident'**
  String get roleResident;

  /// No description provided for @roleRoommate.
  ///
  /// In en, this message translates to:
  /// **'Roommate'**
  String get roleRoommate;

  /// No description provided for @roleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get roleAdmin;

  /// No description provided for @roleGuard.
  ///
  /// In en, this message translates to:
  /// **'Guard'**
  String get roleGuard;

  /// No description provided for @adminOffice.
  ///
  /// In en, this message translates to:
  /// **'Admin office'**
  String get adminOffice;

  /// No description provided for @noActiveAddressLinked.
  ///
  /// In en, this message translates to:
  /// **'No active address linked.'**
  String get noActiveAddressLinked;

  /// No description provided for @registerResidentTitle.
  ///
  /// In en, this message translates to:
  /// **'Direct Registration'**
  String get registerResidentTitle;

  /// No description provided for @addressAlreadyClaimedError.
  ///
  /// In en, this message translates to:
  /// **'This address is already claimed by another primary resident.'**
  String get addressAlreadyClaimedError;

  /// No description provided for @roommateRequiresResidentError.
  ///
  /// In en, this message translates to:
  /// **'A roommate can only be added to an address that is already assigned to a primary resident.'**
  String get roommateRequiresResidentError;

  /// No description provided for @userRegisteredSuccess.
  ///
  /// In en, this message translates to:
  /// **'User successfully registered and assigned to address.'**
  String get userRegisteredSuccess;

  /// No description provided for @selectResidentLabel.
  ///
  /// In en, this message translates to:
  /// **'Select Resident'**
  String get selectResidentLabel;

  /// No description provided for @paymentApprovedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Payment approved successfully. Status updated to paid.'**
  String get paymentApprovedSuccess;

  /// No description provided for @paymentRejectedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Payment proof rejected.'**
  String get paymentRejectedSuccess;

  /// No description provided for @selfApprovalBlockedError.
  ///
  /// In en, this message translates to:
  /// **'You cannot approve a payment proof that you uploaded yourself.'**
  String get selfApprovalBlockedError;

  /// No description provided for @addFacilityTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Amenity'**
  String get addFacilityTitle;

  /// No description provided for @facilityIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Amenity ID (e.g., multipurpose_room)'**
  String get facilityIdLabel;

  /// No description provided for @facilityNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Display Name'**
  String get facilityNameLabel;

  /// No description provided for @isUniqueAmenityLabel.
  ///
  /// In en, this message translates to:
  /// **'Unique Amenity (Single capacity)'**
  String get isUniqueAmenityLabel;

  /// No description provided for @quantityLabel.
  ///
  /// In en, this message translates to:
  /// **'Available Quantity'**
  String get quantityLabel;

  /// No description provided for @facilityAddedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Amenity successfully added.'**
  String get facilityAddedSuccess;

  /// No description provided for @settingsSavedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Settings successfully updated.'**
  String get settingsSavedSuccess;

  /// No description provided for @paymentCutoffDayLabel.
  ///
  /// In en, this message translates to:
  /// **'Payment Cutoff Day of Month'**
  String get paymentCutoffDayLabel;

  /// No description provided for @gracePeriodDaysLabel.
  ///
  /// In en, this message translates to:
  /// **'Grace Period (Days)'**
  String get gracePeriodDaysLabel;

  /// No description provided for @uploadDocumentTitle.
  ///
  /// In en, this message translates to:
  /// **'Upload Document'**
  String get uploadDocumentTitle;

  /// No description provided for @documentTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Document Title'**
  String get documentTitleLabel;

  /// No description provided for @categoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get categoryLabel;

  /// No description provided for @uploadButton.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get uploadButton;

  /// No description provided for @uploadingDocument.
  ///
  /// In en, this message translates to:
  /// **'Uploading document...'**
  String get uploadingDocument;

  /// No description provided for @documentUploadedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Document uploaded successfully!'**
  String get documentUploadedSuccess;

  /// No description provided for @untitledDocument.
  ///
  /// In en, this message translates to:
  /// **'Untitled Document'**
  String get untitledDocument;

  /// No description provided for @downloadingDocument.
  ///
  /// In en, this message translates to:
  /// **'Downloading document...'**
  String get downloadingDocument;

  /// No description provided for @downloadReportMenu.
  ///
  /// In en, this message translates to:
  /// **'Download Payment Report'**
  String get downloadReportMenu;

  /// No description provided for @generateReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment Matrix Report'**
  String get generateReportTitle;

  /// No description provided for @startMonthLabel.
  ///
  /// In en, this message translates to:
  /// **'Start Month'**
  String get startMonthLabel;

  /// No description provided for @endMonthLabel.
  ///
  /// In en, this message translates to:
  /// **'End Month'**
  String get endMonthLabel;

  /// No description provided for @generatingReport.
  ///
  /// In en, this message translates to:
  /// **'Generating CSV report matrix...'**
  String get generatingReport;

  /// No description provided for @reportSavedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Report file saved successfully!'**
  String get reportSavedSuccess;

  /// No description provided for @statusPastDue.
  ///
  /// In en, this message translates to:
  /// **'Past Due'**
  String get statusPastDue;

  /// No description provided for @manageGuardsMenu.
  ///
  /// In en, this message translates to:
  /// **'Manage Security Guards'**
  String get manageGuardsMenu;

  /// No description provided for @provisionGuardTitle.
  ///
  /// In en, this message translates to:
  /// **'Provision Security Guard'**
  String get provisionGuardTitle;

  /// No description provided for @guardNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Guard Name'**
  String get guardNameLabel;

  /// No description provided for @guardEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Guard Email'**
  String get guardEmailLabel;

  /// No description provided for @guardPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Initial Password'**
  String get guardPasswordLabel;

  /// No description provided for @provisionButton.
  ///
  /// In en, this message translates to:
  /// **'Provision Account'**
  String get provisionButton;

  /// No description provided for @guardProvisionedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Security guard account provisioned successfully.'**
  String get guardProvisionedSuccess;

  /// No description provided for @removeGuardButton.
  ///
  /// In en, this message translates to:
  /// **'Remove Account'**
  String get removeGuardButton;

  /// No description provided for @guardRemovedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Security guard account removed successfully.'**
  String get guardRemovedSuccess;

  /// No description provided for @changePasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Change User Password'**
  String get changePasswordTitle;

  /// No description provided for @newPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get newPasswordLabel;

  /// No description provided for @passwordUpdatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'User password updated successfully.'**
  String get passwordUpdatedSuccess;

  /// No description provided for @privacyNoticeProofDeletion.
  ///
  /// In en, this message translates to:
  /// **'Privacy Notice: To protect your personal data, this proof of ownership document will be permanently removed from our storage servers and database immediately upon admin approval.'**
  String get privacyNoticeProofDeletion;

  /// No description provided for @noDataAlertTitle.
  ///
  /// In en, this message translates to:
  /// **'No Data Found'**
  String get noDataAlertTitle;

  /// No description provided for @noDataAlertMessage.
  ///
  /// In en, this message translates to:
  /// **'No payment records exist for the selected period.'**
  String get noDataAlertMessage;

  /// No description provided for @claimingAddress.
  ///
  /// In en, this message translates to:
  /// **'Claiming: {address}'**
  String claimingAddress(String address);

  /// No description provided for @cooldownUnitLabel.
  ///
  /// In en, this message translates to:
  /// **'Booking Cooldown Unit'**
  String get cooldownUnitLabel;

  /// No description provided for @cooldownValueLabel.
  ///
  /// In en, this message translates to:
  /// **'Cooldown Duration'**
  String get cooldownValueLabel;

  /// No description provided for @cooldownUnrestricted.
  ///
  /// In en, this message translates to:
  /// **'Unrestricted (No Cooldown)'**
  String get cooldownUnrestricted;

  /// No description provided for @cooldownDays.
  ///
  /// In en, this message translates to:
  /// **'Days'**
  String get cooldownDays;

  /// No description provided for @cooldownMonths.
  ///
  /// In en, this message translates to:
  /// **'Months'**
  String get cooldownMonths;

  /// No description provided for @cooldownYears.
  ///
  /// In en, this message translates to:
  /// **'Years'**
  String get cooldownYears;

  /// No description provided for @addressClaimInstructions.
  ///
  /// In en, this message translates to:
  /// **'You can claim a property as a primary resident or show your Household QR Code to be linked by a primary resident.'**
  String get addressClaimInstructions;

  /// No description provided for @roommateOnboardingInstructions.
  ///
  /// In en, this message translates to:
  /// **'Ask your family member to register in the app, and on the address selection screen tap the \'Family Group\' tab to show their QR code or share their User ID/email.'**
  String get roommateOnboardingInstructions;

  /// No description provided for @deliveryDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Property Handover Date'**
  String get deliveryDateLabel;

  /// No description provided for @selectDeliveryDate.
  ///
  /// In en, this message translates to:
  /// **'Select delivery date'**
  String get selectDeliveryDate;

  /// No description provided for @selectPeriodLabel.
  ///
  /// In en, this message translates to:
  /// **'Select maintenance period'**
  String get selectPeriodLabel;

  /// No description provided for @periodPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'e.g. May 2026'**
  String get periodPlaceholder;

  /// No description provided for @noPendingPeriods.
  ///
  /// In en, this message translates to:
  /// **'You have no pending periods of payment.'**
  String get noPendingPeriods;

  /// No description provided for @resignAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Unbind Address'**
  String get resignAddressLabel;

  /// No description provided for @resignConfirmText.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to unbind your account and all roommates from this address?'**
  String get resignConfirmText;

  /// No description provided for @deleteAccountLabel.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get deleteAccountLabel;

  /// No description provided for @deleteAccountConfirmText.
  ///
  /// In en, this message translates to:
  /// **'This action is permanent and will delete all your credentials. Do you want to proceed?'**
  String get deleteAccountConfirmText;

  /// No description provided for @addCategoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Category'**
  String get addCategoryTitle;

  /// No description provided for @categoryNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Category Name'**
  String get categoryNameLabel;

  /// No description provided for @targetAudienceLabel.
  ///
  /// In en, this message translates to:
  /// **'Target Audience'**
  String get targetAudienceLabel;

  /// No description provided for @audienceAll.
  ///
  /// In en, this message translates to:
  /// **'All Users'**
  String get audienceAll;

  /// No description provided for @audienceResidents.
  ///
  /// In en, this message translates to:
  /// **'Residents Only'**
  String get audienceResidents;

  /// No description provided for @joinAsRoommateTitle.
  ///
  /// In en, this message translates to:
  /// **'Join Household as Roommate'**
  String get joinAsRoommateTitle;

  /// No description provided for @joinAsRoommateTab.
  ///
  /// In en, this message translates to:
  /// **'Join as Roommate'**
  String get joinAsRoommateTab;

  /// No description provided for @claimPropertyTab.
  ///
  /// In en, this message translates to:
  /// **'Claim Property'**
  String get claimPropertyTab;

  /// No description provided for @showQrToResidentInstructions.
  ///
  /// In en, this message translates to:
  /// **'Show this QR code to the primary resident of your household. They can scan it from their app to link your account.'**
  String get showQrToResidentInstructions;

  /// No description provided for @myRoommateQrCode.
  ///
  /// In en, this message translates to:
  /// **'My Household QR Code'**
  String get myRoommateQrCode;

  /// No description provided for @copyUidButton.
  ///
  /// In en, this message translates to:
  /// **'Copy User ID'**
  String get copyUidButton;

  /// No description provided for @uidCopiedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'User ID copied to clipboard.'**
  String get uidCopiedSnackbar;

  /// No description provided for @scanRoommateQrButton.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get scanRoommateQrButton;

  /// No description provided for @enterEmailOrUidLabel.
  ///
  /// In en, this message translates to:
  /// **'Enter Roommate Email or User ID (UID)'**
  String get enterEmailOrUidLabel;

  /// No description provided for @roommateQrScannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan Roommate QR Code'**
  String get roommateQrScannerTitle;

  /// No description provided for @invalidRoommateQrCode.
  ///
  /// In en, this message translates to:
  /// **'Invalid Roommate QR Code scanned.'**
  String get invalidRoommateQrCode;

  /// No description provided for @roommateAddedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Family member added successfully.'**
  String get roommateAddedSuccess;

  /// No description provided for @waitingToBeLinked.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a resident to scan or link your account...'**
  String get waitingToBeLinked;

  /// No description provided for @bulkUserImportMenu.
  ///
  /// In en, this message translates to:
  /// **'Bulk User Creation (CSV)'**
  String get bulkUserImportMenu;

  /// No description provided for @bulkUserImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Bulk Resident Creation'**
  String get bulkUserImportTitle;

  /// No description provided for @uploadCsvButton.
  ///
  /// In en, this message translates to:
  /// **'Upload CSV File'**
  String get uploadCsvButton;

  /// No description provided for @copyCsvTemplateButton.
  ///
  /// In en, this message translates to:
  /// **'Copy CSV Template'**
  String get copyCsvTemplateButton;

  /// No description provided for @processImportButton.
  ///
  /// In en, this message translates to:
  /// **'Create Accounts ({count})'**
  String processImportButton(int count);

  /// No description provided for @importSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Completed'**
  String get importSuccessTitle;

  /// No description provided for @importSummaryText.
  ///
  /// In en, this message translates to:
  /// **'{successCount} accounts created successfully, {failureCount} failed.'**
  String importSummaryText(int successCount, int failureCount);

  /// No description provided for @noFileSelected.
  ///
  /// In en, this message translates to:
  /// **'No file selected.'**
  String get noFileSelected;

  /// No description provided for @invalidCsvFormat.
  ///
  /// In en, this message translates to:
  /// **'Invalid CSV format or missing headers.'**
  String get invalidCsvFormat;

  /// No description provided for @copyPasswordsButton.
  ///
  /// In en, this message translates to:
  /// **'Copy Passwords'**
  String get copyPasswordsButton;

  /// No description provided for @passwordsCopiedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Passwords copied to clipboard.'**
  String get passwordsCopiedSnackbar;

  /// No description provided for @csvColumnsHint.
  ///
  /// In en, this message translates to:
  /// **'Expected CSV columns: name, email, password (optional), street (optional), number (optional)'**
  String get csvColumnsHint;

  /// No description provided for @csvTemplateCopiedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'CSV template copied to clipboard.'**
  String get csvTemplateCopiedSnackbar;

  /// No description provided for @downloadResultCsvButton.
  ///
  /// In en, this message translates to:
  /// **'Download Result CSV'**
  String get downloadResultCsvButton;

  /// No description provided for @copyResultCsvButton.
  ///
  /// In en, this message translates to:
  /// **'Copy Result CSV'**
  String get copyResultCsvButton;

  /// No description provided for @csvDownloadedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Result CSV downloaded successfully.'**
  String get csvDownloadedSuccess;

  /// No description provided for @csvCopiedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Result CSV copied to clipboard.'**
  String get csvCopiedSuccess;

  /// No description provided for @bulkAddressImportMenu.
  ///
  /// In en, this message translates to:
  /// **'Bulk Address Creation (CSV)'**
  String get bulkAddressImportMenu;

  /// No description provided for @bulkAddressImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Bulk Address Creation'**
  String get bulkAddressImportTitle;

  /// No description provided for @addressCsvColumnsHint.
  ///
  /// In en, this message translates to:
  /// **'Expected CSV columns: streetName, initialNumber, finalNumber, exclusions (optional)'**
  String get addressCsvColumnsHint;

  /// No description provided for @importAddressesButton.
  ///
  /// In en, this message translates to:
  /// **'Import Addresses ({count})'**
  String importAddressesButton(int count);

  /// No description provided for @addressesImportedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Successfully created {created} addresses ({skipped} skipped/duplicates).'**
  String addressesImportedSuccess(int created, int skipped);

  /// No description provided for @importAnotherFileButton.
  ///
  /// In en, this message translates to:
  /// **'Import Another File'**
  String get importAnotherFileButton;

  /// No description provided for @paymentSettingsSection.
  ///
  /// In en, this message translates to:
  /// **'Payment & Grace Period'**
  String get paymentSettingsSection;

  /// No description provided for @smtpSettingsSection.
  ///
  /// In en, this message translates to:
  /// **'SMTP Email Service'**
  String get smtpSettingsSection;

  /// No description provided for @smtpEnabledLabel.
  ///
  /// In en, this message translates to:
  /// **'Enable Automatic Welcome Emails'**
  String get smtpEnabledLabel;

  /// No description provided for @smtpEnabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Send account credentials to new residents upon creation or bulk import'**
  String get smtpEnabledSubtitle;

  /// No description provided for @smtpHostLabel.
  ///
  /// In en, this message translates to:
  /// **'SMTP Host Server'**
  String get smtpHostLabel;

  /// No description provided for @smtpHostHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. smtp.gmail.com or smtp.sendgrid.net'**
  String get smtpHostHint;

  /// No description provided for @smtpPortLabel.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get smtpPortLabel;

  /// No description provided for @smtpPortHint.
  ///
  /// In en, this message translates to:
  /// **'587, 465, 25'**
  String get smtpPortHint;

  /// No description provided for @smtpSecureLabel.
  ///
  /// In en, this message translates to:
  /// **'Use SSL/TLS (Secure)'**
  String get smtpSecureLabel;

  /// No description provided for @smtpSecureSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enable for port 465, disable for STARTTLS (port 587)'**
  String get smtpSecureSubtitle;

  /// No description provided for @smtpUserLabel.
  ///
  /// In en, this message translates to:
  /// **'Username / Auth Email'**
  String get smtpUserLabel;

  /// No description provided for @smtpUserHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. notifications@yourdomain.com'**
  String get smtpUserHint;

  /// No description provided for @smtpPassLabel.
  ///
  /// In en, this message translates to:
  /// **'Password / API Key'**
  String get smtpPassLabel;

  /// No description provided for @smtpPassHint.
  ///
  /// In en, this message translates to:
  /// **'SMTP password or App Password'**
  String get smtpPassHint;

  /// No description provided for @smtpSenderEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Sender Email (Optional)'**
  String get smtpSenderEmailLabel;

  /// No description provided for @smtpSenderEmailHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. no-reply@yourdomain.com'**
  String get smtpSenderEmailHint;

  /// No description provided for @smtpSenderNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Sender Display Name (Optional)'**
  String get smtpSenderNameLabel;

  /// No description provided for @smtpSenderNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Suburban Life Admin'**
  String get smtpSenderNameHint;

  /// No description provided for @testSmtpButton.
  ///
  /// In en, this message translates to:
  /// **'Test Connection & Send Email'**
  String get testSmtpButton;

  /// No description provided for @testRecipientLabel.
  ///
  /// In en, this message translates to:
  /// **'Test Destination Email'**
  String get testRecipientLabel;

  /// No description provided for @testRecipientHint.
  ///
  /// In en, this message translates to:
  /// **'your-email@example.com'**
  String get testRecipientHint;

  /// No description provided for @smtpHostRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter the SMTP Host server.'**
  String get smtpHostRequired;

  /// No description provided for @smtpUserRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter the SMTP Username or Auth Email.'**
  String get smtpUserRequired;

  /// No description provided for @smtpPassRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter the SMTP Password or API Key.'**
  String get smtpPassRequired;

  /// No description provided for @smtpTestRecipientRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid test destination email address.'**
  String get smtpTestRecipientRequired;

  /// No description provided for @testSmtpSuccess.
  ///
  /// In en, this message translates to:
  /// **'SMTP connection verified! Test email sent successfully.'**
  String get testSmtpSuccess;

  /// No description provided for @testSmtpFailure.
  ///
  /// In en, this message translates to:
  /// **'SMTP test failed: {error}'**
  String testSmtpFailure(String error);

  /// No description provided for @smtpBadgeActive.
  ///
  /// In en, this message translates to:
  /// **'SMTP Welcome Emails Active'**
  String get smtpBadgeActive;

  /// No description provided for @smtpBadgeInactive.
  ///
  /// In en, this message translates to:
  /// **'SMTP Inactive (No emails will be sent)'**
  String get smtpBadgeInactive;

  /// No description provided for @saveSettingsButton.
  ///
  /// In en, this message translates to:
  /// **'Save Settings'**
  String get saveSettingsButton;

  /// No description provided for @emailSentStatus.
  ///
  /// In en, this message translates to:
  /// **'Email Sent'**
  String get emailSentStatus;

  /// No description provided for @emailFailedStatus.
  ///
  /// In en, this message translates to:
  /// **'Email Failed'**
  String get emailFailedStatus;

  /// No description provided for @emailSkippedStatus.
  ///
  /// In en, this message translates to:
  /// **'Email Skipped (SMTP Disabled)'**
  String get emailSkippedStatus;

  /// No description provided for @customWelcomeEmailSection.
  ///
  /// In en, this message translates to:
  /// **'Custom Welcome Message Template'**
  String get customWelcomeEmailSection;

  /// No description provided for @customWelcomeEmailSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Customize the welcome email sent to new accounts. Use placeholders to insert account details dynamically.'**
  String get customWelcomeEmailSubtitle;

  /// No description provided for @emailSubjectLabel.
  ///
  /// In en, this message translates to:
  /// **'Email Subject'**
  String get emailSubjectLabel;

  /// No description provided for @emailSubjectHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Welcome to %appName%! Login Credentials'**
  String get emailSubjectHint;

  /// No description provided for @emailBodyLabel.
  ///
  /// In en, this message translates to:
  /// **'Email Message Body'**
  String get emailBodyLabel;

  /// No description provided for @emailBodyHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your welcome message template here...'**
  String get emailBodyHint;

  /// No description provided for @availablePlaceholdersLabel.
  ///
  /// In en, this message translates to:
  /// **'Available Placeholders (click to insert):'**
  String get availablePlaceholdersLabel;

  /// No description provided for @resetDefaultTemplateButton.
  ///
  /// In en, this message translates to:
  /// **'Reset to Default Template'**
  String get resetDefaultTemplateButton;

  /// No description provided for @defaultWelcomeSubject.
  ///
  /// In en, this message translates to:
  /// **'Welcome to %appName%! Login Credentials'**
  String get defaultWelcomeSubject;

  /// No description provided for @defaultWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Hello %name%,\n\nYour %role% account has been created successfully. Below are your login credentials:\n\n- Email: %email%\n- Password: %password%\n- Address: %address%\n\nWe recommend logging in and updating your password.\n\nBest regards,\nAdministration of %appName%'**
  String get defaultWelcomeBody;

  /// No description provided for @createUserMenu.
  ///
  /// In en, this message translates to:
  /// **'Create User'**
  String get createUserMenu;

  /// No description provided for @createUserTitle.
  ///
  /// In en, this message translates to:
  /// **'Create User Account'**
  String get createUserTitle;

  /// No description provided for @userTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'User Type'**
  String get userTypeLabel;

  /// No description provided for @guardInfoBanner.
  ///
  /// In en, this message translates to:
  /// **'Security guard accounts have permissions to scan visitor QR passes, log entry access, and verify guest IDs.'**
  String get guardInfoBanner;

  /// No description provided for @adminInfoBanner.
  ///
  /// In en, this message translates to:
  /// **'Administrator accounts have full control. This user will be automatically linked to the \'Admin office\' address.'**
  String get adminInfoBanner;

  /// No description provided for @userCreatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'User account created successfully!'**
  String get userCreatedSuccess;

  /// No description provided for @createUserButton.
  ///
  /// In en, this message translates to:
  /// **'Create User Account'**
  String get createUserButton;

  /// No description provided for @generatePasswordButton.
  ///
  /// In en, this message translates to:
  /// **'Generate Password'**
  String get generatePasswordButton;

  /// No description provided for @selectStreetPrompt.
  ///
  /// In en, this message translates to:
  /// **'Select Street'**
  String get selectStreetPrompt;

  /// No description provided for @selectNumberPrompt.
  ///
  /// In en, this message translates to:
  /// **'Select House Number'**
  String get selectNumberPrompt;

  /// No description provided for @noAvailableAddressesError.
  ///
  /// In en, this message translates to:
  /// **'No available unclaimed addresses found on this street.'**
  String get noAvailableAddressesError;

  /// No description provided for @addressMustBeSelected.
  ///
  /// In en, this message translates to:
  /// **'Please select a street and house number for the resident.'**
  String get addressMustBeSelected;

  /// No description provided for @fullNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get fullNameLabel;

  /// No description provided for @fullNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. John Doe'**
  String get fullNameHint;

  /// No description provided for @emailAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Email Address'**
  String get emailAddressLabel;

  /// No description provided for @emailAddressHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. user@example.com'**
  String get emailAddressHint;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @passwordHint.
  ///
  /// In en, this message translates to:
  /// **'Min 6 characters'**
  String get passwordHint;

  /// No description provided for @selectAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Assigned Address'**
  String get selectAddressLabel;

  /// No description provided for @userManagementMenu.
  ///
  /// In en, this message translates to:
  /// **'User Account Details'**
  String get userManagementMenu;

  /// No description provided for @shareQrAccessMessage.
  ///
  /// In en, this message translates to:
  /// **'Here is your access QR code!'**
  String get shareQrAccessMessage;

  /// No description provided for @supplierSingleDayValidity.
  ///
  /// In en, this message translates to:
  /// **'Valid today only (Single use)'**
  String get supplierSingleDayValidity;

  /// No description provided for @cardGuestName.
  ///
  /// In en, this message translates to:
  /// **'Guest Name'**
  String get cardGuestName;

  /// No description provided for @cardAuthorizedAddress.
  ///
  /// In en, this message translates to:
  /// **'Authorized Address'**
  String get cardAuthorizedAddress;

  /// No description provided for @cardAccessCategory.
  ///
  /// In en, this message translates to:
  /// **'Access Category'**
  String get cardAccessCategory;

  /// No description provided for @cardValidity.
  ///
  /// In en, this message translates to:
  /// **'Validity'**
  String get cardValidity;

  /// No description provided for @cardVehicleDetails.
  ///
  /// In en, this message translates to:
  /// **'Vehicle Details'**
  String get cardVehicleDetails;

  /// No description provided for @passwordComplexityRequirements.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters long and contain at least 1 uppercase letter, 1 lowercase letter, and 1 number.'**
  String get passwordComplexityRequirements;

  /// No description provided for @passwordComplexityHelper.
  ///
  /// In en, this message translates to:
  /// **'Min. 8 characters (1 uppercase, 1 lowercase, 1 number)'**
  String get passwordComplexityHelper;

  /// No description provided for @passwordComplexityError.
  ///
  /// In en, this message translates to:
  /// **'The password does not meet the security requirements.'**
  String get passwordComplexityError;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @errorPrefix.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorPrefix(String error);

  /// No description provided for @userNotLoggedIn.
  ///
  /// In en, this message translates to:
  /// **'User not logged in'**
  String get userNotLoggedIn;

  /// No description provided for @guestFallback.
  ///
  /// In en, this message translates to:
  /// **'Guest'**
  String get guestFallback;

  /// No description provided for @switchToResidentViewTooltip.
  ///
  /// In en, this message translates to:
  /// **'Switch to Resident View'**
  String get switchToResidentViewTooltip;

  /// No description provided for @switchToAdminViewTooltip.
  ///
  /// In en, this message translates to:
  /// **'Switch to Admin View'**
  String get switchToAdminViewTooltip;

  /// No description provided for @notificationHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification History'**
  String get notificationHistoryTitle;

  /// No description provided for @notificationHistoryPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'History will be displayed here (FCM).'**
  String get notificationHistoryPlaceholder;

  /// No description provided for @qrItemCreated.
  ///
  /// In en, this message translates to:
  /// **'Created: {date}'**
  String qrItemCreated(String date);

  /// No description provided for @qrItemPlates.
  ///
  /// In en, this message translates to:
  /// **'Plates: {plates}'**
  String qrItemPlates(String plates);

  /// No description provided for @qrInvalidatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'QR Code invalidated.'**
  String get qrInvalidatedSuccess;

  /// No description provided for @enterGuestNamePrompt.
  ///
  /// In en, this message translates to:
  /// **'Please enter the guest name'**
  String get enterGuestNamePrompt;

  /// No description provided for @qrGenerationFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to generate QR code'**
  String get qrGenerationFailed;

  /// No description provided for @qrSharingError.
  ///
  /// In en, this message translates to:
  /// **'Error sharing/downloading: {error}'**
  String qrSharingError(String error);

  /// No description provided for @bookingCreatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Booking successfully created!'**
  String get bookingCreatedSuccess;

  /// No description provided for @bookingStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status: {status}'**
  String bookingStatusLabel(String status);

  /// No description provided for @bookingCancelledSuccess.
  ///
  /// In en, this message translates to:
  /// **'Booking cancelled.'**
  String get bookingCancelledSuccess;

  /// No description provided for @editRejectedBookingTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Rejected Booking'**
  String get editRejectedBookingTitle;

  /// No description provided for @bookingResubmittedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Booking resubmitted for review.'**
  String get bookingResubmittedSuccess;

  /// No description provided for @resubmitButton.
  ///
  /// In en, this message translates to:
  /// **'Resubmit'**
  String get resubmitButton;

  /// No description provided for @addressDetailsNotFound.
  ///
  /// In en, this message translates to:
  /// **'Address details not found.'**
  String get addressDetailsNotFound;

  /// No description provided for @passwordMinLengthValidation.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters.'**
  String get passwordMinLengthValidation;

  /// No description provided for @addressUnlinkedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Address unlinked successfully.'**
  String get addressUnlinkedSuccess;

  /// No description provided for @resetPasswordButton.
  ///
  /// In en, this message translates to:
  /// **'Reset Pwd'**
  String get resetPasswordButton;

  /// No description provided for @guardFormValidation.
  ///
  /// In en, this message translates to:
  /// **'Please provide a valid name, email, and password (min 6 chars).'**
  String get guardFormValidation;

  /// No description provided for @errorProvisioningGuard.
  ///
  /// In en, this message translates to:
  /// **'Error provisioning guard: {error}'**
  String errorProvisioningGuard(String error);

  /// No description provided for @errorRemovingGuard.
  ///
  /// In en, this message translates to:
  /// **'Error removing guard: {error}'**
  String errorRemovingGuard(String error);

  /// No description provided for @noGuardsProvisioned.
  ///
  /// In en, this message translates to:
  /// **'No security guards provisioned yet.'**
  String get noGuardsProvisioned;

  /// No description provided for @errorDeletingFacility.
  ///
  /// In en, this message translates to:
  /// **'Error deleting: {error}'**
  String errorDeletingFacility(String error);

  /// No description provided for @noAmenitiesRegistered.
  ///
  /// In en, this message translates to:
  /// **'No amenities registered yet.'**
  String get noAmenitiesRegistered;

  /// No description provided for @approvePaymentButton.
  ///
  /// In en, this message translates to:
  /// **'Approve Payment'**
  String get approvePaymentButton;

  /// No description provided for @errorReadingFile.
  ///
  /// In en, this message translates to:
  /// **'Error reading file: {error}'**
  String errorReadingFile(String error);

  /// No description provided for @importError.
  ///
  /// In en, this message translates to:
  /// **'Import error: {error}'**
  String importError(String error);

  /// No description provided for @errorSavingFile.
  ///
  /// In en, this message translates to:
  /// **'Error saving file: {error}'**
  String errorSavingFile(String error);

  /// No description provided for @userSummaryEmail.
  ///
  /// In en, this message translates to:
  /// **'Email: {email}'**
  String userSummaryEmail(String email);

  /// No description provided for @userSummaryStatus.
  ///
  /// In en, this message translates to:
  /// **'Status: {status}'**
  String userSummaryStatus(String status);

  /// No description provided for @userSummaryAssignedPassword.
  ///
  /// In en, this message translates to:
  /// **'Assigned Password: {password}'**
  String userSummaryAssignedPassword(String password);

  /// No description provided for @userSummaryLinkedAddress.
  ///
  /// In en, this message translates to:
  /// **'Linked Address: {address}'**
  String userSummaryLinkedAddress(String address);

  /// No description provided for @addressExclusionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Exclusions: {exclusions}'**
  String addressExclusionsLabel(String exclusions);

  /// No description provided for @accessLogsMenu.
  ///
  /// In en, this message translates to:
  /// **'Access History & Logs'**
  String get accessLogsMenu;

  /// No description provided for @accessLogsTitle.
  ///
  /// In en, this message translates to:
  /// **'Access Logs'**
  String get accessLogsTitle;

  /// No description provided for @filterByAddress.
  ///
  /// In en, this message translates to:
  /// **'Filter by Address'**
  String get filterByAddress;

  /// No description provided for @allAddresses.
  ///
  /// In en, this message translates to:
  /// **'All Addresses'**
  String get allAddresses;

  /// No description provided for @filterByDate.
  ///
  /// In en, this message translates to:
  /// **'Date Filter'**
  String get filterByDate;

  /// No description provided for @allDates.
  ///
  /// In en, this message translates to:
  /// **'All Dates'**
  String get allDates;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @thisWeek.
  ///
  /// In en, this message translates to:
  /// **'This Week'**
  String get thisWeek;

  /// No description provided for @thisMonth.
  ///
  /// In en, this message translates to:
  /// **'This Month'**
  String get thisMonth;

  /// No description provided for @customDateRange.
  ///
  /// In en, this message translates to:
  /// **'Custom Date Range'**
  String get customDateRange;

  /// No description provided for @filterByType.
  ///
  /// In en, this message translates to:
  /// **'Visitor Type'**
  String get filterByType;

  /// No description provided for @allTypes.
  ///
  /// In en, this message translates to:
  /// **'All Types'**
  String get allTypes;

  /// No description provided for @visitorTypeGuest.
  ///
  /// In en, this message translates to:
  /// **'Guest'**
  String get visitorTypeGuest;

  /// No description provided for @visitorTypeSupplier.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get visitorTypeSupplier;

  /// No description provided for @searchVisitorOrPlate.
  ///
  /// In en, this message translates to:
  /// **'Search visitor name, plate or reason...'**
  String get searchVisitorOrPlate;

  /// No description provided for @totalAccesses.
  ///
  /// In en, this message translates to:
  /// **'Total Events'**
  String get totalAccesses;

  /// No description provided for @allowedAccesses.
  ///
  /// In en, this message translates to:
  /// **'Allowed'**
  String get allowedAccesses;

  /// No description provided for @deniedAccesses.
  ///
  /// In en, this message translates to:
  /// **'Denied'**
  String get deniedAccesses;

  /// No description provided for @providerAccesses.
  ///
  /// In en, this message translates to:
  /// **'Providers'**
  String get providerAccesses;

  /// No description provided for @noAccessLogsFound.
  ///
  /// In en, this message translates to:
  /// **'No access logs match the selected filters.'**
  String get noAccessLogsFound;

  /// No description provided for @verifiedByGuard.
  ///
  /// In en, this message translates to:
  /// **'Guard'**
  String get verifiedByGuard;

  /// No description provided for @invitedByResident.
  ///
  /// In en, this message translates to:
  /// **'Resident'**
  String get invitedByResident;

  /// No description provided for @destinationAddress.
  ///
  /// In en, this message translates to:
  /// **'Destination'**
  String get destinationAddress;

  /// No description provided for @vehicleDetails.
  ///
  /// In en, this message translates to:
  /// **'Vehicle'**
  String get vehicleDetails;

  /// No description provided for @viewVisitorIdPhoto.
  ///
  /// In en, this message translates to:
  /// **'Visitor ID Photo'**
  String get viewVisitorIdPhoto;

  /// No description provided for @viewPlatePhoto.
  ///
  /// In en, this message translates to:
  /// **'Vehicle Plate Photo'**
  String get viewPlatePhoto;

  /// No description provided for @reasonOrNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes / Reason'**
  String get reasonOrNotes;

  /// No description provided for @accessAllowed.
  ///
  /// In en, this message translates to:
  /// **'Allowed'**
  String get accessAllowed;

  /// No description provided for @accessDenied.
  ///
  /// In en, this message translates to:
  /// **'Denied'**
  String get accessDenied;

  /// No description provided for @logPassengersCount.
  ///
  /// In en, this message translates to:
  /// **'Passengers: {count}'**
  String logPassengersCount(int count);

  /// No description provided for @errorFallbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorFallbackTitle;

  /// No description provided for @errorFallbackMessage.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred. An error report has been automatically recorded.'**
  String get errorFallbackMessage;

  /// No description provided for @errorFallbackRestart.
  ///
  /// In en, this message translates to:
  /// **'Restart App'**
  String get errorFallbackRestart;

  /// No description provided for @fileExplorer.
  ///
  /// In en, this message translates to:
  /// **'File Explorer'**
  String get fileExplorer;

  /// No description provided for @rootFolder.
  ///
  /// In en, this message translates to:
  /// **'Root'**
  String get rootFolder;

  /// No description provided for @newFolder.
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get newFolder;

  /// No description provided for @folderName.
  ///
  /// In en, this message translates to:
  /// **'Folder Name'**
  String get folderName;

  /// No description provided for @folderCreated.
  ///
  /// In en, this message translates to:
  /// **'Folder created successfully'**
  String get folderCreated;

  /// No description provided for @folderDeleted.
  ///
  /// In en, this message translates to:
  /// **'Folder deleted successfully'**
  String get folderDeleted;

  /// No description provided for @deleteFolderConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this folder and its documents?'**
  String get deleteFolderConfirmation;

  /// No description provided for @emptyFolder.
  ///
  /// In en, this message translates to:
  /// **'This folder is empty'**
  String get emptyFolder;

  /// No description provided for @itemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 items} =1{1 item} other{{count} items}}'**
  String itemsCount(int count);

  /// No description provided for @publicationDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Publication Date'**
  String get publicationDateLabel;

  /// No description provided for @selectPublicationDate.
  ///
  /// In en, this message translates to:
  /// **'Select Publication Date'**
  String get selectPublicationDate;

  /// No description provided for @fileTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'File Type'**
  String get fileTypeLabel;

  /// No description provided for @fileSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get fileSizeLabel;

  /// No description provided for @moveDocument.
  ///
  /// In en, this message translates to:
  /// **'Move Document'**
  String get moveDocument;

  /// No description provided for @selectDestinationFolder.
  ///
  /// In en, this message translates to:
  /// **'Select Destination Folder'**
  String get selectDestinationFolder;

  /// No description provided for @documentMoved.
  ///
  /// In en, this message translates to:
  /// **'Document moved successfully'**
  String get documentMoved;

  /// No description provided for @documentDeleted.
  ///
  /// In en, this message translates to:
  /// **'Document deleted successfully'**
  String get documentDeleted;

  /// No description provided for @deleteDocumentConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this document?'**
  String get deleteDocumentConfirmation;

  /// No description provided for @openingExternalDocument.
  ///
  /// In en, this message translates to:
  /// **'Opening document in external app...'**
  String get openingExternalDocument;

  /// No description provided for @noAppToOpenFile.
  ///
  /// In en, this message translates to:
  /// **'No application found to open this file type'**
  String get noAppToOpenFile;

  /// No description provided for @cachedLocally.
  ///
  /// In en, this message translates to:
  /// **'Cached'**
  String get cachedLocally;

  /// No description provided for @loadingDocument.
  ///
  /// In en, this message translates to:
  /// **'Loading document...'**
  String get loadingDocument;

  /// No description provided for @errorLoadingDocument.
  ///
  /// In en, this message translates to:
  /// **'Error loading document'**
  String get errorLoadingDocument;

  /// No description provided for @increaseFontSize.
  ///
  /// In en, this message translates to:
  /// **'Increase font size'**
  String get increaseFontSize;

  /// No description provided for @decreaseFontSize.
  ///
  /// In en, this message translates to:
  /// **'Decrease font size'**
  String get decreaseFontSize;

  /// No description provided for @copyText.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get copyText;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboard;

  /// No description provided for @shareDocument.
  ///
  /// In en, this message translates to:
  /// **'Share document'**
  String get shareDocument;

  /// No description provided for @searchDocuments.
  ///
  /// In en, this message translates to:
  /// **'Search documents...'**
  String get searchDocuments;

  /// No description provided for @allFolders.
  ///
  /// In en, this message translates to:
  /// **'All Folders'**
  String get allFolders;

  /// No description provided for @currentFolderOnly.
  ///
  /// In en, this message translates to:
  /// **'Current Folder'**
  String get currentFolderOnly;

  /// No description provided for @viewImage.
  ///
  /// In en, this message translates to:
  /// **'View Image'**
  String get viewImage;

  /// No description provided for @readDocument.
  ///
  /// In en, this message translates to:
  /// **'Read Document'**
  String get readDocument;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @manageCategories.
  ///
  /// In en, this message translates to:
  /// **'Manage Categories'**
  String get manageCategories;

  /// No description provided for @addCategory.
  ///
  /// In en, this message translates to:
  /// **'Add Category'**
  String get addCategory;

  /// No description provided for @editCategory.
  ///
  /// In en, this message translates to:
  /// **'Edit Category'**
  String get editCategory;

  /// No description provided for @deleteCategory.
  ///
  /// In en, this message translates to:
  /// **'Delete Category'**
  String get deleteCategory;

  /// No description provided for @categoryName.
  ///
  /// In en, this message translates to:
  /// **'Category Name'**
  String get categoryName;

  /// No description provided for @categoryCreated.
  ///
  /// In en, this message translates to:
  /// **'Category created successfully'**
  String get categoryCreated;

  /// No description provided for @categoryUpdated.
  ///
  /// In en, this message translates to:
  /// **'Category updated successfully'**
  String get categoryUpdated;

  /// No description provided for @categoryDeleted.
  ///
  /// In en, this message translates to:
  /// **'Category deleted successfully'**
  String get categoryDeleted;

  /// No description provided for @deleteCategoryConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this category?'**
  String get deleteCategoryConfirmation;

  /// No description provided for @categoryInUseWarning.
  ///
  /// In en, this message translates to:
  /// **'This category is assigned to {count} document(s). Are you sure you want to delete it?'**
  String categoryInUseWarning(int count);

  /// No description provided for @noCategoriesFound.
  ///
  /// In en, this message translates to:
  /// **'No categories registered'**
  String get noCategoriesFound;

  /// No description provided for @allCategories.
  ///
  /// In en, this message translates to:
  /// **'ALL'**
  String get allCategories;

  /// No description provided for @changeCategory.
  ///
  /// In en, this message translates to:
  /// **'Change Category'**
  String get changeCategory;

  /// No description provided for @selectNewCategory.
  ///
  /// In en, this message translates to:
  /// **'Select New Category'**
  String get selectNewCategory;

  /// No description provided for @documentCategoryChanged.
  ///
  /// In en, this message translates to:
  /// **'Document category updated successfully'**
  String get documentCategoryChanged;

  /// No description provided for @categoryInUseBlocked.
  ///
  /// In en, this message translates to:
  /// **'This category is currently assigned to {count, plural, =1{1 document} other{{count} documents}}. You must reassign or delete the documents before this category can be removed.'**
  String categoryInUseBlocked(int count);

  /// No description provided for @cannotDeleteCategoryInUseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Cannot delete: assigned to {count, plural, =1{1 document} other{{count} documents}}'**
  String cannotDeleteCategoryInUseTooltip(int count);

  /// No description provided for @understood.
  ///
  /// In en, this message translates to:
  /// **'Understood'**
  String get understood;

  /// No description provided for @reviewBookingsMenu.
  ///
  /// In en, this message translates to:
  /// **'Review Bookings'**
  String get reviewBookingsMenu;

  /// No description provided for @adminBookingApprovalTitle.
  ///
  /// In en, this message translates to:
  /// **'Booking Approvals'**
  String get adminBookingApprovalTitle;

  /// No description provided for @noPendingBookings.
  ///
  /// In en, this message translates to:
  /// **'No pending bookings to review.'**
  String get noPendingBookings;

  /// No description provided for @bookingApprovedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Booking approved successfully.'**
  String get bookingApprovedSuccess;

  /// No description provided for @bookingRejectedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Booking rejected.'**
  String get bookingRejectedSuccess;

  /// No description provided for @approveBookingConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to approve this booking?'**
  String get approveBookingConfirm;

  /// No description provided for @rejectBookingConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to reject this booking?'**
  String get rejectBookingConfirm;

  /// No description provided for @rejectionReasonOptional.
  ///
  /// In en, this message translates to:
  /// **'Notes or rejection reason (optional)'**
  String get rejectionReasonOptional;

  /// No description provided for @applicant.
  ///
  /// In en, this message translates to:
  /// **'Applicant'**
  String get applicant;

  /// No description provided for @timeSlot.
  ///
  /// In en, this message translates to:
  /// **'Time Slot'**
  String get timeSlot;

  /// No description provided for @bookingDetails.
  ///
  /// In en, this message translates to:
  /// **'Booking Details'**
  String get bookingDetails;

  /// No description provided for @rejectBookingTitle.
  ///
  /// In en, this message translates to:
  /// **'Reject Booking'**
  String get rejectBookingTitle;

  /// No description provided for @approveBookingTitle.
  ///
  /// In en, this message translates to:
  /// **'Approve Booking'**
  String get approveBookingTitle;

  /// No description provided for @approveBookingButton.
  ///
  /// In en, this message translates to:
  /// **'Approve Booking'**
  String get approveBookingButton;

  /// No description provided for @rejectBookingButton.
  ///
  /// In en, this message translates to:
  /// **'Reject Booking'**
  String get rejectBookingButton;

  /// No description provided for @approve.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approve;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @howToAddFamilyMemberTitle.
  ///
  /// In en, this message translates to:
  /// **'How to add a family member or roommate?'**
  String get howToAddFamilyMemberTitle;

  /// No description provided for @familyOnboardingStep1Title.
  ///
  /// In en, this message translates to:
  /// **'1. Register in the App'**
  String get familyOnboardingStep1Title;

  /// No description provided for @familyOnboardingStep1Desc.
  ///
  /// In en, this message translates to:
  /// **'Ask your family member to download the application and create an account.'**
  String get familyOnboardingStep1Desc;

  /// No description provided for @familyOnboardingStep2Title.
  ///
  /// In en, this message translates to:
  /// **'2. Select \'Family Group\''**
  String get familyOnboardingStep2Title;

  /// No description provided for @familyOnboardingStep2Desc.
  ///
  /// In en, this message translates to:
  /// **'On the address selection screen, tell them to tap the \'Family Group\' option to display their QR code.'**
  String get familyOnboardingStep2Desc;

  /// No description provided for @familyOnboardingStep3Title.
  ///
  /// In en, this message translates to:
  /// **'3. Scan QR or Enter Email/ID'**
  String get familyOnboardingStep3Title;

  /// No description provided for @familyOnboardingStep3Desc.
  ///
  /// In en, this message translates to:
  /// **'Scan their QR code using the button below, or enter their registered email / User ID.'**
  String get familyOnboardingStep3Desc;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
