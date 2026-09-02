// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Lao (`lo`).
class AppLocalizationsLo extends AppLocalizations {
  AppLocalizationsLo([String locale = 'lo']) : super(locale);

  @override
  String get appTitle => 'Beauty Clinic POS';

  @override
  String get commonSave => 'ບັນທຶກ';

  @override
  String get commonSaveChanges => 'ບັນທຶກການປ່ຽນແປງ';

  @override
  String get commonCancel => 'ຍົກເລີກ';

  @override
  String get commonDelete => 'ລຶບ';

  @override
  String get commonEdit => 'ແກ້ໄຂ';

  @override
  String get commonAdd => 'ເພີ່ມ';

  @override
  String get commonSearch => 'ຄົ້ນຫາ';

  @override
  String get commonRequired => 'ຈຳເປັນຕ້ອງໃສ່';

  @override
  String get commonOptional => 'ບໍ່ບັງຄັບ';

  @override
  String get commonNotSpecified => 'ບໍ່ໄດ້ລະບຸ';

  @override
  String get commonNoPhoneOnFile => 'ບໍ່ມີເບີໂທ';

  @override
  String get commonCashier => 'ພະນັກງານແຄຊເຊຍ';

  @override
  String get commonChoose => 'ເລືອກ';

  @override
  String get authLoginTagline => 'ເຂົ້າສູ່ລະບົບທຸລະກິດຂອງທ່ານ';

  @override
  String get authEmailLabel => 'ອີເມວ';

  @override
  String get authEmailInvalid => 'ກະລຸນາໃສ່ອີເມວທີ່ຖືກຕ້ອງ';

  @override
  String get authPasswordLabel => 'ລະຫັດຜ່ານ';

  @override
  String get authPasswordRequired => 'ກະລຸນາໃສ່ລະຫັດຜ່ານ';

  @override
  String get authForgotPassword => 'ລືມລະຫັດຜ່ານ?';

  @override
  String get authSignIn => 'ເຂົ້າສູ່ລະບົບ';

  @override
  String get authNoAccountYet => 'ຍັງບໍ່ມີບັນຊີທຸລະກິດ?';

  @override
  String get authCreateOne => 'ສ້າງບັນຊີໃໝ່';

  @override
  String get authCheckYourEmail => 'ກວດເບິ່ງອີເມວຂອງທ່ານ';

  @override
  String authResetLinkSentTo(String email) {
    return 'ຖ້າມີບັນຊີສຳລັບ $email, ລິ້ງຕັ້ງລະຫັດຜ່ານໃໝ່ໄດ້ຖືກສົ່ງໄປແລ້ວ.';
  }

  @override
  String get authResetPasswordTitle => 'ຕັ້ງລະຫັດຜ່ານໃໝ່';

  @override
  String get authResetPasswordSubtitle =>
      'ພວກເຮົາຈະສົ່ງລິ້ງຕັ້ງລະຫັດຜ່ານໃໝ່ໄປໃຫ້ທ່ານທາງອີເມວ.';

  @override
  String get authSendResetLink => 'ສົ່ງລິ້ງຕັ້ງລະຫັດຜ່ານໃໝ່';

  @override
  String authConfirmationSentTo(String email) {
    return 'ພວກເຮົາໄດ້ສົ່ງລິ້ງຢືນຢັນໄປທີ່ $email ແລ້ວ. ກະລຸນາຢືນຢັນອີເມວ ແລ້ວເຂົ້າສູ່ລະບົບ.';
  }

  @override
  String get authBackToSignIn => 'ກັບໄປໜ້າເຂົ້າສູ່ລະບົບ';

  @override
  String get authCreateAccountTitle => 'ສ້າງບັນຊີຂອງທ່ານ';

  @override
  String get authCreateAccountSubtitle =>
      'ຂັ້ນຕໍ່ໄປ ທ່ານຈະຕັ້ງຄ່າທຸລະກິດຂອງທ່ານ.';

  @override
  String get authFullNameLabel => 'ຊື່ ແລະ ນາມສະກຸນ';

  @override
  String get authNameRequired => 'ກະລຸນາໃສ່ຊື່ຂອງທ່ານ';

  @override
  String get authPasswordTooShortValidation => 'ໃຊ້ຢ່າງໜ້ອຍ 6 ໂຕອັກສອນ';

  @override
  String get authCreateAccount => 'ສ້າງບັນຊີ';

  @override
  String get authSignOut => 'ອອກຈາກລະບົບ';

  @override
  String get authSetUpBusinessTitle => 'ຕັ້ງຄ່າທຸລະກິດຂອງທ່ານ';

