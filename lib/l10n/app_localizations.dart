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
  /// **'Ask family members to show their Household QR Code or share their User ID/email so you can add them to your family group.'**
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

  /// No description provided for @pasteFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste from Clipboard'**
  String get pasteFromClipboard;

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
