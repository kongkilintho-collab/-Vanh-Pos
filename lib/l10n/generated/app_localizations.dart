import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_lo.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
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
    Locale('lo'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Beauty Clinic POS'**
  String get appTitle;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get commonSaveChanges;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @commonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// No description provided for @commonSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get commonSearch;

  /// No description provided for @commonRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get commonRequired;

  /// No description provided for @commonOptional.
  ///
  /// In en, this message translates to:
  /// **'optional'**
  String get commonOptional;

  /// No description provided for @commonNotSpecified.
  ///
  /// In en, this message translates to:
  /// **'Not specified'**
  String get commonNotSpecified;

  /// No description provided for @commonNoPhoneOnFile.
  ///
  /// In en, this message translates to:
  /// **'No phone on file'**
  String get commonNoPhoneOnFile;

  /// No description provided for @commonCashier.
  ///
  /// In en, this message translates to:
  /// **'Cashier'**
  String get commonCashier;

  /// No description provided for @commonChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get commonChoose;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @authLoginTagline.
  ///
  /// In en, this message translates to:
  /// **'Sign in to your business'**
  String get authLoginTagline;

  /// No description provided for @authEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmailLabel;

  /// No description provided for @authEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get authEmailInvalid;

  /// No description provided for @authPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPasswordLabel;

  /// No description provided for @authPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get authPasswordRequired;

  /// No description provided for @authForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get authForgotPassword;

  /// No description provided for @authSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignIn;

  /// No description provided for @authNoAccountYet.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have a business account yet?'**
  String get authNoAccountYet;

  /// No description provided for @authCreateOne.
  ///
  /// In en, this message translates to:
  /// **'Create one'**
  String get authCreateOne;

  /// No description provided for @authCheckYourEmail.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get authCheckYourEmail;

  /// No description provided for @authResetLinkSentTo.
  ///
  /// In en, this message translates to:
  /// **'If an account exists for {email}, a reset link has been sent.'**
  String authResetLinkSentTo(String email);

  /// No description provided for @authResetPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset your password'**
  String get authResetPasswordTitle;

  /// No description provided for @authResetPasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We\'ll email you a reset link.'**
  String get authResetPasswordSubtitle;

  /// No description provided for @authSendResetLink.
  ///
  /// In en, this message translates to:
  /// **'Send reset link'**
  String get authSendResetLink;

  /// No description provided for @authConfirmationSentTo.
  ///
  /// In en, this message translates to:
  /// **'We\'ve sent a confirmation link to {email}. Confirm your email, then sign in.'**
  String authConfirmationSentTo(String email);

  /// No description provided for @authBackToSignIn.
  ///
  /// In en, this message translates to:
  /// **'Back to sign in'**
  String get authBackToSignIn;

  /// No description provided for @authCreateAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get authCreateAccountTitle;

  /// No description provided for @authCreateAccountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You\'ll set up your business next.'**
  String get authCreateAccountSubtitle;

  /// No description provided for @authFullNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get authFullNameLabel;

  /// No description provided for @authNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your name'**
  String get authNameRequired;

  /// No description provided for @authPasswordTooShortValidation.
  ///
  /// In en, this message translates to:
  /// **'Use at least 6 characters'**
  String get authPasswordTooShortValidation;

  /// No description provided for @authCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authCreateAccount;

  /// No description provided for @authSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get authSignOut;

  /// No description provided for @authSetUpBusinessTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up your business'**
  String get authSetUpBusinessTitle;

  /// No description provided for @authSetUpBusinessSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This creates your clinic\'s workspace. You\'ll be the owner.'**
  String get authSetUpBusinessSubtitle;

  /// No description provided for @authBusinessNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Business name'**
  String get authBusinessNameLabel;

  /// No description provided for @authBusinessNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a business name'**
  String get authBusinessNameRequired;

  /// No description provided for @authPhoneOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone (optional)'**
  String get authPhoneOptionalLabel;

  /// No description provided for @authCreateBusiness.
  ///
  /// In en, this message translates to:
  /// **'Create business'**
  String get authCreateBusiness;

  /// No description provided for @errorIncorrectCredentials.
  ///
  /// In en, this message translates to:
  /// **'Incorrect email or password.'**
  String get errorIncorrectCredentials;

  /// No description provided for @errorEmailNotConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Please confirm your email before signing in.'**
  String get errorEmailNotConfirmed;

  /// No description provided for @errorUserAlreadyRegistered.
  ///
  /// In en, this message translates to:
  /// **'An account with this email already exists.'**
  String get errorUserAlreadyRegistered;

  /// No description provided for @errorPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password is too short. Use at least 6 characters.'**
  String get errorPasswordTooShort;

  /// No description provided for @errorAuthGeneric.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed. Please try again.'**
  String get errorAuthGeneric;

  /// No description provided for @errorRecordExists.
  ///
  /// In en, this message translates to:
  /// **'That record already exists.'**
  String get errorRecordExists;

  /// No description provided for @errorNoPermission.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to do that.'**
  String get errorNoPermission;

  /// No description provided for @errorSaveGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong saving your data. Please try again.'**
  String get errorSaveGeneric;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please check your connection and try again.'**
  String get errorGeneric;

  /// No description provided for @posWalkInCustomer.
  ///
  /// In en, this message translates to:
  /// **'Walk-in customer'**
  String get posWalkInCustomer;

  /// No description provided for @posCartEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Cart is empty'**
  String get posCartEmptyTitle;

  /// No description provided for @posCartEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap a service or product to add it'**
  String get posCartEmptySubtitle;

  /// No description provided for @posSubtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get posSubtotal;

  /// No description provided for @posDiscount.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get posDiscount;

  /// No description provided for @posTax.
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get posTax;

  /// No description provided for @posTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get posTotal;

  /// No description provided for @posChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get posChange;

  /// No description provided for @posCompleteSale.
  ///
  /// In en, this message translates to:
  /// **'Complete sale'**
  String get posCompleteSale;

  /// No description provided for @posRemoveTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get posRemoveTooltip;

  /// No description provided for @posStaffForCommission.
  ///
  /// In en, this message translates to:
  /// **'Staff (for commission)'**
  String get posStaffForCommission;

  /// No description provided for @posUnassigned.
  ///
  /// In en, this message translates to:
  /// **'Unassigned'**
  String get posUnassigned;

  /// No description provided for @posPaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get posPaymentMethod;

  /// No description provided for @posAmountPaidLak.
  ///
  /// In en, this message translates to:
  /// **'Amount paid (LAK)'**
  String get posAmountPaidLak;

  /// No description provided for @posPaymentInsufficient.
  ///
  /// In en, this message translates to:
  /// **'Payment amount cannot be less than the sale total.'**
  String get posPaymentInsufficient;

  /// No description provided for @posAcceptDepositAction.
  ///
  /// In en, this message translates to:
  /// **'Accept deposit'**
  String get posAcceptDepositAction;

  /// No description provided for @posDepositTitle.
  ///
  /// In en, this message translates to:
  /// **'Accept deposit'**
  String get posDepositTitle;

  /// No description provided for @posDepositAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Initial payment'**
  String get posDepositAmountLabel;

  /// No description provided for @posDepositAmountRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a deposit amount'**
  String get posDepositAmountRequired;

  /// No description provided for @posDepositRemainingBalance.
  ///
  /// In en, this message translates to:
  /// **'Remaining balance'**
  String get posDepositRemainingBalance;

  /// No description provided for @posDepositConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Confirm deposit'**
  String get posDepositConfirmAction;

  /// No description provided for @posDepositResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Deposit recorded'**
  String get posDepositResultTitle;

  /// No description provided for @posDepositResultPaymentStatus.
  ///
  /// In en, this message translates to:
  /// **'Payment status'**
  String get posDepositResultPaymentStatus;

  /// No description provided for @posDepositDoneAction.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get posDepositDoneAction;

  /// No description provided for @paymentMethodCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get paymentMethodCash;

  /// No description provided for @paymentMethodBankTransfer.
  ///
  /// In en, this message translates to:
  /// **'Bank transfer'**
  String get paymentMethodBankTransfer;

  /// No description provided for @paymentMethodCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get paymentMethodCard;

  /// No description provided for @paymentMethodOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get paymentMethodOther;

  /// No description provided for @salesStatusVoided.
  ///
  /// In en, this message translates to:
  /// **'Voided'**
  String get salesStatusVoided;

  /// No description provided for @salesStatusRefunded.
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get salesStatusRefunded;

  /// No description provided for @salesStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get salesStatusCompleted;

  /// No description provided for @salesVoidConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Void this sale?'**
  String get salesVoidConfirmTitle;

  /// No description provided for @salesVoidConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This reverses stock and commissions for this sale and marks its payment refunded. This cannot be undone.'**
  String get salesVoidConfirmBody;

  /// No description provided for @salesVoidReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get salesVoidReasonLabel;

  /// No description provided for @salesVoidReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Why is this sale being voided?'**
  String get salesVoidReasonHint;

  /// No description provided for @salesVoidAction.
  ///
  /// In en, this message translates to:
  /// **'Void sale'**
  String get salesVoidAction;

  /// No description provided for @salesVoiding.
  ///
  /// In en, this message translates to:
  /// **'Voiding…'**
  String get salesVoiding;

  /// No description provided for @salesVoidedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Sale voided.'**
  String get salesVoidedSnackbar;

  /// No description provided for @salesDetailFallbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Sale'**
  String get salesDetailFallbackTitle;

  /// No description provided for @salesVoidDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Void details'**
  String get salesVoidDetailsTitle;

  /// No description provided for @salesRowPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get salesRowPaid;

  /// No description provided for @salesStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get salesStatusPending;

  /// No description provided for @salesStatusPartial.
  ///
  /// In en, this message translates to:
  /// **'Partially paid'**
  String get salesStatusPartial;

  /// No description provided for @salesRowOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Outstanding balance'**
  String get salesRowOutstanding;

  /// No description provided for @salesPaymentHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment history'**
  String get salesPaymentHistoryTitle;

  /// No description provided for @salesNoPayments.
  ///
  /// In en, this message translates to:
  /// **'No payments recorded yet.'**
  String get salesNoPayments;

  /// No description provided for @salesSettleBalanceAction.
  ///
  /// In en, this message translates to:
  /// **'Settle balance'**
  String get salesSettleBalanceAction;

  /// No description provided for @salesSettleBalanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Settle outstanding balance'**
  String get salesSettleBalanceTitle;

  /// No description provided for @salesSettleAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Payment amount'**
  String get salesSettleAmountLabel;

  /// No description provided for @salesSettleReferenceOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Reference (optional)'**
  String get salesSettleReferenceOptionalLabel;

  /// No description provided for @salesSettleSubmitAction.
  ///
  /// In en, this message translates to:
  /// **'Record payment'**
  String get salesSettleSubmitAction;

  /// No description provided for @salesSettleAmountExceedsBalance.
  ///
  /// In en, this message translates to:
  /// **'Amount cannot exceed the outstanding balance'**
  String get salesSettleAmountExceedsBalance;

  /// No description provided for @salesSettleSuccessSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Payment recorded.'**
  String get salesSettleSuccessSnackbar;

  /// No description provided for @customersFallbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get customersFallbackTitle;

  /// No description provided for @customersTotalSpent.
  ///
  /// In en, this message translates to:
  /// **'Total spent'**
  String get customersTotalSpent;

  /// No description provided for @customersVisits.
  ///
  /// In en, this message translates to:
  /// **'Visits'**
  String get customersVisits;

  /// No description provided for @customersLastVisit.
  ///
  /// In en, this message translates to:
  /// **'Last visit'**
  String get customersLastVisit;

  /// No description provided for @customersPurchaseHistory.
  ///
  /// In en, this message translates to:
  /// **'Purchase history'**
  String get customersPurchaseHistory;

  /// No description provided for @customersNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get customersNotes;

  /// No description provided for @customersNoSalesYet.
  ///
  /// In en, this message translates to:
  /// **'No sales yet.'**
  String get customersNoSalesYet;

  /// No description provided for @customersNoNotesYet.
  ///
  /// In en, this message translates to:
  /// **'No notes yet.'**
  String get customersNoNotesYet;

  /// No description provided for @customersAddNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Add a note...'**
  String get customersAddNoteHint;

  /// No description provided for @treatmentHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Treatment history'**
  String get treatmentHistoryTitle;

  /// No description provided for @treatmentNoneYet.
  ///
  /// In en, this message translates to:
  /// **'No treatments recorded yet.'**
  String get treatmentNoneYet;

  /// No description provided for @treatmentAddAction.
  ///
  /// In en, this message translates to:
  /// **'Add treatment'**
  String get treatmentAddAction;

  /// No description provided for @treatmentFormTitle.
  ///
  /// In en, this message translates to:
  /// **'Add treatment'**
  String get treatmentFormTitle;

  /// No description provided for @treatmentServiceLabel.
  ///
  /// In en, this message translates to:
  /// **'Service'**
  String get treatmentServiceLabel;

  /// No description provided for @treatmentStaffLabel.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get treatmentStaffLabel;

  /// No description provided for @treatmentDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Treatment date'**
  String get treatmentDateLabel;

  /// No description provided for @treatmentNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get treatmentNotesLabel;

  /// No description provided for @treatmentResultLabel.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get treatmentResultLabel;

  /// No description provided for @treatmentFeedbackLabel.
  ///
  /// In en, this message translates to:
  /// **'Customer feedback'**
  String get treatmentFeedbackLabel;

  /// No description provided for @treatmentBeforeAfterLabel.
  ///
  /// In en, this message translates to:
  /// **'Before/After reference (URL)'**
  String get treatmentBeforeAfterLabel;

  /// No description provided for @treatmentFollowUpLabel.
  ///
  /// In en, this message translates to:
  /// **'Follow-up date'**
  String get treatmentFollowUpLabel;

  /// No description provided for @treatmentSaveAction.
  ///
  /// In en, this message translates to:
  /// **'Save treatment'**
  String get treatmentSaveAction;

  /// No description provided for @treatmentServiceRequired.
  ///
  /// In en, this message translates to:
  /// **'Select a service'**
  String get treatmentServiceRequired;

  /// No description provided for @treatmentStaffRequired.
  ///
  /// In en, this message translates to:
  /// **'Select a staff member'**
  String get treatmentStaffRequired;

  /// No description provided for @treatmentRowResult.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get treatmentRowResult;

  /// No description provided for @treatmentRowFeedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get treatmentRowFeedback;

  /// No description provided for @treatmentRowFollowUp.
  ///
  /// In en, this message translates to:
  /// **'Follow-up'**
  String get treatmentRowFollowUp;

  /// No description provided for @consultationHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Consultations'**
  String get consultationHistoryTitle;

  /// No description provided for @consultationNoneYet.
  ///
  /// In en, this message translates to:
  /// **'No consultations recorded yet.'**
  String get consultationNoneYet;

  /// No description provided for @consultationAddAction.
  ///
  /// In en, this message translates to:
  /// **'Add consultation'**
  String get consultationAddAction;

  /// No description provided for @consultationFormTitle.
  ///
  /// In en, this message translates to:
  /// **'Add consultation'**
  String get consultationFormTitle;

  /// No description provided for @consultationStaffLabel.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get consultationStaffLabel;

  /// No description provided for @consultationDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Consultation date'**
  String get consultationDateLabel;

  /// No description provided for @consultationRecommendedServiceLabel.
  ///
  /// In en, this message translates to:
  /// **'Recommended service (optional)'**
  String get consultationRecommendedServiceLabel;

  /// No description provided for @consultationRecommendedServiceNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get consultationRecommendedServiceNone;

  /// No description provided for @consultationNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Consultation notes'**
  String get consultationNotesLabel;

  /// No description provided for @consultationConcernsLabel.
  ///
  /// In en, this message translates to:
  /// **'Customer concerns'**
  String get consultationConcernsLabel;

  /// No description provided for @consultationObservationsLabel.
  ///
  /// In en, this message translates to:
  /// **'Observations'**
  String get consultationObservationsLabel;

  /// No description provided for @consultationConsiderationsLabel.
  ///
  /// In en, this message translates to:
  /// **'Considerations'**
  String get consultationConsiderationsLabel;

  /// No description provided for @consultationAssessmentLabel.
  ///
  /// In en, this message translates to:
  /// **'Assessment'**
  String get consultationAssessmentLabel;

  /// No description provided for @consultationRecommendationLabel.
  ///
  /// In en, this message translates to:
  /// **'Recommendation notes'**
  String get consultationRecommendationLabel;

  /// No description provided for @consultationSaveAction.
  ///
  /// In en, this message translates to:
  /// **'Save consultation'**
  String get consultationSaveAction;

  /// No description provided for @consultationStaffRequired.
  ///
  /// In en, this message translates to:
  /// **'Select a staff member'**
  String get consultationStaffRequired;

  /// No description provided for @consultationRowRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get consultationRowRecommended;

  /// No description provided for @consultationRowConcerns.
  ///
  /// In en, this message translates to:
  /// **'Concerns'**
  String get consultationRowConcerns;

  /// No description provided for @consultationRowAssessment.
  ///
  /// In en, this message translates to:
  /// **'Assessment'**
  String get consultationRowAssessment;

  /// No description provided for @customersNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get customersNameLabel;

  /// No description provided for @customersGenderOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Gender (optional)'**
  String get customersGenderOptionalLabel;

  /// No description provided for @customersGenderMale.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get customersGenderMale;

  /// No description provided for @customersGenderFemale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get customersGenderFemale;

  /// No description provided for @customersGenderOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get customersGenderOther;

  /// No description provided for @customersNotesOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes (optional)'**
  String get customersNotesOptionalLabel;

  /// No description provided for @customersEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit customer'**
  String get customersEditTitle;

  /// No description provided for @customersAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add customer'**
  String get customersAddTitle;

  /// No description provided for @customersSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name or phone'**
  String get customersSearchHint;

  /// No description provided for @customersEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No customers yet'**
  String get customersEmptyTitle;

  /// No description provided for @customersEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add your first customer, or they\'ll be created automatically at checkout.'**
  String get customersEmptySubtitle;

  /// No description provided for @customersVisitsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} visits'**
  String customersVisitsCount(int count);

  /// No description provided for @posReceiptSaleComplete.
  ///
  /// In en, this message translates to:
  /// **'Sale complete'**
  String get posReceiptSaleComplete;

  /// No description provided for @posReceiptReceipt.
  ///
  /// In en, this message translates to:
  /// **'Receipt'**
  String get posReceiptReceipt;

  /// No description provided for @posReceiptDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get posReceiptDate;

  /// No description provided for @posReceiptCashier.
  ///
  /// In en, this message translates to:
  /// **'Cashier'**
  String get posReceiptCashier;

  /// No description provided for @posReceiptCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get posReceiptCustomer;

  /// No description provided for @posReceiptWalkIn.
  ///
  /// In en, this message translates to:
  /// **'Walk-in'**
  String get posReceiptWalkIn;

  /// No description provided for @posReceiptPaidVia.
  ///
  /// In en, this message translates to:
  /// **'Paid ({method})'**
  String posReceiptPaidVia(String method);

  /// No description provided for @posReceiptThankYou.
  ///
  /// In en, this message translates to:
  /// **'Thank you!'**
  String get posReceiptThankYou;

  /// No description provided for @posReceiptNewSale.
  ///
  /// In en, this message translates to:
  /// **'New sale'**
  String get posReceiptNewSale;

  /// No description provided for @posCartItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} item} other{{count} items}}'**
  String posCartItemCount(int count);

  /// No description provided for @posSelectCustomer.
  ///
  /// In en, this message translates to:
  /// **'Select customer'**
  String get posSelectCustomer;

  /// No description provided for @posSearchNameOrPhone.
  ///
  /// In en, this message translates to:
  /// **'Search name or phone'**
  String get posSearchNameOrPhone;

  /// No description provided for @posNoCustomersFound.
  ///
  /// In en, this message translates to:
  /// **'No customers found'**
  String get posNoCustomersFound;

  /// No description provided for @posCreateAsNewCustomer.
  ///
  /// In en, this message translates to:
  /// **'Create \"{query}\" as new customer'**
  String posCreateAsNewCustomer(String query);

  /// No description provided for @posSearchServicesOrProducts.
  ///
  /// In en, this message translates to:
  /// **'Search services or products'**
  String get posSearchServicesOrProducts;

  /// No description provided for @posServicesTab.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get posServicesTab;

  /// No description provided for @posProductsTab.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get posProductsTab;

  /// No description provided for @posNoServicesYet.
  ///
  /// In en, this message translates to:
  /// **'No services yet'**
  String get posNoServicesYet;

  /// No description provided for @posNoProductsYet.
  ///
  /// In en, this message translates to:
  /// **'No products yet'**
  String get posNoProductsYet;

  /// No description provided for @posNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get posNoMatches;

  /// No description provided for @posOutOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get posOutOfStock;

  /// No description provided for @posItemsLeft.
  ///
  /// In en, this message translates to:
  /// **'{price} · {count} left'**
  String posItemsLeft(String price, int count);

  /// No description provided for @salesSearchByReceiptHint.
  ///
  /// In en, this message translates to:
  /// **'Search by receipt number'**
  String get salesSearchByReceiptHint;

  /// No description provided for @salesNoSalesFound.
  ///
  /// In en, this message translates to:
  /// **'No sales found.'**
  String get salesNoSalesFound;

  /// No description provided for @roleOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get roleOwner;

  /// No description provided for @roleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get roleAdmin;

  /// No description provided for @roleManager.
  ///
  /// In en, this message translates to:
  /// **'Manager'**
  String get roleManager;

  /// No description provided for @roleCashier.
  ///
  /// In en, this message translates to:
  /// **'Cashier'**
  String get roleCashier;

  /// No description provided for @roleStaff.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get roleStaff;

  /// No description provided for @movementTypePurchase.
  ///
  /// In en, this message translates to:
  /// **'Restock (purchase)'**
  String get movementTypePurchase;

  /// No description provided for @movementTypeSale.
  ///
  /// In en, this message translates to:
  /// **'Sale'**
  String get movementTypeSale;

  /// No description provided for @movementTypeReturn.
  ///
  /// In en, this message translates to:
  /// **'Return'**
  String get movementTypeReturn;

  /// No description provided for @movementTypeAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Adjustment'**
  String get movementTypeAdjustment;

  /// No description provided for @movementTypeDamage.
  ///
  /// In en, this message translates to:
  /// **'Damage'**
  String get movementTypeDamage;

  /// No description provided for @movementTypeExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get movementTypeExpired;

  /// No description provided for @staffInviteButton.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get staffInviteButton;

  /// No description provided for @staffEmptyState.
  ///
  /// In en, this message translates to:
  /// **'No staff yet.'**
  String get staffEmptyState;

  /// No description provided for @staffRoleInactiveSuffix.
  ///
  /// In en, this message translates to:
  /// **'{role} · Inactive'**
  String staffRoleInactiveSuffix(String role);

  /// No description provided for @staffChangeRole.
  ///
  /// In en, this message translates to:
  /// **'Change role'**
  String get staffChangeRole;

  /// No description provided for @staffDeactivate.
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get staffDeactivate;

  /// No description provided for @staffReactivate.
  ///
  /// In en, this message translates to:
  /// **'Reactivate'**
  String get staffReactivate;

  /// No description provided for @staffInviteTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite staff'**
  String get staffInviteTitle;

  /// No description provided for @staffInviteSubtitle.
  ///
  /// In en, this message translates to:
  /// **'They must already have an account. Enter their email to look them up.'**
  String get staffInviteSubtitle;

  /// No description provided for @staffFind.
  ///
  /// In en, this message translates to:
  /// **'Find'**
  String get staffFind;

  /// No description provided for @staffNoAccountFound.
  ///
  /// In en, this message translates to:
  /// **'No account found with this email. They need to sign up first.'**
  String get staffNoAccountFound;

  /// No description provided for @staffAccountFound.
  ///
  /// In en, this message translates to:
  /// **'Account found'**
  String get staffAccountFound;

  /// No description provided for @staffRoleLabel.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get staffRoleLabel;

  /// No description provided for @staffInviteAction.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get staffInviteAction;

  /// No description provided for @invTabStock.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get invTabStock;

  /// No description provided for @invTabMovements.
  ///
  /// In en, this message translates to:
  /// **'Movements'**
  String get invTabMovements;

  /// No description provided for @invTabSuppliers.
  ///
  /// In en, this message translates to:
  /// **'Suppliers'**
  String get invTabSuppliers;

  /// No description provided for @invNoProductsYetTitle.
  ///
  /// In en, this message translates to:
  /// **'No products yet'**
  String get invNoProductsYetTitle;

  /// No description provided for @invNoProductsYetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add products in the Products tab to start tracking stock.'**
  String get invNoProductsYetSubtitle;

  /// No description provided for @invLowStockWarning.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} product at or below its low-stock threshold.} other{{count} products at or below its low-stock threshold.}}'**
  String invLowStockWarning(int count);

  /// No description provided for @invLowStockAlertAt.
  ///
  /// In en, this message translates to:
  /// **'Low-stock alert at {threshold}'**
  String invLowStockAlertAt(int threshold);

  /// No description provided for @invInStock.
  ///
  /// In en, this message translates to:
  /// **'{count} in stock'**
  String invInStock(int count);

  /// No description provided for @invAdjustStockTooltip.
  ///
  /// In en, this message translates to:
  /// **'Adjust stock'**
  String get invAdjustStockTooltip;

  /// No description provided for @invNoMovementsYet.
  ///
  /// In en, this message translates to:
  /// **'No stock movements yet. Sales and manual adjustments will appear here.'**
  String get invNoMovementsYet;

  /// No description provided for @invUnknownProduct.
  ///
  /// In en, this message translates to:
  /// **'Unknown product'**
  String get invUnknownProduct;

  /// No description provided for @invAddSupplier.
  ///
  /// In en, this message translates to:
  /// **'Add supplier'**
  String get invAddSupplier;

  /// No description provided for @invEditSupplier.
  ///
  /// In en, this message translates to:
  /// **'Edit supplier'**
  String get invEditSupplier;

  /// No description provided for @invNoSuppliersYetTitle.
  ///
  /// In en, this message translates to:
  /// **'No suppliers yet'**
  String get invNoSuppliersYetTitle;

  /// No description provided for @invNoSuppliersYetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Track who you restock products from.'**
  String get invNoSuppliersYetSubtitle;

  /// No description provided for @invNoContactInfo.
  ///
  /// In en, this message translates to:
  /// **'No contact info on file'**
  String get invNoContactInfo;

  /// No description provided for @invInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get invInactive;

  /// No description provided for @invAdjustStockTitle.
  ///
  /// In en, this message translates to:
  /// **'Adjust stock'**
  String get invAdjustStockTitle;

  /// No description provided for @invAdjustStockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{name} · currently {count} in stock'**
  String invAdjustStockSubtitle(String name, int count);

  /// No description provided for @invAddStockSegment.
  ///
  /// In en, this message translates to:
  /// **'Add stock'**
  String get invAddStockSegment;

  /// No description provided for @invRemoveStockSegment.
  ///
  /// In en, this message translates to:
  /// **'Remove stock'**
  String get invRemoveStockSegment;

  /// No description provided for @invQuantityLabel.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get invQuantityLabel;

  /// No description provided for @invQuantityPositiveRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a positive whole number'**
  String get invQuantityPositiveRequired;

  /// No description provided for @invReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get invReasonLabel;

  /// No description provided for @invNoteOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get invNoteOptionalLabel;

  /// No description provided for @invSaveAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Save adjustment'**
  String get invSaveAdjustment;

  /// No description provided for @supplierNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Supplier name'**
  String get supplierNameLabel;

  /// No description provided for @commonActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get commonActive;

  /// No description provided for @customersEmailOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Email (optional)'**
  String get customersEmailOptionalLabel;

  /// No description provided for @customersAddressOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Address (optional)'**
  String get customersAddressOptionalLabel;

  /// No description provided for @expensesEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit expense'**
  String get expensesEditTitle;

  /// No description provided for @expensesAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get expensesAddTitle;

  /// No description provided for @expensesAmountLak.
  ///
  /// In en, this message translates to:
  /// **'Amount (LAK)'**
  String get expensesAmountLak;

  /// No description provided for @expensesPositiveAmountRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a positive amount'**
  String get expensesPositiveAmountRequired;

  /// No description provided for @expensesCategoryOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Category (optional)'**
  String get expensesCategoryOptionalLabel;

  /// No description provided for @expensesNoCategory.
  ///
  /// In en, this message translates to:
  /// **'No category'**
  String get expensesNoCategory;

  /// No description provided for @expensesDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get expensesDateLabel;

  /// No description provided for @expensesDescriptionOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get expensesDescriptionOptionalLabel;

  /// No description provided for @expensesManageCategoriesTooltip.
  ///
  /// In en, this message translates to:
  /// **'Manage categories'**
  String get expensesManageCategoriesTooltip;

  /// No description provided for @expensesAllCategories.
  ///
  /// In en, this message translates to:
  /// **'All categories'**
  String get expensesAllCategories;

  /// No description provided for @expensesNoExpensesTitle.
  ///
  /// In en, this message translates to:
  /// **'No expenses recorded'**
  String get expensesNoExpensesTitle;

  /// No description provided for @expensesNoExpensesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Track rent, utilities, and other business costs here.'**
  String get expensesNoExpensesSubtitle;

  /// No description provided for @expensesTotalLabel.
  ///
  /// In en, this message translates to:
  /// **'Total: '**
  String get expensesTotalLabel;

  /// No description provided for @expensesUncategorized.
  ///
  /// In en, this message translates to:
  /// **'Uncategorized'**
  String get expensesUncategorized;

  /// No description provided for @expensesDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete expense?'**
  String get expensesDeleteTitle;

  /// No description provided for @expensesDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get expensesDeleteBody;

  /// No description provided for @expenseCategoriesTitle.
  ///
  /// In en, this message translates to:
  /// **'Expense categories'**
  String get expenseCategoriesTitle;

  /// No description provided for @expenseNewCategoryNameLabel.
  ///
  /// In en, this message translates to:
  /// **'New category name'**
  String get expenseNewCategoryNameLabel;

  /// No description provided for @expenseNoCategoriesYet.
  ///
  /// In en, this message translates to:
  /// **'No categories yet.'**
  String get expenseNoCategoriesYet;

  /// No description provided for @categoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get categoryLabel;

  /// No description provided for @navOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get navOverview;

  /// No description provided for @navPos.
  ///
  /// In en, this message translates to:
  /// **'POS'**
  String get navPos;

  /// No description provided for @navSales.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get navSales;

  /// No description provided for @navCustomers.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get navCustomers;

  /// No description provided for @navAppointments.
  ///
  /// In en, this message translates to:
  /// **'Appointments'**
  String get navAppointments;

  /// No description provided for @navServices.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get navServices;

  /// No description provided for @navPackages.
  ///
  /// In en, this message translates to:
  /// **'Packages'**
  String get navPackages;

  /// No description provided for @navProducts.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get navProducts;

  /// No description provided for @navInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get navInventory;

  /// No description provided for @navStaff.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get navStaff;

  /// No description provided for @navCommissions.
  ///
  /// In en, this message translates to:
  /// **'Commissions'**
  String get navCommissions;

  /// No description provided for @navExpenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get navExpenses;

  /// No description provided for @navReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get navReports;

  /// No description provided for @navAuditLog.
  ///
  /// In en, this message translates to:
  /// **'Audit Log'**
  String get navAuditLog;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @navSoon.
  ///
  /// In en, this message translates to:
  /// **'Soon'**
  String get navSoon;

  /// No description provided for @navNotBuiltYet.
  ///
  /// In en, this message translates to:
  /// **'{label} is not built yet'**
  String navNotBuiltYet(String label);

  /// No description provided for @navScheduledLater.
  ///
  /// In en, this message translates to:
  /// **'This section is scheduled later in the build plan.'**
  String get navScheduledLater;

  /// No description provided for @overviewIntro.
  ///
  /// In en, this message translates to:
  /// **'You\'re authenticated and your business workspace is set up. POS, customers, inventory, and reporting come online as each part of the build lands.'**
  String get overviewIntro;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @reportsTodayTagline.
  ///
  /// In en, this message translates to:
  /// **'Today\'s business at a glance.'**
  String get reportsTodayTagline;

  /// No description provided for @reportsTodaySales.
  ///
  /// In en, this message translates to:
  /// **'Today\'s sales'**
  String get reportsTodaySales;

  /// No description provided for @reportsSalesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} sale} other{{count} sales}}'**
  String reportsSalesCount(int count);

  /// No description provided for @reportsCommission.
  ///
  /// In en, this message translates to:
  /// **'Commission'**
  String get reportsCommission;

  /// No description provided for @reportsExpenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get reportsExpenses;

  /// No description provided for @reportsEstimatedProfit.
  ///
  /// In en, this message translates to:
  /// **'Estimated profit'**
  String get reportsEstimatedProfit;

  /// No description provided for @reportsRevenue.
  ///
  /// In en, this message translates to:
  /// **'Revenue'**
  String get reportsRevenue;

  /// No description provided for @reportsCogs.
  ///
  /// In en, this message translates to:
  /// **'Cost of goods sold'**
  String get reportsCogs;

  /// No description provided for @reportsExportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get reportsExportCsv;

  /// No description provided for @reportsCopiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Report copied to clipboard as CSV.'**
  String get reportsCopiedToClipboard;

  /// No description provided for @reportsRevenueByDay.
  ///
  /// In en, this message translates to:
  /// **'Revenue by day'**
  String get reportsRevenueByDay;

  /// No description provided for @reportsSalesInRange.
  ///
  /// In en, this message translates to:
  /// **'Sales in range'**
  String get reportsSalesInRange;

  /// No description provided for @reportsNoSalesInRange.
  ///
  /// In en, this message translates to:
  /// **'No sales in this range yet.'**
  String get reportsNoSalesInRange;

  /// No description provided for @reportsColReceipt.
  ///
  /// In en, this message translates to:
  /// **'Receipt'**
  String get reportsColReceipt;

  /// No description provided for @reportsColDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get reportsColDate;

  /// No description provided for @reportsColStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get reportsColStatus;

  /// No description provided for @reportsColAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get reportsColAmount;

  /// No description provided for @reportsCsvPaymentStatus.
  ///
  /// In en, this message translates to:
  /// **'Payment status'**
  String get reportsCsvPaymentStatus;

  /// No description provided for @auditActionLabel.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get auditActionLabel;

  /// No description provided for @auditAllActions.
  ///
  /// In en, this message translates to:
  /// **'All actions'**
  String get auditAllActions;

  /// No description provided for @auditEntityLabel.
  ///
  /// In en, this message translates to:
  /// **'Entity'**
  String get auditEntityLabel;

  /// No description provided for @auditAllEntities.
  ///
  /// In en, this message translates to:
  /// **'All entities'**
  String get auditAllEntities;

  /// No description provided for @auditEmptyState.
  ///
  /// In en, this message translates to:
  /// **'No audit events for this filter.'**
  String get auditEmptyState;

  /// No description provided for @auditSystemActor.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get auditSystemActor;

  /// No description provided for @auditBefore.
  ///
  /// In en, this message translates to:
  /// **'Before'**
  String get auditBefore;

  /// No description provided for @auditAfter.
  ///
  /// In en, this message translates to:
  /// **'After'**
  String get auditAfter;

  /// No description provided for @auditDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get auditDetails;

  /// No description provided for @commissionKindPercentage.
  ///
  /// In en, this message translates to:
  /// **'Percentage'**
  String get commissionKindPercentage;

  /// No description provided for @commissionKindFixed.
  ///
  /// In en, this message translates to:
  /// **'Fixed amount'**
  String get commissionKindFixed;

  /// No description provided for @commissionStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get commissionStatusPending;

  /// No description provided for @commissionStatusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get commissionStatusApproved;

  /// No description provided for @commissionStatusReversed.
  ///
  /// In en, this message translates to:
  /// **'Reversed'**
  String get commissionStatusReversed;

  /// No description provided for @commissionStatusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get commissionStatusPaid;

  /// No description provided for @productsAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add product'**
  String get productsAddTitle;

  /// No description provided for @productsEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit product'**
  String get productsEditTitle;

  /// No description provided for @productsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No products yet'**
  String get productsEmptyTitle;

  /// No description provided for @productsEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add retail products to sell alongside services.'**
  String get productsEmptySubtitle;

  /// No description provided for @productsSkuPrefix.
  ///
  /// In en, this message translates to:
  /// **'SKU {sku}'**
  String productsSkuPrefix(String sku);

  /// No description provided for @productNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Product name'**
  String get productNameLabel;

  /// No description provided for @productSkuOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'SKU (optional)'**
  String get productSkuOptionalLabel;

  /// No description provided for @productSellingPriceLak.
  ///
  /// In en, this message translates to:
  /// **'Selling price (LAK)'**
  String get productSellingPriceLak;

  /// No description provided for @productCostPriceLak.
  ///
  /// In en, this message translates to:
  /// **'Cost price (LAK)'**
  String get productCostPriceLak;

  /// No description provided for @productStockQuantityLabel.
  ///
  /// In en, this message translates to:
  /// **'Stock quantity'**
  String get productStockQuantityLabel;

  /// No description provided for @productLowStockAlertAtLabel.
  ///
  /// In en, this message translates to:
  /// **'Low-stock alert at'**
  String get productLowStockAlertAtLabel;

  /// No description provided for @commonInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid'**
  String get commonInvalid;

  /// No description provided for @servicesAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add service'**
  String get servicesAddTitle;

  /// No description provided for @servicesEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit service'**
  String get servicesEditTitle;

  /// No description provided for @servicesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No services yet'**
  String get servicesEmptyTitle;

  /// No description provided for @servicesEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add your first service to start taking bookings and sales.'**
  String get servicesEmptySubtitle;

  /// No description provided for @servicesDurationCommission.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min · {label} {value}{percentSuffix} commission'**
  String servicesDurationCommission(
    int minutes,
    String label,
    String value,
    String percentSuffix,
  );

  /// No description provided for @serviceNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Service name'**
  String get serviceNameLabel;

  /// No description provided for @serviceDescriptionOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get serviceDescriptionOptionalLabel;

  /// No description provided for @servicePriceLak.
  ///
  /// In en, this message translates to:
  /// **'Price (LAK)'**
  String get servicePriceLak;

  /// No description provided for @servicePriceInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid price'**
  String get servicePriceInvalid;

  /// No description provided for @serviceDurationMinLabel.
  ///
  /// In en, this message translates to:
  /// **'Duration (min)'**
  String get serviceDurationMinLabel;

  /// No description provided for @serviceCommissionTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Commission type'**
  String get serviceCommissionTypeLabel;

  /// No description provided for @serviceCommissionPercentLabel.
  ///
  /// In en, this message translates to:
  /// **'Commission %'**
  String get serviceCommissionPercentLabel;

  /// No description provided for @serviceCommissionLakLabel.
  ///
  /// In en, this message translates to:
  /// **'Commission (LAK)'**
  String get serviceCommissionLakLabel;

  /// No description provided for @commissionsStaffLabel.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get commissionsStaffLabel;

  /// No description provided for @commissionsAllStaff.
  ///
  /// In en, this message translates to:
  /// **'All staff'**
  String get commissionsAllStaff;

  /// No description provided for @commissionsStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get commissionsStatusLabel;

  /// No description provided for @commissionsAllStatuses.
  ///
  /// In en, this message translates to:
  /// **'All statuses'**
  String get commissionsAllStatuses;

  /// No description provided for @commissionsNoneFound.
  ///
  /// In en, this message translates to:
  /// **'No commissions found.'**
  String get commissionsNoneFound;

  /// No description provided for @commissionsUnknownStaff.
  ///
  /// In en, this message translates to:
  /// **'Unknown staff'**
  String get commissionsUnknownStaff;

  /// No description provided for @commissionsMarkAs.
  ///
  /// In en, this message translates to:
  /// **'Mark {status}'**
  String commissionsMarkAs(String status);

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Business settings'**
  String get settingsTitle;

  /// No description provided for @settingsReadOnlyNotice.
  ///
  /// In en, this message translates to:
  /// **'You have read-only access. Ask an admin or owner to make changes.'**
  String get settingsReadOnlyNotice;

  /// No description provided for @settingsBusinessNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Business name'**
  String get settingsBusinessNameLabel;

  /// No description provided for @settingsCurrencyCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Currency code (e.g. LAK)'**
  String get settingsCurrencyCodeLabel;

  /// No description provided for @settingsCurrencyCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a 3-letter currency code'**
  String get settingsCurrencyCodeInvalid;

  /// No description provided for @settingsTaxEnabled.
  ///
  /// In en, this message translates to:
  /// **'Tax enabled'**
  String get settingsTaxEnabled;

  /// No description provided for @settingsTaxRateLabel.
  ///
  /// In en, this message translates to:
  /// **'Tax rate (%)'**
  String get settingsTaxRateLabel;

  /// No description provided for @settingsTaxRateInvalidNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a number'**
  String get settingsTaxRateInvalidNumber;

  /// No description provided for @settingsTaxRateRange.
  ///
  /// In en, this message translates to:
  /// **'Must be between 0 and 100'**
  String get settingsTaxRateRange;

  /// No description provided for @settingsLogoUrlOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Logo URL (optional)'**
  String get settingsLogoUrlOptionalLabel;

  /// No description provided for @settingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved.'**
  String get settingsSaved;

  /// No description provided for @settingsLanguageTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageTitle;

  /// No description provided for @settingsLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose the app\'s display language.'**
  String get settingsLanguageSubtitle;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageLao.
  ///
  /// In en, this message translates to:
  /// **'ລາວ'**
  String get languageLao;

  /// No description provided for @dateRangeToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get dateRangeToday;

  /// No description provided for @dateRangeThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get dateRangeThisWeek;

  /// No description provided for @dateRangeThisMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get dateRangeThisMonth;

  /// No description provided for @dateRangeCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get dateRangeCustom;

  /// No description provided for @authShowPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get authShowPassword;

  /// No description provided for @authHidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get authHidePassword;

  /// No description provided for @posQuantityIncrease.
  ///
  /// In en, this message translates to:
  /// **'Increase quantity'**
  String get posQuantityIncrease;

  /// No description provided for @posQuantityDecrease.
  ///
  /// In en, this message translates to:
  /// **'Decrease quantity'**
  String get posQuantityDecrease;

  /// No description provided for @staffManageMemberTooltip.
  ///
  /// In en, this message translates to:
  /// **'Manage staff member'**
  String get staffManageMemberTooltip;

  /// No description provided for @apptBookTitle.
  ///
  /// In en, this message translates to:
  /// **'Book appointment'**
  String get apptBookTitle;

  /// No description provided for @apptWalkIn.
  ///
  /// In en, this message translates to:
  /// **'Walk-in'**
  String get apptWalkIn;

  /// No description provided for @apptCustomerOptional.
  ///
  /// In en, this message translates to:
  /// **'Customer (optional)'**
  String get apptCustomerOptional;

  /// No description provided for @apptStaffLabel.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get apptStaffLabel;

  /// No description provided for @apptServicesLabel.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get apptServicesLabel;

  /// No description provided for @apptSelectAtLeastOneService.
  ///
  /// In en, this message translates to:
  /// **'Select at least one service'**
  String get apptSelectAtLeastOneService;

  /// No description provided for @apptNotesOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes (optional)'**
  String get apptNotesOptionalLabel;

  /// No description provided for @apptCalendarMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get apptCalendarMonth;

  /// No description provided for @apptCalendarWeek.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get apptCalendarWeek;

  /// No description provided for @apptNoAppointmentsThisDay.
  ///
  /// In en, this message translates to:
  /// **'No appointments this day'**
  String get apptNoAppointmentsThisDay;

  /// No description provided for @apptStatusScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get apptStatusScheduled;

  /// No description provided for @apptStatusConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get apptStatusConfirmed;

  /// No description provided for @apptStatusCheckedIn.
  ///
  /// In en, this message translates to:
  /// **'Checked in'**
  String get apptStatusCheckedIn;

  /// No description provided for @apptStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get apptStatusCompleted;

  /// No description provided for @apptStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get apptStatusCancelled;

  /// No description provided for @apptStatusNoShow.
  ///
  /// In en, this message translates to:
  /// **'No-show'**
  String get apptStatusNoShow;

  /// No description provided for @apptCancelReasonTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel appointment'**
  String get apptCancelReasonTitle;

  /// No description provided for @apptCancelReasonOptionalHint.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get apptCancelReasonOptionalHint;

  /// No description provided for @apptReschedule.
  ///
  /// In en, this message translates to:
  /// **'Reschedule'**
  String get apptReschedule;

  /// No description provided for @apptRescheduleConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm reschedule'**
  String get apptRescheduleConfirm;

  /// No description provided for @pkgAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add package'**
  String get pkgAddTitle;

  /// No description provided for @pkgEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit package'**
  String get pkgEditTitle;

  /// No description provided for @pkgEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No packages yet'**
  String get pkgEmptyTitle;

  /// No description provided for @pkgEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add your first package to start selling memberships.'**
  String get pkgEmptySubtitle;

  /// No description provided for @pkgNoServicesYet.
  ///
  /// In en, this message translates to:
  /// **'No services yet'**
  String get pkgNoServicesYet;

  /// No description provided for @pkgNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Package name'**
  String get pkgNameLabel;

  /// No description provided for @pkgDescriptionOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get pkgDescriptionOptionalLabel;

  /// No description provided for @pkgPriceLak.
  ///
  /// In en, this message translates to:
  /// **'Price (LAK)'**
  String get pkgPriceLak;

  /// No description provided for @pkgValidityDaysOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Validity in days (optional)'**
  String get pkgValidityDaysOptionalLabel;

  /// No description provided for @pkgServicesLabel.
  ///
  /// In en, this message translates to:
  /// **'Included services'**
  String get pkgServicesLabel;

  /// No description provided for @pkgServiceLabel.
  ///
  /// In en, this message translates to:
  /// **'Service'**
  String get pkgServiceLabel;

  /// No description provided for @pkgSessionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get pkgSessionsLabel;

  /// No description provided for @pkgAddServiceAction.
  ///
  /// In en, this message translates to:
  /// **'Add service'**
  String get pkgAddServiceAction;

  /// No description provided for @pkgSelectAtLeastOneService.
  ///
  /// In en, this message translates to:
  /// **'Select at least one service'**
  String get pkgSelectAtLeastOneService;

  /// No description provided for @pkgTab.
  ///
  /// In en, this message translates to:
  /// **'Packages'**
  String get pkgTab;

  /// No description provided for @pkgSelectCustomer.
  ///
  /// In en, this message translates to:
  /// **'Select customer'**
  String get pkgSelectCustomer;

  /// No description provided for @pkgCustomerRequired.
  ///
  /// In en, this message translates to:
  /// **'A customer is required to purchase a package'**
  String get pkgCustomerRequired;

  /// No description provided for @pkgPurchaseAction.
  ///
  /// In en, this message translates to:
  /// **'Purchase package'**
  String get pkgPurchaseAction;

  /// No description provided for @pkgUseEntitlementLabel.
  ///
  /// In en, this message translates to:
  /// **'Use package session'**
  String get pkgUseEntitlementLabel;

  /// No description provided for @pkgPayNormally.
  ///
  /// In en, this message translates to:
  /// **'Pay normally'**
  String get pkgPayNormally;

  /// No description provided for @pkgEntitlementOption.
  ///
  /// In en, this message translates to:
  /// **'{remaining} session(s) remaining'**
  String pkgEntitlementOption(int remaining);

  /// No description provided for @pkgCoveredByPackage.
  ///
  /// In en, this message translates to:
  /// **'Covered by package'**
  String get pkgCoveredByPackage;

  /// No description provided for @pkgRedemptionRemaining.
  ///
  /// In en, this message translates to:
  /// **'{name}: {remaining} of {total} sessions remaining'**
  String pkgRedemptionRemaining(String name, int remaining, int total);

  /// No description provided for @pkgMembershipsTitle.
  ///
  /// In en, this message translates to:
  /// **'Memberships'**
  String get pkgMembershipsTitle;

  /// No description provided for @pkgNoMembershipsYet.
  ///
  /// In en, this message translates to:
  /// **'No packages purchased yet.'**
  String get pkgNoMembershipsYet;

  /// No description provided for @pkgNeverExpires.
  ///
  /// In en, this message translates to:
  /// **'Never expires'**
  String get pkgNeverExpires;

  /// No description provided for @pkgExpiresOn.
  ///
  /// In en, this message translates to:
  /// **'Expires {date}'**
  String pkgExpiresOn(String date);

  /// No description provided for @pkgItemRemaining.
  ///
  /// In en, this message translates to:
  /// **'{name}: {remaining} of {total} remaining'**
  String pkgItemRemaining(String name, int remaining, int total);

  /// No description provided for @pkgStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get pkgStatusActive;

  /// No description provided for @pkgStatusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get pkgStatusExpired;

  /// No description provided for @pkgStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get pkgStatusCancelled;

  /// No description provided for @navFollowUps.
  ///
  /// In en, this message translates to:
  /// **'Follow-ups'**
  String get navFollowUps;

  /// No description provided for @reportsFollowUpsDueToday.
  ///
  /// In en, this message translates to:
  /// **'Follow-ups due today'**
  String get reportsFollowUpsDueToday;

  /// No description provided for @reportsFollowUpsOverdue.
  ///
  /// In en, this message translates to:
  /// **'Follow-ups overdue'**
  String get reportsFollowUpsOverdue;

  /// No description provided for @followUpStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get followUpStatusPending;

  /// No description provided for @followUpStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get followUpStatusCompleted;

  /// No description provided for @followUpStatusMissed.
  ///
  /// In en, this message translates to:
  /// **'Missed'**
  String get followUpStatusMissed;

  /// No description provided for @followUpStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get followUpStatusCancelled;

  /// No description provided for @followUpStaffRequired.
  ///
  /// In en, this message translates to:
  /// **'Select a staff member'**
  String get followUpStaffRequired;

  /// No description provided for @followUpRescheduleTitle.
  ///
  /// In en, this message translates to:
  /// **'Reschedule follow-up'**
  String get followUpRescheduleTitle;

  /// No description provided for @followUpFormTitle.
  ///
  /// In en, this message translates to:
  /// **'Add follow-up'**
  String get followUpFormTitle;

  /// No description provided for @followUpStaffLabel.
  ///
  /// In en, this message translates to:
  /// **'Assigned staff'**
  String get followUpStaffLabel;

  /// No description provided for @followUpNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get followUpNotesLabel;

  /// No description provided for @followUpRescheduleConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm reschedule'**
  String get followUpRescheduleConfirm;

  /// No description provided for @followUpSaveAction.
  ///
  /// In en, this message translates to:
  /// **'Save follow-up'**
  String get followUpSaveAction;

  /// No description provided for @followUpHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Follow-ups'**
  String get followUpHistoryTitle;

  /// No description provided for @followUpAddAction.
  ///
  /// In en, this message translates to:
  /// **'Add follow-up'**
  String get followUpAddAction;

  /// No description provided for @followUpNoneYet.
  ///
  /// In en, this message translates to:
  /// **'No follow-ups yet.'**
  String get followUpNoneYet;

  /// No description provided for @followUpOverdueLabel.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get followUpOverdueLabel;

  /// No description provided for @followUpListEmpty.
  ///
  /// In en, this message translates to:
  /// **'No follow-ups in this filter.'**
  String get followUpListEmpty;

  /// No description provided for @followUpFilterDueToday.
  ///
  /// In en, this message translates to:
  /// **'Due today'**
  String get followUpFilterDueToday;

  /// No description provided for @followUpFilterOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get followUpFilterOverdue;

  /// No description provided for @followUpFilterUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get followUpFilterUpcoming;

  /// No description provided for @followUpFilterCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get followUpFilterCompleted;

  /// No description provided for @followUpLineStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'LINE reminders'**
  String get followUpLineStatusTitle;

  /// No description provided for @followUpLineNotLinked.
  ///
  /// In en, this message translates to:
  /// **'Not linked to LINE'**
  String get followUpLineNotLinked;

  /// No description provided for @followUpLineGenerateCode.
  ///
  /// In en, this message translates to:
  /// **'Generate linking code'**
  String get followUpLineGenerateCode;

  /// No description provided for @followUpLineLinkedSince.
  ///
  /// In en, this message translates to:
  /// **'Linked to LINE since {date}'**
  String followUpLineLinkedSince(String date);

  /// No description provided for @followUpLineUnlink.
  ///
  /// In en, this message translates to:
  /// **'Unlink'**
  String get followUpLineUnlink;

  /// No description provided for @followUpLineLinkCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'LINE linking code'**
  String get followUpLineLinkCodeTitle;

  /// No description provided for @followUpLineLinkCodeInstructions.
  ///
  /// In en, this message translates to:
  /// **'Ask the customer to send this code as a message to the business\'s LINE Official Account to receive reminders.'**
  String get followUpLineLinkCodeInstructions;
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
      <String>['en', 'lo'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'lo':
      return AppLocalizationsLo();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