  @override
  String get authSetUpBusinessSubtitle =>
      'ນີ້ຈະສ້າງພື້ນທີ່ເຮັດວຽກໃຫ້ຄລີນິກຂອງທ່ານ. ທ່ານຈະເປັນເຈົ້າຂອງ.';

  @override
  String get authBusinessNameLabel => 'ຊື່ທຸລະກິດ';

  @override
  String get authBusinessNameRequired => 'ກະລຸນາໃສ່ຊື່ທຸລະກິດ';

  @override
  String get authPhoneOptionalLabel => 'ເບີໂທ (ບໍ່ບັງຄັບ)';

  @override
  String get authCreateBusiness => 'ສ້າງທຸລະກິດ';

  @override
  String get errorIncorrectCredentials => 'ອີເມວ ຫຼື ລະຫັດຜ່ານບໍ່ຖືກຕ້ອງ.';

  @override
  String get errorEmailNotConfirmed =>
      'ກະລຸນາຢືນຢັນອີເມວຂອງທ່ານກ່ອນເຂົ້າສູ່ລະບົບ.';

  @override
  String get errorUserAlreadyRegistered => 'ມີບັນຊີທີ່ໃຊ້ອີເມວນີ້ຢູ່ແລ້ວ.';

  @override
  String get errorPasswordTooShort =>
      'ລະຫັດຜ່ານສັ້ນເກີນໄປ. ໃຊ້ຢ່າງໜ້ອຍ 6 ໂຕອັກສອນ.';

  @override
  String get errorAuthGeneric => 'ເຂົ້າສູ່ລະບົບບໍ່ສຳເລັດ. ກະລຸນາລອງໃໝ່ອີກຄັ້ງ.';

  @override
  String get errorRecordExists => 'ຂໍ້ມູນນີ້ມີຢູ່ແລ້ວ.';

  @override
  String get errorNoPermission => 'ທ່ານບໍ່ມີສິດເຮັດລາຍການນີ້.';

  @override
  String get errorSaveGeneric => 'ບັນທຶກຂໍ້ມູນບໍ່ສຳເລັດ. ກະລຸນາລອງໃໝ່ອີກຄັ້ງ.';

  @override
  String get errorGeneric =>
      'ມີບາງຢ່າງຜິດພາດ. ກະລຸນາກວດສອບການເຊື່ອມຕໍ່ອິນເຕີເນັດ ແລ້ວລອງໃໝ່ອີກຄັ້ງ.';

  @override
  String get posWalkInCustomer => 'ລູກຄ້າທົ່ວໄປ';

  @override
  String get posCartEmptyTitle => 'ກະຕ່າສິນຄ້າວ່າງເປົ່າ';

  @override
  String get posCartEmptySubtitle =>
      'ແຕະທີ່ບໍລິການ ຫຼື ສິນຄ້າເພື່ອເພີ່ມເຂົ້າກະຕ່າ';

  @override
  String get posSubtotal => 'ລວມຍ່ອຍ';

  @override
  String get posDiscount => 'ສ່ວນຫຼຸດ';

  @override
  String get posTax => 'ພາສີ';

  @override
  String get posTotal => 'ລວມທັງໝົດ';

  @override
  String get posChange => 'ເງິນທອນ';

  @override
  String get posCompleteSale => 'ຢືນຢັນການຂາຍ';

  @override
  String get posRemoveTooltip => 'ລຶບອອກ';

  @override
  String get posStaffForCommission => 'ພະນັກງານ (ສຳລັບຄ່າຄອມມິຊຊັນ)';

  @override
  String get posUnassigned => 'ຍັງບໍ່ໄດ້ມອບໝາຍ';

  @override
  String get posPaymentMethod => 'ວິທີຊຳລະເງິນ';

  @override
  String get posAmountPaidLak => 'ຈຳນວນເງິນທີ່ຮັບ (ກີບ)';

  @override
  String get posPaymentInsufficient =>
      'ຈຳນວນເງິນທີ່ຮັບຕ້ອງບໍ່ໜ້ອຍກວ່າຍອດລວມການຂາຍ.';

  @override
  String get paymentMethodCash => 'ເງິນສົດ';

  @override
  String get paymentMethodBankTransfer => 'ໂອນຜ່ານທະນາຄານ';

  @override
  String get paymentMethodCard => 'ບັດ';

  @override
  String get paymentMethodOther => 'ອື່ນໆ';

  @override
  String get salesStatusVoided => 'ຍົກເລີກແລ້ວ';

  @override
  String get salesStatusRefunded => 'ຄືນເງິນແລ້ວ';

