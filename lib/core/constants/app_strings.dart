class AppStrings {
  AppStrings._();

  // ── App ───────────────────────────────────────────────────────────────────
  static const String appName       = 'TapGuard';
  static const String appTagline    = 'Safety at your fingertips';
  static const String appVersion    = 'TapGuard V2.4.1 (Privacy Build)';

  // ── Splash ────────────────────────────────────────────────────────────────
  static const String privacyFocused = 'PRIVACY-FOCUSED SHARING';

  // ── Onboarding ────────────────────────────────────────────────────────────
  static const String onboardingSkip = 'Skip';
  static const String onboarding1Title = 'NFC Pairing';
  static const String onboarding1Body =
      'Securely pair with your trusted contact instantly via NFC. '
      'Just tap your phones together to establish a private, '
      'bi-directional location sharing link.';

  static const String onboarding2Title = 'Bi-directional Sharing';
  static const String onboarding2Body =
      'Keep an eye on each other with real-time, mutual location '
      'updates. Tap your phones to start a secure, two-way safety session.';
  static const String onboarding2Badge = 'END SESSION AT ANY TIME';

  static const String onboarding3Title = 'Privacy First';
  static const String onboarding3Body =
      'You control when and for how long you share. No continuous '
      'tracking, no hidden data collection. Safety on your terms.';
  static const String onboarding3Feature1 = 'Auto-expires after sharing period';
  static const String onboarding3Feature2 = 'NFC-enabled bi-directional link';

  static const String startPairing   = 'Start Pairing';
  static const String continueBtn    = 'Continue';
  static const String skipForNow     = 'Skip for now';
  static const String howDoesItWork  = 'How does it work?';
  static const String getStarted     = 'Get Started';
  static const String endToEndEncrypted = 'END-TO-END ENCRYPTED';

  // ── Auth ──────────────────────────────────────────────────────────────────
  static const String welcomeTitle   = 'Welcome to TapGuard';
  static const String welcomeBody    =
      'Your safety is our priority. Enter your email to get started.';
  static const String emailAddress   = 'Email Address';
  static const String emailPlaceholder = 'you@gmail.com';
  static const String enterEmailBody =
      'Enter your email address and we\'ll send a verification code instantly.';
  static const String phoneNumber    = 'Phone Number';
  static const String phonePlaceholder = '+1 000-000-0000';
  static const String sendOtp        = 'Send OTP';
  static const String nfcEnabledPrivacy = 'NFC ENABLED PRIVACY';
  static const String privacyPolicy  = 'Privacy Policy';
  static const String termsOfService = 'Terms of Service';
  static const String locationEncrypted =
      'Your location data is encrypted and only shared with your trusted contacts during active sessions.';

  static const String verifyOtp      = 'Verify OTP';
  static const String otpSentTo      = 'Code sent to ';
  static const String resendOtp      = 'Resend OTP';
  static const String verifyBtn      = 'Verify & Continue';
  static const String verifyEmailBody = 'We sent a 6-digit code to';

  static const String setupProfile   = 'Setup Your Profile';
  static const String setupProfileBody =
      'This helps your trusted contacts identify you instantly.';
  static const String yourName       = 'Your Name';
  static const String yourNameHint   = 'e.g. Sarah Jenkins';
  static const String signedInAs     = 'Signed in as';
  static const String phoneLaterHint =
      'You can add your phone number later from your profile '
      '(required for SOS SMS alerts).';
  static const String saveProfile    = 'Save & Continue';

  // ── Account / Profile (in-app) ───────────────────────────────────────────
  static const String account        = 'Account';
  static const String editProfile    = 'Edit Profile';
  static const String saveChanges    = 'Save Changes';
  static const String accountSection = 'ACCOUNT';
  static const String appSection     = 'APP';
  static const String logoutConfirmTitle = 'Log out?';
  static const String logoutConfirmBody =
      'You will need to verify your email again to sign back in.';
  static const String addContact     = 'Add Trusted Contact';
  static const String contactName    = 'Full Name';
  static const String contactEmail   = 'Email';
  static const String contactPhone   = 'Phone (for SOS SMS)';
  static const String primaryContact = 'Primary Emergency Contact';
  static const String notifyFirst    =
      'Notify this contact first in emergencies';
  static const String priorityLevel  = 'Priority Level';
  static const String priorityHint   =
      'Priority 1 is notified first in SOS emergencies';
  static const String priorityHigh   = 'High';
  static const String priorityMedium = 'Medium';
  static const String priorityLow    = 'Low';
  static const String noContactsYet  = 'No Trusted Contacts Yet';
  static const String noContactsBody =
      'Add trusted contacts to enable location\n'
      'sharing and emergency notifications';
  static const String removeContactTitle = 'Remove Contact?';
  static const String removeContactBodyPrefix = 'Are you sure you want to remove';
  static const String removeContactBodySuffix = '?';
  static const String remove         = 'Remove';
  static const String contactRemoved = 'Contact removed successfully';
  static const String contactAdded   = 'added';
  static const String contactSetEmergency = 'is now your primary emergency contact';
  static const String contactUnsetEmergency =
      'is no longer your primary emergency contact';
  static const String profileUpdated = 'Profile updated successfully';
  static const String pleaseEnterName = 'Please enter a name';
  static const String pleaseFillAll  = 'Please fill all fields';
  static const String pleaseEnterEmail = 'Please enter a valid email';
  static const String pleaseEnterPhone = 'Please enter a phone number';
  static const String editContactSoon = 'Edit functionality coming soon';

  // ── Home ──────────────────────────────────────────────────────────────────
  static const String systemReady    = 'SYSTEM READY';
  static const String startNfcPairing = 'Start NFC Pairing';
  static const String holdPhoneNear  =
      'Hold your phone near a trusted friend\'s to instantly share location.';
  static const String tapToPair      = 'Tap to Pair';
  static const String safetyMap      = 'Safety Map';
  static const String liveView       = 'Live view';
  static const String safeTimer      = 'Safe Timer';
  static const String comingHome     = 'Coming home';
  static const String trustedContacts = 'Trusted Contacts';
  static const String seeAll         = 'See All';
  static const String activeNow      = '● Active Now';
  static const String endToEndSharing = 'END-TO-END ENCRYPTED SHARING';

  // ── NFC Pairing ───────────────────────────────────────────────────────────
  static const String connectWithFriend = 'Connect with a Friend';
  static const String bringPhones    = 'Bring phones close to pair';
  static const String bringPhonesBody =
      'To start bi-directional sharing, tap the backs of your phones together.';
  static const String locationEncryptedPrivate = 'Your location is encrypted & private';
  static const String e2eNote =
      'TapGuard uses end-to-end encryption. Only this contact will be able to see your live location during an active session.';
  static const String cancel         = 'Cancel';
  static const String searching      = 'Searching…';
  static const String connected      = 'Connected';
  static const String pairingSuccess = 'Pairing successful';
  static const String startLocationSharing = 'Start Location Sharing?';

  // ── Active Session ────────────────────────────────────────────────────────
  static const String activeSession  = 'Active Session';
  static const String connectedTo    = 'Connected to ';
  static const String remaining      = 'REMAINING';
  static const String liveNfcSharing = 'LIVE NFC SHARING ACTIVE';
  static const String iAmSafe        = 'I am Safe';
  static const String confirmsStatus = 'Confirms status & resets timer';
  static const String endSession     = 'End Session';
  static const String stopSharing    = 'Stop sharing your location';
  static const String locationEncryptedVisible =
      'Your location is currently encrypted and visible only to your trusted contact.';

  // ── Map ───────────────────────────────────────────────────────────────────
  static const String liveTracking   = '● LIVE TRACKING';
  static const String arrivingIn     = 'Arriving in ';
  static const String headingTo      = 'Heading to: ';
  static const String yourDevice     = 'YOUR DEVICE';
  static const String milesLeft      = ' miles left';
  static const String checkIn        = 'Check-in';

  // ── SOS ───────────────────────────────────────────────────────────────────
  static const String sosActive      = 'SOS ACTIVE';
  static const String alertingContacts =
      'Alerting Trusted Contacts & Local Authorities';
  static const String seconds        = 'SECONDS';
  static const String liveLocationSharing = 'Live Location Sharing';
  static const String nfcGpsActive   = 'NFC & GPS active for 5 contacts';
  static const String live           = 'LIVE';
  static const String emergencyDispatch = 'Emergency Dispatch';
  static const String connectingStation = 'Connecting to nearest station...';
  static const String cancelSos      = 'CANCEL SOS';
  static const String holdToCancel   = 'HOLD TO CANCEL IF THIS WAS A MISTAKE';

  // ── Geofence ──────────────────────────────────────────────────────────────
  static const String setupSafeZone  = 'Setup Safe Zone';
  static const String searchAddress  = 'Search for address or place';
  static const String currentSetup   = 'CURRENT SETUP';
  static const String homeSafeZone   = 'Home Safe Zone';
  static const String adjustRadius   = 'Adjust Radius';
  static const String radiusRange    = '100m - 2km';
  static const String notifyEntered  = 'Notify when entered';
  static const String alertArrival   = 'Alert contacts on arrival';
  static const String notifyExited   = 'Notify when exited';
  static const String alertDeparture = 'Alert contacts on departure';
  static const String e2eLocationData = 'END-TO-END ENCRYPTED LOCATION DATA';
  static const String saveSafeZone   = 'Save Safe Zone';

  // ── Profile / Circle ─────────────────────────────────────────────────────
  static const String myCircle       = 'My Circle';
  static const String circleSubtitle = 'Trusted contacts who receive alerts';
  static const String idVerified     = 'ID Verified';
  static const String myQR           = 'My QR';
  static const String manage         = 'Manage';
  static const String pairNfc        = 'Pair NFC';
  static const String resend         = 'Resend';
  static const String invitePending  = 'Invite Pending...';
  static const String addTrustedContact = 'Add Trusted Contact';
  static const String proTip         = 'Pro Tip';
  static const String proTipBody     =
      'Pair contacts via NFC to enable "Instant Check-in" when you\'re near '
      'their device. Tap the back of your phones together.';

  // ── Privacy & Permissions ────────────────────────────────────────────────
  static const String privacyPermissions = 'Privacy & Permissions';
  static const String yourSafetyPrivacy = 'Your Safety, Your Privacy';
  static const String privacyBody    =
      'TapGuard is built with a privacy-first approach. We only access the data necessary to protect you in an emergency.';
  static const String coreSafetyFeatures = 'CORE SAFETY FEATURES';
  static const String shakeDetection = 'Shake Detection';
  static const String shakeBody      =
      'Detects sudden, violent movements to automatically trigger an SOS alert if you can\'t reach your phone.';
  static const String locationSharing = 'Location Sharing';
  static const String locationBody   =
      'Allows emergency contacts and responders to find your exact coordinates when an alarm is active.';
  static const String nfcVisibility  = 'NFC Visibility';
  static const String nfcBody        =
      'Required to pair with TapGuard wearable accessories and smart jewellery via a simple tap.';
  static const String microphoneAccess = 'Microphone Access';
  static const String microphoneBody =
      'Used only for "Voice Trigger" mode. Listens for your specific distress keywords when you feel unsafe.';
  static const String dataPolicyNote =
      'All data is end-to-end encrypted. We never sell your personal information to third parties.';
  static const String viewPrivacyPolicy = 'View Privacy Policy';
  static const String saveAndContinue = 'Save & Continue';

  // ── Settings ──────────────────────────────────────────────────────────────
  static const String settings       = 'Settings';
  static const String safetyEmergency = 'SAFETY & EMERGENCY';
  static const String emergencySmsTemplate = 'Emergency SMS Template';
  static const String smsDraft       = '"I\'m in danger, please check..."';
  static const String appPreferences = 'APP PREFERENCES';
  static const String notifications  = 'Notifications';
  static const String darkMode       = 'Dark Mode';
  static const String helpSupport    = 'Help & Support';
  static const String logout         = 'Logout';

  // ── History ───────────────────────────────────────────────────────────────
  static const String sessionHistory = 'Session History';
  static const String normal         = 'Normal';
  static const String sosTriggered   = 'SOS Triggered';

  // ── General ───────────────────────────────────────────────────────────────
  static const String ok             = 'OK';
  static const String confirm        = 'Confirm';
  static const String save           = 'Save';
  static const String back           = 'Back';
  static const String next           = 'Next';
  static const String skip           = 'Skip';
  static const String loading        = 'Loading...';
  static const String error          = 'Something went wrong';
  static const String retry          = 'Retry';
  static const String noInternet     = 'No internet connection';
}