# Miya Tools

This directory contains utility scripts and tools for managing the Miya Health platform.

## First-time iOS build

Before opening the project in Xcode, create the required secrets file (the project will not open without it):

```bash
./tools/setup_ios_secrets.sh
```

Or manually: `cp "Miya Health/Secrets.xcconfig.example" "Miya Health/Secrets.xcconfig"`.

Then edit `Miya Health/Secrets.xcconfig` and replace placeholders with your ROOK client UUID, ROOK secret key, Supabase URL, and Supabase anon key. Do **not** commit `Secrets.xcconfig` (it is in `.gitignore`).

## Scripts

### `auto_setup_scoring.ts`

Automated setup script for server-side vitality scoring. This script:
- Runs database migrations for scoring schema
- Generates and sets Edge Function secrets
- Provides deployment instructions

#### Prerequisites

1. **Environment Variables**: Set required environment variables before running:
   - `SUPABASE_URL`: Your Supabase project URL
   - `SUPABASE_SERVICE_ROLE_KEY`: Your Supabase service role key (keep secret!)
   - `SUPABASE_ACCESS_TOKEN`: (Optional) For automated secret management

   **iOS app:** The Miya Health app gets ROOK and Supabase keys from a **gitignored** xcconfig so they are never committed. See **First-time iOS build** above for creating `Secrets.xcconfig`. Then edit it with your ROOK client UUID, ROOK secret key, Supabase URL, and Supabase anon key (ROOK keys from your ROOK dashboard; Supabase values from Supabase project Settings → API). Do **not** commit `Secrets.xcconfig` (it is in `.gitignore`). The app will fail at launch with a clear error if the file is missing or keys are empty. For CI: provide the same variables as CI secrets and generate or inject `Secrets.xcconfig` during the build.

2. **Get Your Keys**:
   - Navigate to your Supabase Dashboard
   - Go to Settings → API
   - Copy the `URL` and `service_role` key (never commit these!)

#### Running with Deno (Recommended)

```bash
# Set environment variables and run
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key \
deno run -A tools/auto_setup_scoring.ts
```

Or create a `.env` file (never commit this!):

```bash
# Copy example and fill in values
cp .env.example .env
# Edit .env with your actual keys
# Then run:
deno run -A --env tools/auto_setup_scoring.ts
```

#### Running with Node.js

```bash
# Set environment variables and run
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key \
node tools/auto_setup_scoring.ts
```

#### Using dotenv (Node.js)

```bash
# Install dotenv
npm install dotenv

# Create .env file
cp .env.example .env
# Edit .env with your actual keys

# Run with dotenv
node -r dotenv/config tools/auto_setup_scoring.ts
```

## Security Best Practices

⚠️ **IMPORTANT**: Never commit sensitive credentials to version control!

- ✅ Use environment variables for all secrets
- ✅ Keep `.env` files local only (already in `.gitignore`)
- ✅ Use `.env.example` with placeholder values for documentation
- ✅ **iOS:** Use `Secrets.xcconfig` (gitignored) for ROOK and Supabase keys; copy from `Secrets.xcconfig.example`.
- ✅ Rotate keys immediately if accidentally exposed (e.g. keys that were ever in git history must be rotated in the ROOK and Supabase dashboards; then use the new keys only in local/CI `Secrets.xcconfig` or env).
- ❌ Never hardcode API keys or service role keys in source code
- ❌ Never commit `.env` files or `Miya Health/Secrets.xcconfig`
- ❌ Never share service role keys in chat/email

## Getting Help

If you encounter issues:

1. Verify your environment variables are set correctly
2. Check that your Supabase project is active
3. Ensure you have the correct permissions
4. Review the Supabase Dashboard for any errors

For more information, see the main project documentation.