  @override
  String get salesStatusCompleted => 'ສຳເລັດແລ້ວ';

  @override
  String get salesVoidConfirmTitle => 'ຍົກເລີກການຂາຍນີ້ບໍ?';

  @override
  String get salesVoidConfirmBody =>
      'ການເຮັດແບບນີ້ຈະຄືນສະຕັອກສິນຄ້າ ແລະ ຄ່າຄອມມິຊຊັນຂອງການຂາຍນີ້ ພ້ອມທັງໝາຍການຊຳລະເງິນວ່າຄືນເງິນແລ້ວ. ບໍ່ສາມາດແກ້ຄືນໄດ້.';

  @override
  String get salesVoidReasonLabel => 'ເຫດຜົນ';

  @override
  String get salesVoidReasonHint => 'ເປັນຫຍັງຈຶ່ງຍົກເລີກການຂາຍນີ້?';

  @override
  String get salesVoidAction => 'ຍົກເລີກການຂາຍ';

  @override
  String get salesVoiding => 'ກຳລັງຍົກເລີກ…';

  @override
  String get salesVoidedSnackbar => 'ຍົກເລີກການຂາຍແລ້ວ.';

  @override
  String get salesDetailFallbackTitle => 'ການຂາຍ';

  @override
  String get salesVoidDetailsTitle => 'ລາຍລະອຽດການຍົກເລີກ';

  @override
  String get salesRowPaid => 'ຮັບເງິນແລ້ວ';

  @override
  String get customersFallbackTitle => 'ລູກຄ້າ';

  @override
  String get customersTotalSpent => 'ຍອດຊື້ທັງໝົດ';

  @override
  String get customersVisits => 'ຈຳນວນຄັ້ງທີ່ມາ';

  @override
  String get customersLastVisit => 'ມາຄັ້ງລ່າສຸດ';

  @override
  String get customersPurchaseHistory => 'ປະຫວັດການຊື້';

  @override
  String get customersNotes => 'ບັນທຶກ';

  @override
  String get customersNoSalesYet => 'ຍັງບໍ່ມີການຊື້.';

  @override
  String get customersNoNotesYet => 'ຍັງບໍ່ມີບັນທຶກ.';

  @override
  String get customersAddNoteHint => 'ເພີ່ມບັນທຶກ...';

  @override
  String get customersNameLabel => 'ຊື່';

  @override
  String get customersGenderOptionalLabel => 'ເພດ (ບໍ່ບັງຄັບ)';

  @override
  String get customersGenderMale => 'ຊາຍ';

  @override
  String get customersGenderFemale => 'ຍິງ';

  @override
  String get customersGenderOther => 'ອື່ນໆ';

  @override
  String get customersNotesOptionalLabel => 'ບັນທຶກ (ບໍ່ບັງຄັບ)';

  @override
  String get customersEditTitle => 'ແກ້ໄຂລູກຄ້າ';

  @override
  String get customersAddTitle => 'ເພີ່ມລູກຄ້າ';

  @override
  String get customersSearchHint => 'ຄົ້ນຫາຕາມຊື່ ຫຼື ເບີໂທ';

  @override
  String get customersEmptyTitle => 'ຍັງບໍ່ມີລູກຄ້າ';

  @override
  String get customersEmptySubtitle =>
      'ເພີ່ມລູກຄ້າຄົນທຳອິດຂອງທ່ານ, ຫຼືຈະຖືກສ້າງອັດຕະໂນມັດຕອນຊຳລະເງິນ.';

  @override
  String customersVisitsCount(int count) {
    return '$count ຄັ້ງ';
  }

  @override
  String get posReceiptSaleComplete => 'ການຂາຍສຳເລັດ';

  @override
  String get posReceiptReceipt => 'ໃບບິນ';

  @override
  String get posReceiptDate => 'ວັນທີ';

  @override
  String get posReceiptCashier => 'ພະນັກງານແຄຊເຊຍ';

  @override
  String get posReceiptCustomer => 'ລູກຄ້າ';

  @override
  String get posReceiptWalkIn => 'ລູກຄ້າທົ່ວໄປ';

  @override
  String posReceiptPaidVia(String method) {
    return 'ຊຳລະ ($method)';
  }

  @override
  String get posReceiptThankYou => 'ຂອບໃຈ!';

  @override
  String get posReceiptNewSale => 'ການຂາຍໃໝ່';

