# Getting Skeleton onto TestFlight

You need a paid Apple Developer Program membership ($99/year) and Xcode signed in to that account.

## 1. One-time setup

1. In Xcode: **Settings → Accounts → +** and sign in with your Apple ID.
2. Find your **Team ID**: developer.apple.com → Account → Membership details.
3. Create your local config (gitignored) and set your team. Pick a bundle ID you own, e.g. `com.yourname.skeleton`:
   ```bash
   cp App/Config/Skeleton.local.xcconfig.example App/Config/Skeleton.local.xcconfig
   ```
   Edit it: set `DEVELOPMENT_TEAM` and `PRODUCT_BUNDLE_IDENTIFIER`. Leave the Supabase lines empty to ship with demo data, or fill them in for a real backend.
4. Regenerate the project (quit Xcode first):
   ```bash
   xcodegen generate && open Skeleton.xcodeproj
   ```
5. In [App Store Connect](https://appstoreconnect.apple.com) → **Apps → + → New App**: platform iOS, name "Skeleton" (or a variant if taken), the same bundle ID, any SKU.

## 2. Upload a build

1. In Xcode, pick **Any iOS Device (arm64)** as the destination.
2. **Product → Archive**. When it finishes, the Organizer opens.
3. **Distribute App → TestFlight & App Store → Distribute**. Xcode signs and uploads it.
4. Bump `CFBundleVersion` in `project.yml` (the `"1"`) before each new upload.

## 3. Test it

1. In App Store Connect → your app → **TestFlight**, wait for the build to finish processing (5–30 min). Answer the export-compliance question if asked (the app declares no non-exempt encryption).
2. Add yourself under **Internal Testing**.
3. Install the **TestFlight** app on your iPhone and accept the invite.

## Xcode Cloud (optional)

`ci_scripts/ci_post_clone.sh` installs XcodeGen and generates the project after Xcode Cloud clones the repo, so a workflow with a TestFlight post-action works without committing the `.xcodeproj`.
