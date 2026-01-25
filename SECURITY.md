# 🔐 API Keys and Security Configuration

This project uses sensitive API keys and credentials that should NOT be committed to version control.

## 📋 Setup Instructions

### 1. Environment Variables

1. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` and add your actual credentials:
   - Firebase API Key
   - Firebase Project ID
   - Firebase Messaging Sender ID
   - Firebase Storage Bucket
   - Firebase Auth Domain
   - Firebase App IDs (Web, Android, iOS)
   - Google Maps API Key

### 2. Firebase Configuration Files

#### iOS - GoogleService-Info.plist
1. Download your `GoogleService-Info.plist` from Firebase Console
2. Place it in `ios/Runner/`
3. **DO NOT** commit this file to git (already in .gitignore)

#### Android - google-services.json
1. Download your `google-services.json` from Firebase Console
2. Place it in `android/app/`
3. **DO NOT** commit this file to git (already in .gitignore)

#### Dart - firebase_options.dart
1. Run FlutterFire CLI to generate this file:
   ```bash
   flutterfire configure
   ```
2. This file contains your Firebase configuration
3. **DO NOT** commit this file to git (already in .gitignore)

### 3. Google Maps API Key

The Google Maps API key is stored in `.env` and should be:
- Added to `ios/Runner/AppDelegate.swift` (already configured)
- Added to `android/app/src/main/AndroidManifest.xml` (already configured)

## 🔒 Security Best Practices

### Files that are IGNORED by Git (safe):
- `.env` - Environment variables
- `ios/Runner/GoogleService-Info.plist` - iOS Firebase config
- `android/app/google-services.json` - Android Firebase config
- `lib/firebase_options.dart` - Dart Firebase config

### Files that are COMMITTED to Git (safe):
- `.env.example` - Template with placeholder values
- All other code files

## ⚠️ Important Notes

1. **Never commit actual API keys** to version control
2. **Rotate your keys immediately** if accidentally committed
3. **Use Firebase Security Rules** to protect your database
4. **Enable API restrictions** in Google Cloud Console for Maps API
5. **Use different keys** for development and production

## 🚨 If You Accidentally Commit Keys

If you accidentally commit API keys:

1. **Immediately rotate/regenerate** the compromised keys in Firebase/Google Cloud Console
2. Remove the keys from git history:
   ```bash
   git filter-branch --force --index-filter \
   "git rm --cached --ignore-unmatch path/to/file" \
   --prune-empty --tag-name-filter cat -- --all
   ```
3. Force push to remote (if already pushed):
   ```bash
   git push origin --force --all
   ```
4. Update `.env` with new keys

## 📱 Getting Your API Keys

### Firebase Console
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Go to Project Settings
4. Download configuration files or copy keys

### Google Maps Platform
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Navigate to APIs & Services > Credentials
3. Create or manage your API keys
4. Enable Maps SDK for iOS and Android
5. Set up API restrictions for security

## 🔧 Team Setup

When a new team member joins:

1. They should copy `.env.example` to `.env`
2. Project admin provides the actual API keys
3. They download Firebase config files from Firebase Console
4. They run `flutter pub get` and `pod install` (for iOS)

## ✅ Verification

To verify your setup is secure:

```bash
# Check that sensitive files are ignored
git status

# These files should NOT appear in git status:
# - .env
# - ios/Runner/GoogleService-Info.plist
# - android/app/google-services.json
# - lib/firebase_options.dart
```

## 📞 Support

If you have issues with API key configuration, contact the project admin.

---

**Remember:** Security is not an afterthought. Always protect your API keys! 🔐