  @override
  String posCartItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ລາຍການ',
    );
    return '$_temp0';
  }

  @override
  String get posSelectCustomer => 'ເລືອກລູກຄ້າ';

  @override
  String get posSearchNameOrPhone => 'ຄົ້ນຫາຊື່ ຫຼື ເບີໂທ';

  @override
  String get posNoCustomersFound => 'ບໍ່ພົບລູກຄ້າ';

  @override
  String posCreateAsNewCustomer(String query) {
    return 'ສ້າງ \"$query\" ເປັນລູກຄ້າໃໝ່';
  }

  @override
  String get posSearchServicesOrProducts => 'ຄົ້ນຫາບໍລິການ ຫຼື ສິນຄ້າ';

  @override
  String get posServicesTab => 'ບໍລິການ';

  @override
  String get posProductsTab => 'ສິນຄ້າ';

  @override
  String get posNoServicesYet => 'ຍັງບໍ່ມີບໍລິການ';

  @override
  String get posNoProductsYet => 'ຍັງບໍ່ມີສິນຄ້າ';

  @override
  String get posNoMatches => 'ບໍ່ພົບຂໍ້ມູນທີ່ກົງກັນ';

  @override
  String get posOutOfStock => 'ສິນຄ້າໝົດ';

  @override
  String posItemsLeft(String price, int count) {
    return '$price · ເຫຼືອ $count';
  }

  @override
  String get salesSearchByReceiptHint => 'ຄົ້ນຫາຕາມເລກທີ່ໃບບິນ';

  @override
  String get salesNoSalesFound => 'ບໍ່ພົບການຂາຍ.';

  @override
  String get roleOwner => 'ເຈົ້າຂອງ';

  @override
  String get roleAdmin => 'ຜູ້ບໍລິຫານ';

  @override
  String get roleManager => 'ຜູ້ຈັດການ';

  @override
  String get roleCashier => 'ພະນັກງານແຄຊເຊຍ';

  @override
  String get roleStaff => 'ພະນັກງານ';

  @override
  String get movementTypePurchase => 'ຮັບເຂົ້າ (ຊື້ເຂົ້າ)';

  @override
  String get movementTypeSale => 'ຂາຍອອກ';

  @override
  String get movementTypeReturn => 'ສົ່ງຄືນ';

  @override
  String get movementTypeAdjustment => 'ປັບປຸງຍອດ';

  @override
  String get movementTypeDamage => 'ເສຍຫາຍ';

  @override
  String get movementTypeExpired => 'ໝົດອາຍຸ';

  @override
  String get staffInviteButton => 'ເຊີນ';

  @override
  String get staffEmptyState => 'ຍັງບໍ່ມີພະນັກງານ.';

  @override
  String staffRoleInactiveSuffix(String role) {
    return '$role · ປິດການໃຊ້ງານ';
  }

  @override
  String get staffChangeRole => 'ປ່ຽນຕຳແໜ່ງ';

  @override
  String get staffDeactivate => 'ປິດການໃຊ້ງານ';

  @override
  String get staffReactivate => 'ເປີດການໃຊ້ງານຄືນ';

  @override
  String get staffInviteTitle => 'ເຊີນພະນັກງານ';

  @override
  String get staffInviteSubtitle => 'ຕ້ອງມີບັນຊີຢູ່ແລ້ວ. ໃສ່ອີເມວເພື່ອຄົ້ນຫາ.';

  @override
  String get staffFind => 'ຄົ້ນຫາ';

  @override
  String get staffNoAccountFound =>
      'ບໍ່ພົບບັນຊີທີ່ໃຊ້ອີເມວນີ້. ຕ້ອງໃຫ້ພະນັກງານສ້າງບັນຊີກ່ອນ.';

  @override
  String get staffAccountFound => 'ພົບບັນຊີແລ້ວ';

  @override
  String get staffRoleLabel => 'ຕຳແໜ່ງ';

  @override
  String get staffInviteAction => 'ເຊີນ';

  @override
  String get invTabStock => 'ສະຕັອກ';

  @override
  String get invTabMovements => 'ການເຄື່ອນໄຫວ';

  @override
  String get invTabSuppliers => 'ຜູ້ສະໜອງ';

  @override
  String get invNoProductsYetTitle => 'ຍັງບໍ່ມີສິນຄ້າ';

  @override
  String get invNoProductsYetSubtitle =>
      'ເພີ່ມສິນຄ້າໃນແຖບສິນຄ້າເພື່ອເລີ່ມຕິດຕາມສະຕັອກ.';

  @override
  String invLowStockWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ມີ $count ລາຍການສິນຄ້າໃກ້ໝົດ ຫຼື ໝົດແລ້ວ.',
    );
    return '$_temp0';
  }

  @override
  String invLowStockAlertAt(int threshold) {
    return 'ແຈ້ງເຕືອນສິນຄ້າໃກ້ໝົດຢູ່ທີ່ $threshold';
  }

  @override
  String invInStock(int count) {
    return 'ມີໃນສະຕັອກ $count';
  }

  @override
  String get invAdjustStockTooltip => 'ປັບຍອດສະຕັອກ';

  @override
  String get invNoMovementsYet =>
      'ຍັງບໍ່ມີການເຄື່ອນໄຫວສະຕັອກ. ການຂາຍ ແລະ ການປັບຍອດດ້ວຍມືຈະສະແດງຢູ່ນີ້.';

  @override
  String get invUnknownProduct => 'ບໍ່ຮູ້ຈັກສິນຄ້າ';

  @override
  String get invAddSupplier => 'ເພີ່ມຜູ້ສະໜອງ';

  @override
  String get invEditSupplier => 'ແກ້ໄຂຜູ້ສະໜອງ';

  @override
  String get invNoSuppliersYetTitle => 'ຍັງບໍ່ມີຜູ້ສະໜອງ';

  @override
  String get invNoSuppliersYetSubtitle =>
      'ຕິດຕາມແຫຼ່ງທີ່ທ່ານສັ່ງຊື້ສິນຄ້າມາເຕີມ.';

  @override
  String get invNoContactInfo => 'ບໍ່ມີຂໍ້ມູນຕິດຕໍ່';

  @override
  String get invInactive => 'ປິດການໃຊ້ງານ';

  @override
  String get invAdjustStockTitle => 'ປັບຍອດສະຕັອກ';

  @override
  String invAdjustStockSubtitle(String name, int count) {
    return '$name · ປັດຈຸບັນມີ $count ໃນສະຕັອກ';
  }

  @override
  String get invAddStockSegment => 'ເພີ່ມສະຕັອກ';

  @override
  String get invRemoveStockSegment => 'ຫຼຸດສະຕັອກ';

  @override
  String get invQuantityLabel => 'ຈຳນວນ';

  @override
  String get invQuantityPositiveRequired => 'ກະລຸນາໃສ່ຈຳນວນເຕັມທີ່ຫຼາຍກວ່າສູນ';

  @override
  String get invReasonLabel => 'ເຫດຜົນ';

  @override
  String get invNoteOptionalLabel => 'ໝາຍເຫດ (ບໍ່ບັງຄັບ)';

  @override
  String get invSaveAdjustment => 'ບັນທຶກການປັບຍອດ';

  @override
  String get supplierNameLabel => 'ຊື່ຜູ້ສະໜອງ';

  @override
  String get commonActive => 'ເປີດໃຊ້ງານ';

  @override
  String get customersEmailOptionalLabel => 'ອີເມວ (ບໍ່ບັງຄັບ)';

  @override
  String get customersAddressOptionalLabel => 'ທີ່ຢູ່ (ບໍ່ບັງຄັບ)';

  @override
  String get expensesEditTitle => 'ແກ້ໄຂລາຍຈ່າຍ';

  @override
  String get expensesAddTitle => 'ເພີ່ມລາຍຈ່າຍ';

  @override
  String get expensesAmountLak => 'ຈຳນວນເງິນ (ກີບ)';

  @override
  String get expensesPositiveAmountRequired =>
      'ກະລຸນາໃສ່ຈຳນວນເງິນທີ່ຫຼາຍກວ່າສູນ';

  @override
  String get expensesCategoryOptionalLabel => 'ໝວດໝູ່ (ບໍ່ບັງຄັບ)';

  @override
  String get expensesNoCategory => 'ບໍ່ມີໝວດໝູ່';

  @override
  String get expensesDateLabel => 'ວັນທີ';

  @override
  String get expensesDescriptionOptionalLabel => 'ລາຍລະອຽດ (ບໍ່ບັງຄັບ)';

  @override
  String get expensesManageCategoriesTooltip => 'ຈັດການໝວດໝູ່';

  @override
  String get expensesAllCategories => 'ທຸກໝວດໝູ່';

  @override
  String get expensesNoExpensesTitle => 'ຍັງບໍ່ມີລາຍຈ່າຍທີ່ບັນທຶກໄວ້';

  @override
  String get expensesNoExpensesSubtitle =>
      'ບັນທຶກຄ່າເຊົ່າ, ຄ່າໄຟຟ້າ, ຄ່ານໍ້າ, ແລະ ຄ່າໃຊ້ຈ່າຍທຸລະກິດອື່ນໆທີ່ນີ້.';

  @override
  String get expensesTotalLabel => 'ລວມ: ';

  @override
  String get expensesUncategorized => 'ບໍ່ມີໝວດໝູ່';

  @override
  String get expensesDeleteTitle => 'ລຶບລາຍຈ່າຍນີ້ບໍ?';

  @override
  String get expensesDeleteBody => 'ບໍ່ສາມາດແກ້ຄືນໄດ້.';

  @override
  String get expenseCategoriesTitle => 'ໝວດໝູ່ລາຍຈ່າຍ';

  @override
  String get expenseNewCategoryNameLabel => 'ຊື່ໝວດໝູ່ໃໝ່';

  @override
  String get expenseNoCategoriesYet => 'ຍັງບໍ່ມີໝວດໝູ່.';

  @override
  String get categoryLabel => 'ໝວດໝູ່';

  @override
  String get navOverview => 'ພາບລວມ';

  @override
  String get navPos => 'ຂາຍໜ້າຮ້ານ';

  @override
  String get navSales => 'ການຂາຍ';

  @override
  String get navCustomers => 'ລູກຄ້າ';

  @override
  String get navAppointments => 'ນັດໝາຍ';

  @override
  String get navServices => 'ບໍລິການ';

  @override
  String get navProducts => 'ສິນຄ້າ';

  @override
  String get navInventory => 'ສາງສິນຄ້າ';

  @override
  String get navStaff => 'ພະນັກງານ';

  @override
  String get navCommissions => 'ຄ່າຄອມມິຊຊັນ';

  @override
  String get navExpenses => 'ລາຍຈ່າຍ';

  @override
  String get navReports => 'ລາຍງານ';

  @override
  String get navAuditLog => 'ບັນທຶກການເຄື່ອນໄຫວ';

  @override
  String get navSettings => 'ການຕັ້ງຄ່າ';

  @override
  String get navSoon => 'ໄວໆນີ້';

  @override
  String navNotBuiltYet(String label) {
    return '$label ຍັງບໍ່ໄດ້ສ້າງ';
  }

  @override
  String get navScheduledLater => 'ພາກສ່ວນນີ້ຖືກກຳນົດໄວ້ໃນແຜນພັດທະນາຕໍ່ໄປ.';

  @override
  String get overviewIntro =>
      'ທ່ານໄດ້ເຂົ້າສູ່ລະບົບ ແລະ ພື້ນທີ່ເຮັດວຽກຂອງທຸລະກິດຖືກຕັ້ງຄ່າແລ້ວ. ຂາຍໜ້າຮ້ານ, ລູກຄ້າ, ສາງສິນຄ້າ, ແລະ ລາຍງານຈະເປີດໃຊ້ງານໄດ້ຕາມແຕ່ລະສ່ວນຂອງການພັດທະນາ.';

  @override
  String get commonRetry => 'ລອງໃໝ່';

  @override
  String get reportsTodayTagline => 'ພາບລວມທຸລະກິດວັນນີ້.';

  @override
  String get reportsTodaySales => 'ຍອດຂາຍວັນນີ້';

  @override
  String reportsSalesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ລາຍການຂາຍ',
    );
    return '$_temp0';
  }

  @override
  String get reportsCommission => 'ຄ່າຄອມມິຊຊັນ';

  @override
  String get reportsExpenses => 'ລາຍຈ່າຍ';

  @override
  String get reportsEstimatedProfit => 'ກຳໄລໂດຍປະມານ';

  @override
  String get reportsRevenue => 'ລາຍຮັບ';

  @override
  String get reportsCogs => 'ຕົ້ນທຶນສິນຄ້າທີ່ຂາຍໄດ້';

  @override
  String get reportsExportCsv => 'ສົ່ງອອກ CSV';

  @override
  String get reportsCopiedToClipboard =>
      'ສຳເນົາລາຍງານເປັນ CSV ໄປໃສ່ຄລິບບອດແລ້ວ.';

  @override
  String get reportsRevenueByDay => 'ລາຍຮັບຕໍ່ວັນ';

  @override
  String get reportsSalesInRange => 'ການຂາຍໃນຊ່ວງເວລານີ້';

  @override
  String get reportsNoSalesInRange => 'ຍັງບໍ່ມີການຂາຍໃນຊ່ວງເວລານີ້.';

  @override
  String get reportsColReceipt => 'ໃບບິນ';

  @override
  String get reportsColDate => 'ວັນທີ';

  @override
  String get reportsColStatus => 'ສະຖານະ';

  @override
  String get reportsColAmount => 'ຈຳນວນເງິນ';

  @override
  String get reportsCsvPaymentStatus => 'ສະຖານະການຊຳລະ';

  @override
  String get auditActionLabel => 'ການກະທຳ';

  @override
  String get auditAllActions => 'ທຸກການກະທຳ';

  @override
  String get auditEntityLabel => 'ປະເພດຂໍ້ມູນ';

  @override
  String get auditAllEntities => 'ທຸກປະເພດຂໍ້ມູນ';

  @override
  String get auditEmptyState => 'ບໍ່ພົບເຫດການສຳລັບການກັ່ນຕອງນີ້.';

  @override
  String get auditSystemActor => 'ລະບົບ';

  @override
  String get auditBefore => 'ກ່ອນ';

  @override
  String get auditAfter => 'ຫຼັງ';

  @override
  String get auditDetails => 'ລາຍລະອຽດ';

  @override
  String get commissionKindPercentage => 'ເປີເຊັນ';

  @override
  String get commissionKindFixed => 'ຈຳນວນຄົງທີ່';

  @override
  String get commissionStatusPending => 'ລໍຖ້າ';

  @override
  String get commissionStatusApproved => 'ອະນຸມັດແລ້ວ';

  @override
  String get commissionStatusReversed => 'ຍົກເລີກແລ້ວ';

  @override
  String get commissionStatusPaid => 'ຈ່າຍແລ້ວ';

  @override
  String get productsAddTitle => 'ເພີ່ມສິນຄ້າ';

  @override
  String get productsEditTitle => 'ແກ້ໄຂສິນຄ້າ';

  @override
  String get productsEmptyTitle => 'ຍັງບໍ່ມີສິນຄ້າ';

  @override
  String get productsEmptySubtitle =>
      'ເພີ່ມສິນຄ້າຂາຍປີກເພື່ອຂາຍຄຽງຄູ່ກັບບໍລິການ.';

  @override
  String productsSkuPrefix(String sku) {
    return 'SKU $sku';
  }

  @override
  String get productNameLabel => 'ຊື່ສິນຄ້າ';

  @override
  String get productSkuOptionalLabel => 'SKU (ບໍ່ບັງຄັບ)';

  @override
  String get productSellingPriceLak => 'ລາຄາຂາຍ (ກີບ)';

  @override
  String get productCostPriceLak => 'ລາຄາຕົ້ນທຶນ (ກີບ)';

  @override
  String get productStockQuantityLabel => 'ຈຳນວນສະຕັອກ';

  @override
  String get productLowStockAlertAtLabel => 'ແຈ້ງເຕືອນສິນຄ້າໃກ້ໝົດຢູ່ທີ່';

  @override
  String get commonInvalid => 'ບໍ່ຖືກຕ້ອງ';

  @override
  String get servicesAddTitle => 'ເພີ່ມບໍລິການ';

  @override
  String get servicesEditTitle => 'ແກ້ໄຂບໍລິການ';

  @override
  String get servicesEmptyTitle => 'ຍັງບໍ່ມີບໍລິການ';

  @override
  String get servicesEmptySubtitle =>
      'ເພີ່ມບໍລິການທຳອິດຂອງທ່ານເພື່ອເລີ່ມຮັບການຈອງ ແລະ ການຂາຍ.';

  @override
  String servicesDurationCommission(
    int minutes,
    String label,
    String value,
    String percentSuffix,
  ) {
    return '$minutes ນາທີ · ຄ່າຄອມ $label $value$percentSuffix';
  }

  @override
  String get serviceNameLabel => 'ຊື່ບໍລິການ';

  @override
  String get serviceDescriptionOptionalLabel => 'ລາຍລະອຽດ (ບໍ່ບັງຄັບ)';

  @override
  String get servicePriceLak => 'ລາຄາ (ກີບ)';

  @override
  String get servicePriceInvalid => 'ກະລຸນາໃສ່ລາຄາທີ່ຖືກຕ້ອງ';

  @override
  String get serviceDurationMinLabel => 'ໄລຍະເວລາ (ນາທີ)';

  @override
  String get serviceCommissionTypeLabel => 'ປະເພດຄ່າຄອມມິຊຊັນ';

  @override
  String get serviceCommissionPercentLabel => 'ຄ່າຄອມ %';

  @override
  String get serviceCommissionLakLabel => 'ຄ່າຄອມ (ກີບ)';

  @override
  String get commissionsStaffLabel => 'ພະນັກງານ';

  @override
  String get commissionsAllStaff => 'ພະນັກງານທັງໝົດ';

  @override
  String get commissionsStatusLabel => 'ສະຖານະ';

  @override
  String get commissionsAllStatuses => 'ທຸກສະຖານະ';

  @override
  String get commissionsNoneFound => 'ບໍ່ພົບຄ່າຄອມມິຊຊັນ.';

  @override
  String get commissionsUnknownStaff => 'ບໍ່ຮູ້ຈັກພະນັກງານ';

  @override
  String commissionsMarkAs(String status) {
    return 'ໝາຍເປັນ $status';
  }

  @override
  String get settingsTitle => 'ການຕັ້ງຄ່າທຸລະກິດ';

  @override
  String get settingsReadOnlyNotice =>
      'ທ່ານມີສິດເບິ່ງໄດ້ຢ່າງດຽວ. ກະລຸນາຕິດຕໍ່ຜູ້ບໍລິຫານ ຫຼື ເຈົ້າຂອງເພື່ອແກ້ໄຂ.';

  @override
  String get settingsBusinessNameLabel => 'ຊື່ທຸລະກິດ';

  @override
  String get settingsCurrencyCodeLabel => 'ລະຫັດສະກຸນເງິນ (ເຊັ່ນ LAK)';

  @override
  String get settingsCurrencyCodeInvalid =>
      'ກະລຸນາໃສ່ລະຫັດສະກຸນເງິນ 3 ໂຕອັກສອນ';

  @override
  String get settingsTaxEnabled => 'ເປີດໃຊ້ພາສີ';

  @override
  String get settingsTaxRateLabel => 'ອັດຕາພາສີ (%)';

  @override
  String get settingsTaxRateInvalidNumber => 'ກະລຸນາໃສ່ຕົວເລກ';

  @override
  String get settingsTaxRateRange => 'ຕ້ອງຢູ່ລະຫວ່າງ 0 ຫາ 100';

  @override
  String get settingsLogoUrlOptionalLabel => 'URL ໂລໂກ້ (ບໍ່ບັງຄັບ)';

  @override
  String get settingsSaved => 'ບັນທຶກການຕັ້ງຄ່າແລ້ວ.';

  @override
  String get settingsLanguageTitle => 'ພາສາ';

  @override
  String get settingsLanguageSubtitle => 'ເລືອກພາສາສະແດງຜົນຂອງແອັບ.';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageLao => 'ລາວ';

  @override
  String get dateRangeToday => 'ມື້ນີ້';

  @override
  String get dateRangeThisWeek => 'ອາທິດນີ້';

  @override
  String get dateRangeThisMonth => 'ເດືອນນີ້';

  @override
  String get dateRangeCustom => 'ກຳນົດເອງ';

  @override
  String get apptBookTitle => 'ນັດໝາຍໃໝ່';

  @override
  String get apptWalkIn => 'ລູກຄ້າຍ່າງເຂົ້າ';

  @override
  String get apptCustomerOptional => 'ລູກຄ້າ (ບໍ່ບັງຄັບ)';

  @override
  String get apptStaffLabel => 'ພະນັກງານ';

  @override
  String get apptServicesLabel => 'ບໍລິການ';

  @override
  String get apptSelectAtLeastOneService => 'ກະລຸນາເລືອກຢ່າງໜ້ອຍໜຶ່ງບໍລິການ';

  @override
  String get apptNotesOptionalLabel => 'ໝາຍເຫດ (ບໍ່ບັງຄັບ)';

  @override
  String get apptCalendarMonth => 'ເດືອນ';

  @override
  String get apptCalendarWeek => 'ອາທິດ';

  @override
  String get apptNoAppointmentsThisDay => 'ບໍ່ມີນັດໝາຍໃນມື້ນີ້';

  @override
  String get apptStatusScheduled => 'ກຳນົດແລ້ວ';

  @override
  String get apptStatusConfirmed => 'ຢືນຢັນແລ້ວ';

  @override
  String get apptStatusCheckedIn => 'ເຊັກອິນແລ້ວ';

  @override
  String get apptStatusCompleted => 'ສຳເລັດແລ້ວ';

  @override
  String get apptStatusCancelled => 'ຍົກເລີກແລ້ວ';

  @override
  String get apptStatusNoShow => 'ບໍ່ມາຕາມນັດ';

  @override
  String get apptCancelReasonTitle => 'ຍົກເລີກນັດໝາຍ';

  @override
  String get apptCancelReasonOptionalHint => 'ເຫດຜົນ (ບໍ່ບັງຄັບ)';

  @override
  String get apptReschedule => 'ປ່ຽນເວລານັດ';

  @override
  String get apptRescheduleConfirm => 'ຢືນຢັນການປ່ຽນເວລາ';
}
