// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Beauty Clinic POS';

  @override
  String get commonSave => 'Save';

  @override
  String get commonSaveChanges => 'Save changes';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonSearch => 'Search';

  @override
  String get commonRequired => 'Required';

  @override
  String get commonOptional => 'optional';

  @override
  String get commonNotSpecified => 'Not specified';

  @override
  String get commonNoPhoneOnFile => 'No phone on file';

  @override
  String get commonCashier => 'Cashier';

  @override
  String get commonChoose => 'Choose';

  @override
  String get commonClose => 'Close';

  @override
  String get authLoginTagline => 'Sign in to your business';

  @override
  String get authEmailLabel => 'Email';

  @override
  String get authEmailInvalid => 'Enter a valid email';

  @override
  String get authPasswordLabel => 'Password';

  @override
  String get authPasswordRequired => 'Enter your password';

  @override
  String get authForgotPassword => 'Forgot password?';

  @override
  String get authSignIn => 'Sign in';

  @override
  String get authNoAccountYet => 'Don\'t have a business account yet?';

  @override
  String get authCreateOne => 'Create one';

  @override
  String get authCheckYourEmail => 'Check your email';

  @override
  String authResetLinkSentTo(String email) {
    return 'If an account exists for $email, a reset link has been sent.';
  }

  @override
  String get authResetPasswordTitle => 'Reset your password';

  @override
  String get authResetPasswordSubtitle => 'We\'ll email you a reset link.';

  @override
  String get authSendResetLink => 'Send reset link';

  @override
  String authConfirmationSentTo(String email) {
    return 'We\'ve sent a confirmation link to $email. Confirm your email, then sign in.';
  }

  @override
  String get authBackToSignIn => 'Back to sign in';

  @override
  String get authCreateAccountTitle => 'Create your account';

  @override
  String get authCreateAccountSubtitle => 'You\'ll set up your business next.';

  @override
  String get authFullNameLabel => 'Full name';

  @override
  String get authNameRequired => 'Enter your name';

  @override
  String get authPasswordTooShortValidation => 'Use at least 6 characters';

  @override
  String get authCreateAccount => 'Create account';

  @override
  String get authSignOut => 'Sign out';

  @override
  String get authSetUpBusinessTitle => 'Set up your business';

  @override
  String get authSetUpBusinessSubtitle =>
      'This creates your clinic\'s workspace. You\'ll be the owner.';

  @override
  String get authBusinessNameLabel => 'Business name';

  @override
  String get authBusinessNameRequired => 'Enter a business name';

  @override
  String get authPhoneOptionalLabel => 'Phone (optional)';

  @override
  String get authCreateBusiness => 'Create business';

  @override
  String get errorIncorrectCredentials => 'Incorrect email or password.';

  @override
  String get errorEmailNotConfirmed =>
      'Please confirm your email before signing in.';

  @override
  String get errorUserAlreadyRegistered =>
      'An account with this email already exists.';

  @override
  String get errorPasswordTooShort =>
      'Password is too short. Use at least 6 characters.';

  @override
  String get errorAuthGeneric => 'Authentication failed. Please try again.';

  @override
  String get errorRecordExists => 'That record already exists.';

  @override
  String get errorNoPermission => 'You don\'t have permission to do that.';

  @override
  String get errorSaveGeneric =>
      'Something went wrong saving your data. Please try again.';

  @override
  String get errorGeneric =>
      'Something went wrong. Please check your connection and try again.';

  @override
  String get posWalkInCustomer => 'Walk-in customer';

  @override
  String get posCartEmptyTitle => 'Cart is empty';

  @override
  String get posCartEmptySubtitle => 'Tap a service or product to add it';

  @override
  String get posSubtotal => 'Subtotal';

  @override
  String get posDiscount => 'Discount';

  @override
  String get posTax => 'Tax';

  @override
  String get posTotal => 'Total';

  @override
  String get posChange => 'Change';

  @override
  String get posCompleteSale => 'Complete sale';

  @override
  String get posRemoveTooltip => 'Remove';

  @override
  String get posStaffForCommission => 'Staff (for commission)';

  @override
  String get posUnassigned => 'Unassigned';

  @override
  String get posPaymentMethod => 'Payment method';

  @override
  String get posAmountPaidLak => 'Amount paid (LAK)';

  @override
  String get posPaymentInsufficient =>
      'Payment amount cannot be less than the sale total.';

  @override
  String get posAcceptDepositAction => 'Accept deposit';

  @override
  String get posDepositTitle => 'Accept deposit';

  @override
  String get posDepositAmountLabel => 'Initial payment';

  @override
  String get posDepositAmountRequired => 'Enter a deposit amount';

  @override
  String get posDepositRemainingBalance => 'Remaining balance';

  @override
  String get posDepositConfirmAction => 'Confirm deposit';

  @override
  String get posDepositResultTitle => 'Deposit recorded';

  @override
  String get posDepositResultPaymentStatus => 'Payment status';

  @override
  String get posDepositDoneAction => 'Done';

  @override
  String get paymentMethodCash => 'Cash';

  @override
  String get paymentMethodBankTransfer => 'Bank transfer';

  @override
  String get paymentMethodCard => 'Card';

  @override
  String get paymentMethodOther => 'Other';

  @override
  String get salesStatusVoided => 'Voided';

  @override
  String get salesStatusRefunded => 'Refunded';

  @override
  String get salesStatusCompleted => 'Completed';

  @override
  String get salesVoidConfirmTitle => 'Void this sale?';

  @override
  String get salesVoidConfirmBody =>
      'This reverses stock and commissions for this sale and marks its payment refunded. This cannot be undone.';

  @override
  String get salesVoidReasonLabel => 'Reason';

  @override
  String get salesVoidReasonHint => 'Why is this sale being voided?';

  @override
  String get salesVoidAction => 'Void sale';

  @override
  String get salesVoiding => 'Voiding…';

  @override
  String get salesVoidedSnackbar => 'Sale voided.';

  @override
  String get salesDetailFallbackTitle => 'Sale';

  @override
  String get salesVoidDetailsTitle => 'Void details';

  @override
  String get salesRowPaid => 'Paid';

  @override
  String get salesStatusPending => 'Pending';

  @override
  String get salesStatusPartial => 'Partially paid';

  @override
  String get salesRowOutstanding => 'Outstanding balance';

  @override
  String get salesPaymentHistoryTitle => 'Payment history';

  @override
  String get salesNoPayments => 'No payments recorded yet.';

  @override
  String get salesSettleBalanceAction => 'Settle balance';

  @override
  String get salesSettleBalanceTitle => 'Settle outstanding balance';

  @override
  String get salesSettleAmountLabel => 'Payment amount';

  @override
  String get salesSettleReferenceOptionalLabel => 'Reference (optional)';

  @override
  String get salesSettleSubmitAction => 'Record payment';

  @override
  String get salesSettleAmountExceedsBalance =>
      'Amount cannot exceed the outstanding balance';

  @override
  String get salesSettleSuccessSnackbar => 'Payment recorded.';

  @override
  String get customersFallbackTitle => 'Customer';

  @override
  String get customersTotalSpent => 'Total spent';

  @override
  String get customersVisits => 'Visits';

  @override
  String get customersLastVisit => 'Last visit';

  @override
  String get customersPurchaseHistory => 'Purchase history';

  @override
  String get customersNotes => 'Notes';

  @override
  String get customersNoSalesYet => 'No sales yet.';

  @override
  String get customersNoNotesYet => 'No notes yet.';

  @override
  String get customersAddNoteHint => 'Add a note...';

  @override
  String get treatmentHistoryTitle => 'Treatment history';

  @override
  String get treatmentNoneYet => 'No treatments recorded yet.';

  @override
  String get treatmentAddAction => 'Add treatment';

  @override
  String get treatmentFormTitle => 'Add treatment';

  @override
  String get treatmentServiceLabel => 'Service';

  @override
  String get treatmentStaffLabel => 'Staff';

  @override
  String get treatmentDateLabel => 'Treatment date';

  @override
  String get treatmentNotesLabel => 'Notes';

  @override
  String get treatmentResultLabel => 'Result';

  @override
  String get treatmentFeedbackLabel => 'Customer feedback';

  @override
  String get treatmentBeforeAfterLabel => 'Before/After reference (URL)';

  @override
  String get treatmentFollowUpLabel => 'Follow-up date';

  @override
  String get treatmentSaveAction => 'Save treatment';

  @override
  String get treatmentServiceRequired => 'Select a service';

  @override
  String get treatmentStaffRequired => 'Select a staff member';

  @override
  String get treatmentRowResult => 'Result';

  @override
  String get treatmentRowFeedback => 'Feedback';

  @override
  String get treatmentRowFollowUp => 'Follow-up';

  @override
  String get consultationHistoryTitle => 'Consultations';

  @override
  String get consultationNoneYet => 'No consultations recorded yet.';

  @override
  String get consultationAddAction => 'Add consultation';

  @override
  String get consultationFormTitle => 'Add consultation';

  @override
  String get consultationStaffLabel => 'Staff';

  @override
  String get consultationDateLabel => 'Consultation date';

  @override
  String get consultationRecommendedServiceLabel =>
      'Recommended service (optional)';

  @override
  String get consultationRecommendedServiceNone => 'None';

  @override
  String get consultationNotesLabel => 'Consultation notes';

  @override
  String get consultationConcernsLabel => 'Customer concerns';

  @override
  String get consultationObservationsLabel => 'Observations';

  @override
  String get consultationConsiderationsLabel => 'Considerations';

  @override
  String get consultationAssessmentLabel => 'Assessment';

  @override
  String get consultationRecommendationLabel => 'Recommendation notes';

  @override
  String get consultationSaveAction => 'Save consultation';

  @override
  String get consultationStaffRequired => 'Select a staff member';

  @override
  String get consultationRowRecommended => 'Recommended';

  @override
  String get consultationRowConcerns => 'Concerns';

  @override
  String get consultationRowAssessment => 'Assessment';

  @override
  String get customersNameLabel => 'Name';

  @override
  String get customersGenderOptionalLabel => 'Gender (optional)';

  @override
  String get customersGenderMale => 'Male';

  @override
  String get customersGenderFemale => 'Female';

  @override
  String get customersGenderOther => 'Other';

  @override
  String get customersNotesOptionalLabel => 'Notes (optional)';

  @override
  String get customersEditTitle => 'Edit customer';

  @override
  String get customersAddTitle => 'Add customer';

  @override
  String get customersSearchHint => 'Search by name or phone';

  @override
  String get customersEmptyTitle => 'No customers yet';

  @override
  String get customersEmptySubtitle =>
      'Add your first customer, or they\'ll be created automatically at checkout.';

  @override
  String customersVisitsCount(int count) {
    return '$count visits';
  }

  @override
  String get posReceiptSaleComplete => 'Sale complete';

  @override
  String get posReceiptReceipt => 'Receipt';

  @override
  String get posReceiptDate => 'Date';

  @override
  String get posReceiptCashier => 'Cashier';

  @override
  String get posReceiptCustomer => 'Customer';

  @override
  String get posReceiptWalkIn => 'Walk-in';

  @override
  String posReceiptPaidVia(String method) {
    return 'Paid ($method)';
  }

  @override
  String get posReceiptThankYou => 'Thank you!';

  @override
  String get posReceiptNewSale => 'New sale';

  @override
  String get posReceiptPrint => 'Print receipt';

  @override
  String get posReceiptPrinting => 'Printing...';

  @override
  String get posReceiptPrintConfirmed => 'Receipt sent to printer';

  @override
  String get posReceiptPrintUncertain =>
      'Printer status unknown -- check the printer';

  @override
  String get posReceiptPrintFailed => 'Couldn\'t reach the printer';

  @override
  String get posReceiptPrintNotConfigured => 'No receipt printer configured';

  @override
  String posCartItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '$count item',
    );
    return '$_temp0';
  }

  @override
  String get posSelectCustomer => 'Select customer';

  @override
  String get posSearchNameOrPhone => 'Search name or phone';

  @override
  String get posNoCustomersFound => 'No customers found';

  @override
  String posCreateAsNewCustomer(String query) {
    return 'Create \"$query\" as new customer';
  }

  @override
  String get posSearchServicesOrProducts => 'Search services or products';

  @override
  String get posServicesTab => 'Services';

  @override
  String get posProductsTab => 'Products';

  @override
  String get posNoServicesYet => 'No services yet';

  @override
  String get posNoProductsYet => 'No products yet';

  @override
  String get posNoMatches => 'No matches';

  @override
  String get posOutOfStock => 'Out of stock';

  @override
  String posItemsLeft(String price, int count) {
    return '$price · $count left';
  }

  @override
  String get salesSearchByReceiptHint => 'Search by receipt number';

  @override
  String get salesNoSalesFound => 'No sales found.';

  @override
  String get roleOwner => 'Owner';

  @override
  String get roleAdmin => 'Admin';

  @override
  String get roleManager => 'Manager';

  @override
  String get roleCashier => 'Cashier';

  @override
  String get roleStaff => 'Staff';

  @override
  String get movementTypePurchase => 'Restock (purchase)';

  @override
  String get movementTypeSale => 'Sale';

  @override
  String get movementTypeReturn => 'Return';

  @override
  String get movementTypeAdjustment => 'Adjustment';

  @override
  String get movementTypeDamage => 'Damage';

  @override
  String get movementTypeExpired => 'Expired';

  @override
  String get staffInviteButton => 'Invite';

  @override
  String get staffEmptyState => 'No staff yet.';

  @override
  String staffRoleInactiveSuffix(String role) {
    return '$role · Inactive';
  }

  @override
  String get staffChangeRole => 'Change role';

  @override
  String get staffDeactivate => 'Deactivate';

  @override
  String get staffReactivate => 'Reactivate';

  @override
  String get staffInviteTitle => 'Invite staff';

  @override
  String get staffInviteSubtitle =>
      'They must already have an account. Enter their email to look them up.';

  @override
  String get staffFind => 'Find';

  @override
  String get staffNoAccountFound =>
      'No account found with this email. They need to sign up first.';

  @override
  String get staffAccountFound => 'Account found';

  @override
  String get staffRoleLabel => 'Role';

  @override
  String get staffInviteAction => 'Invite';

  @override
  String get invTabStock => 'Stock';

  @override
  String get invTabMovements => 'Movements';

  @override
  String get invTabSuppliers => 'Suppliers';

  @override
  String get invNoProductsYetTitle => 'No products yet';

  @override
  String get invNoProductsYetSubtitle =>
      'Add products in the Products tab to start tracking stock.';

  @override
  String invLowStockWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count products at or below its low-stock threshold.',
      one: '$count product at or below its low-stock threshold.',
    );
    return '$_temp0';
  }

  @override
  String invLowStockAlertAt(int threshold) {
    return 'Low-stock alert at $threshold';
  }

  @override
  String invInStock(int count) {
    return '$count in stock';
  }

  @override
  String get invAdjustStockTooltip => 'Adjust stock';

  @override
  String get invNoMovementsYet =>
      'No stock movements yet. Sales and manual adjustments will appear here.';

  @override
  String get invUnknownProduct => 'Unknown product';

  @override
  String get invAddSupplier => 'Add supplier';

  @override
  String get invEditSupplier => 'Edit supplier';

  @override
  String get invNoSuppliersYetTitle => 'No suppliers yet';

  @override
  String get invNoSuppliersYetSubtitle =>
      'Track who you restock products from.';

  @override
  String get invNoContactInfo => 'No contact info on file';

  @override
  String get invInactive => 'Inactive';

  @override
  String get invAdjustStockTitle => 'Adjust stock';

  @override
  String invAdjustStockSubtitle(String name, int count) {
    return '$name · currently $count in stock';
  }

  @override
  String get invAddStockSegment => 'Add stock';

  @override
  String get invRemoveStockSegment => 'Remove stock';

  @override
  String get invQuantityLabel => 'Quantity';

  @override
  String get invQuantityPositiveRequired => 'Enter a positive whole number';

  @override
  String get invReasonLabel => 'Reason';

  @override
  String get invNoteOptionalLabel => 'Note (optional)';

  @override
  String get invSaveAdjustment => 'Save adjustment';

  @override
  String get supplierNameLabel => 'Supplier name';

  @override
  String get commonActive => 'Active';

  @override
  String get customersEmailOptionalLabel => 'Email (optional)';

  @override
  String get customersAddressOptionalLabel => 'Address (optional)';

  @override
  String get expensesEditTitle => 'Edit expense';

  @override
  String get expensesAddTitle => 'Add expense';

  @override
  String get expensesAmountLak => 'Amount (LAK)';

  @override
  String get expensesPositiveAmountRequired => 'Enter a positive amount';

  @override
  String get expensesCategoryOptionalLabel => 'Category (optional)';

  @override
  String get expensesNoCategory => 'No category';

  @override
  String get expensesDateLabel => 'Date';

  @override
  String get expensesDescriptionOptionalLabel => 'Description (optional)';

  @override
  String get expensesManageCategoriesTooltip => 'Manage categories';

  @override
  String get expensesAllCategories => 'All categories';

  @override
  String get expensesNoExpensesTitle => 'No expenses recorded';

  @override
  String get expensesNoExpensesSubtitle =>
      'Track rent, utilities, and other business costs here.';

  @override
  String get expensesTotalLabel => 'Total: ';

  @override
  String get expensesUncategorized => 'Uncategorized';

  @override
  String get expensesDeleteTitle => 'Delete expense?';

  @override
  String get expensesDeleteBody => 'This cannot be undone.';

  @override
  String get expenseCategoriesTitle => 'Expense categories';

  @override
  String get expenseNewCategoryNameLabel => 'New category name';

  @override
  String get expenseNoCategoriesYet => 'No categories yet.';

  @override
  String get categoryLabel => 'Category';

  @override
  String get navOverview => 'Overview';

  @override
  String get navPos => 'POS';

  @override
  String get navSales => 'Sales';

  @override
  String get navCustomers => 'Customers';

  @override
  String get navAppointments => 'Appointments';

  @override
  String get navServices => 'Services';

  @override
  String get navPackages => 'Packages';

  @override
  String get navProducts => 'Products';

  @override
  String get navInventory => 'Inventory';

  @override
  String get navStaff => 'Staff';

  @override
  String get navCommissions => 'Commissions';

  @override
  String get navExpenses => 'Expenses';

  @override
  String get navReports => 'Reports';

  @override
  String get navAuditLog => 'Audit Log';

  @override
  String get navSettings => 'Settings';

  @override
  String get navSoon => 'Soon';

  @override
  String navNotBuiltYet(String label) {
    return '$label is not built yet';
  }

  @override
  String get navScheduledLater =>
      'This section is scheduled later in the build plan.';

  @override
  String get overviewIntro =>
      'You\'re authenticated and your business workspace is set up. POS, customers, inventory, and reporting come online as each part of the build lands.';

  @override
  String get commonRetry => 'Retry';

  @override
  String get reportsTodayTagline => 'Today\'s business at a glance.';

  @override
  String get reportsTodaySales => 'Today\'s sales';

  @override
  String reportsSalesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sales',
      one: '$count sale',
    );
    return '$_temp0';
  }

  @override
  String get reportsCommission => 'Commission';

  @override
  String get reportsExpenses => 'Expenses';

  @override
  String get reportsEstimatedProfit => 'Estimated profit';

  @override
  String get reportsRevenue => 'Revenue';

  @override
  String get reportsCogs => 'Cost of goods sold';

  @override
  String get reportsExportCsv => 'Export CSV';

  @override
  String get reportsCopiedToClipboard => 'Report copied to clipboard as CSV.';

  @override
  String get reportsRevenueByDay => 'Revenue by day';

  @override
  String get reportsSalesInRange => 'Sales in range';

  @override
  String get reportsNoSalesInRange => 'No sales in this range yet.';

  @override
  String get reportsColReceipt => 'Receipt';

  @override
  String get reportsColDate => 'Date';

  @override
  String get reportsColStatus => 'Status';

  @override
  String get reportsColAmount => 'Amount';

  @override
  String get reportsCsvPaymentStatus => 'Payment status';

  @override
  String get auditActionLabel => 'Action';

  @override
  String get auditAllActions => 'All actions';

  @override
  String get auditEntityLabel => 'Entity';

  @override
  String get auditAllEntities => 'All entities';

  @override
  String get auditEmptyState => 'No audit events for this filter.';

  @override
  String get auditSystemActor => 'System';

  @override
  String get auditBefore => 'Before';

  @override
  String get auditAfter => 'After';

  @override
  String get auditDetails => 'Details';

  @override
  String get commissionKindPercentage => 'Percentage';

  @override
  String get commissionKindFixed => 'Fixed amount';

  @override
  String get commissionStatusPending => 'Pending';

  @override
  String get commissionStatusApproved => 'Approved';

  @override
  String get commissionStatusReversed => 'Reversed';

  @override
  String get commissionStatusPaid => 'Paid';

  @override
  String get productsAddTitle => 'Add product';

  @override
  String get productsEditTitle => 'Edit product';

  @override
  String get productsEmptyTitle => 'No products yet';

  @override
  String get productsEmptySubtitle =>
      'Add retail products to sell alongside services.';

  @override
  String productsSkuPrefix(String sku) {
    return 'SKU $sku';
  }

  @override
  String get productNameLabel => 'Product name';

  @override
  String get productSkuOptionalLabel => 'SKU (optional)';

  @override
  String get productSellingPriceLak => 'Selling price (LAK)';

  @override
  String get productCostPriceLak => 'Cost price (LAK)';

  @override
  String get productStockQuantityLabel => 'Stock quantity';

  @override
  String get productLowStockAlertAtLabel => 'Low-stock alert at';

  @override
  String get commonInvalid => 'Invalid';

  @override
  String get servicesAddTitle => 'Add service';

  @override
  String get servicesEditTitle => 'Edit service';

  @override
  String get servicesEmptyTitle => 'No services yet';

  @override
  String get servicesEmptySubtitle =>
      'Add your first service to start taking bookings and sales.';

  @override
  String servicesDurationCommission(
    int minutes,
    String label,
    String value,
    String percentSuffix,
  ) {
    return '$minutes min · $label $value$percentSuffix commission';
  }

  @override
  String get serviceNameLabel => 'Service name';

  @override
  String get serviceDescriptionOptionalLabel => 'Description (optional)';

  @override
  String get servicePriceLak => 'Price (LAK)';

  @override
  String get servicePriceInvalid => 'Enter a valid price';

  @override
  String get serviceDurationMinLabel => 'Duration (min)';

  @override
  String get serviceCommissionTypeLabel => 'Commission type';

  @override
  String get serviceCommissionPercentLabel => 'Commission %';

  @override
  String get serviceCommissionLakLabel => 'Commission (LAK)';

  @override
  String get commissionsStaffLabel => 'Staff';

  @override
  String get commissionsAllStaff => 'All staff';

  @override
  String get commissionsStatusLabel => 'Status';

  @override
  String get commissionsAllStatuses => 'All statuses';

  @override
  String get commissionsNoneFound => 'No commissions found.';

  @override
  String get commissionsUnknownStaff => 'Unknown staff';

  @override
  String commissionsMarkAs(String status) {
    return 'Mark $status';
  }

  @override
  String get settingsTitle => 'Business settings';

  @override
  String get settingsReadOnlyNotice =>
      'You have read-only access. Ask an admin or owner to make changes.';

  @override
  String get settingsBusinessNameLabel => 'Business name';

  @override
  String get settingsCurrencyCodeLabel => 'Currency code (e.g. LAK)';

  @override
  String get settingsCurrencyCodeInvalid => 'Enter a 3-letter currency code';

  @override
  String get settingsTaxEnabled => 'Tax enabled';

  @override
  String get settingsTaxRateLabel => 'Tax rate (%)';

  @override
  String get settingsTaxRateInvalidNumber => 'Enter a number';

  @override
  String get settingsTaxRateRange => 'Must be between 0 and 100';

  @override
  String get settingsLogoUrlOptionalLabel => 'Logo URL (optional)';

  @override
  String get settingsSaved => 'Settings saved.';

  @override
  String get settingsLanguageTitle => 'Language';

  @override
  String get settingsLanguageSubtitle => 'Choose the app\'s display language.';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageLao => 'ລາວ';

  @override
  String get dateRangeToday => 'Today';

  @override
  String get dateRangeThisWeek => 'This week';

  @override
  String get dateRangeThisMonth => 'This month';

  @override
  String get dateRangeCustom => 'Custom';

  @override
  String get authShowPassword => 'Show password';

  @override
  String get authHidePassword => 'Hide password';

  @override
  String get posQuantityIncrease => 'Increase quantity';

  @override
  String get posQuantityDecrease => 'Decrease quantity';

  @override
  String get staffManageMemberTooltip => 'Manage staff member';

  @override
  String get apptBookTitle => 'Book appointment';

  @override
  String get apptWalkIn => 'Walk-in';

  @override
  String get apptCustomerOptional => 'Customer (optional)';

  @override
  String get apptStaffLabel => 'Staff';

  @override
  String get apptServicesLabel => 'Services';

  @override
  String get apptSelectAtLeastOneService => 'Select at least one service';

  @override
  String get apptNotesOptionalLabel => 'Notes (optional)';

  @override
  String get apptCalendarMonth => 'Month';

  @override
  String get apptCalendarWeek => 'Week';

  @override
  String get apptNoAppointmentsThisDay => 'No appointments this day';

  @override
  String get apptStatusScheduled => 'Scheduled';

  @override
  String get apptStatusConfirmed => 'Confirmed';

  @override
  String get apptStatusCheckedIn => 'Checked in';

  @override
  String get apptStatusCompleted => 'Completed';

  @override
  String get apptStatusCancelled => 'Cancelled';

  @override
  String get apptStatusNoShow => 'No-show';

  @override
  String get apptCancelReasonTitle => 'Cancel appointment';

  @override
  String get apptCancelReasonOptionalHint => 'Reason (optional)';

  @override
  String get apptReschedule => 'Reschedule';

  @override
  String get apptRescheduleConfirm => 'Confirm reschedule';

  @override
  String get pkgAddTitle => 'Add package';

  @override
  String get pkgEditTitle => 'Edit package';

  @override
  String get pkgEmptyTitle => 'No packages yet';

  @override
  String get pkgEmptySubtitle =>
      'Add your first package to start selling memberships.';

  @override
  String get pkgNoServicesYet => 'No services yet';

  @override
  String get pkgNameLabel => 'Package name';

  @override
  String get pkgDescriptionOptionalLabel => 'Description (optional)';

  @override
  String get pkgPriceLak => 'Price (LAK)';

  @override
  String get pkgValidityDaysOptionalLabel => 'Validity in days (optional)';

  @override
  String get pkgServicesLabel => 'Included services';

  @override
  String get pkgServiceLabel => 'Service';

  @override
  String get pkgSessionsLabel => 'Sessions';

  @override
  String get pkgAddServiceAction => 'Add service';

  @override
  String get pkgSelectAtLeastOneService => 'Select at least one service';

  @override
  String get pkgTab => 'Packages';

  @override
  String get pkgSelectCustomer => 'Select customer';

  @override
  String get pkgCustomerRequired =>
      'A customer is required to purchase a package';

  @override
  String get pkgPurchaseAction => 'Purchase package';

  @override
  String get pkgUseEntitlementLabel => 'Use package session';

  @override
  String get pkgPayNormally => 'Pay normally';

  @override
  String pkgEntitlementOption(int remaining) {
    return '$remaining session(s) remaining';
  }

  @override
  String get pkgCoveredByPackage => 'Covered by package';

  @override
  String pkgRedemptionRemaining(String name, int remaining, int total) {
    return '$name: $remaining of $total sessions remaining';
  }

  @override
  String get pkgMembershipsTitle => 'Memberships';

  @override
  String get pkgNoMembershipsYet => 'No packages purchased yet.';

  @override
  String get pkgNeverExpires => 'Never expires';

  @override
  String pkgExpiresOn(String date) {
    return 'Expires $date';
  }

  @override
  String pkgItemRemaining(String name, int remaining, int total) {
    return '$name: $remaining of $total remaining';
  }

  @override
  String get pkgStatusActive => 'Active';

  @override
  String get pkgStatusExpired => 'Expired';

  @override
  String get pkgStatusCancelled => 'Cancelled';

  @override
  String get navFollowUps => 'Follow-ups';

  @override
  String get reportsFollowUpsDueToday => 'Follow-ups due today';

  @override
  String get reportsFollowUpsOverdue => 'Follow-ups overdue';

  @override
  String get followUpStatusPending => 'Pending';

  @override
  String get followUpStatusCompleted => 'Completed';

  @override
  String get followUpStatusMissed => 'Missed';

  @override
  String get followUpStatusCancelled => 'Cancelled';

  @override
  String get followUpStaffRequired => 'Select a staff member';

  @override
  String get followUpRescheduleTitle => 'Reschedule follow-up';

  @override
  String get followUpFormTitle => 'Add follow-up';

  @override
  String get followUpStaffLabel => 'Assigned staff';

  @override
  String get followUpNotesLabel => 'Notes';

  @override
  String get followUpRescheduleConfirm => 'Confirm reschedule';

  @override
  String get followUpSaveAction => 'Save follow-up';

  @override
  String get followUpHistoryTitle => 'Follow-ups';

  @override
  String get followUpAddAction => 'Add follow-up';

  @override
  String get followUpNoneYet => 'No follow-ups yet.';

  @override
  String get followUpOverdueLabel => 'Overdue';

  @override
  String get followUpListEmpty => 'No follow-ups in this filter.';

  @override
  String get followUpFilterDueToday => 'Due today';

  @override
  String get followUpFilterOverdue => 'Overdue';

  @override
  String get followUpFilterUpcoming => 'Upcoming';

  @override
  String get followUpFilterCompleted => 'Completed';

  @override
  String get followUpLineStatusTitle => 'LINE reminders';

  @override
  String get followUpLineNotLinked => 'Not linked to LINE';

  @override
  String get followUpLineGenerateCode => 'Generate linking code';

  @override
  String followUpLineLinkedSince(String date) {
    return 'Linked to LINE since $date';
  }

  @override
  String get followUpLineUnlink => 'Unlink';

  @override
  String get followUpLineLinkCodeTitle => 'LINE linking code';

  @override
  String get followUpLineLinkCodeInstructions =>
      'Ask the customer to send this code as a message to the business\'s LINE Official Account to receive reminders.';
}
