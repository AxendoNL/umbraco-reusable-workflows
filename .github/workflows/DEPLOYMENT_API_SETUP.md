# Umbraco Cloud Deployment API Setup

This document describes the configuration needed to use the Deployment API version of the sync-changes-to-cloud action.

## Overview

The deployment API approach (`@deployment-api` tag) uses Umbraco Cloud's Deployment API v2 instead of the traditional git-based sync. This provides better integration, status tracking, and deployment control.

## Required GitHub Secrets

Configure these secrets in your repository settings (Settings > Secrets and variables > Actions > Secrets):

| Secret Name | Description | How to Obtain |
|-------------|-------------|---------------|
| `PROJECTID` | Your Umbraco Cloud project GUID | Found in Umbraco Cloud portal under Project Settings |
| `UMBRACOCLOUDAPIKEY` | API key for Umbraco Cloud API access | Generate in Umbraco Cloud portal under Project Settings > API Keys |
| `NUGET_PAT` | GitHub Personal Access Token for NuGet packages | Existing secret (already configured) |

## Required GitHub Variables

Configure these variables in your repository settings (Settings > Secrets and variables > Actions > Variables):

| Variable Name | Description | Default | Example |
|---------------|-------------|---------|---------|
| `TARGET_ENVIRONMENT_ALIAS` | Target environment to deploy to | - | `live` or `staging` |
| `NOBUILDANDRESTORE` | Skip build and restore on cloud (0=false, 1=true) | `0` | `0` |
| `SKIPVERSIONCHECK` | Skip Umbraco version check (0=false, 1=true) | `0` | `0` |

### Optional Variables (Existing)

These variables are already used by the workflow:

- `FRONTEND_NODE_VERSION` - Node version for frontend builds
- `VUE_NODE_VERSION` - Node version for Vue builds
- `SKIP_FRONTEND` - Skip frontend build if set to 'true'
- `SKIP_VUE` - Skip Vue build if set to 'true'
- `SKIP_CLEANUP` - Skip cleanup step if set to 'true'

## Deprecated Secrets

When using the Deployment API approach, these secrets are **no longer needed**:

- ~~`UMBRACO_CLOUD_USERNAME`~~ - Not used with API
- ~~`UMBRACO_CLOUD_PASSWORD`~~ - Not used with API
- ~~`CLOUD_REPOSITORY_URL`~~ - Not used with API

## How It Works

1. **Prepare**: Switches `.gitignore` to `cloud.gitignore` to include built assets
2. **Substitute**: Updates `appsettings.json` with runtime minification version
3. **Zip**: Creates `sources.zip` excluding frontend/vue source directories and items in `cloud.zipignore`
4. **Upload**: Uploads artifact to Umbraco Cloud API and receives an `artifactId`
5. **Deploy**: Starts deployment to target environment using the artifact
6. **Wait**: Polls deployment status until completion (timeout: 40 minutes)

## Required Files in Project Root

### cloud.gitignore
A more permissive gitignore that allows built assets to be included in the deployment. During deployment, this file replaces your regular `.gitignore`.

**Purpose:** Your normal `.gitignore` excludes built files like `wwwroot/assets/`, but cloud needs these. The `cloud.gitignore` allows:
- ✅ Compiled frontend/Vue assets
- ✅ Built artifacts needed by cloud
- ❌ Still blocks: temp files, logs, media, IDE files

### cloud.zipignore
Controls what gets excluded from the `sources.zip` uploaded to Umbraco Cloud.

**Purpose:** Keeps deployment size small by excluding:
- ❌ Source code folders: `node_modules/`, `.Frontend/`, `.Vue/`
- ❌ Build artifacts: `bin/`, `obj/` (cloud rebuilds these)
- ❌ Pipeline files: `.github/`, `.git/`
- ❌ Dev files: documentation, IDE configs

**Result:** Only production-ready files get deployed, not source code or build tools.

## Migration from Git-based Sync

To migrate from the old git-based sync to Deployment API:

1. Set up all required secrets and variables listed above
2. Update your workflow to use `@deployment-api` tag instead of `@umbraco-v9`
3. Test the deployment workflow
4. Once confirmed working, you can remove the deprecated secrets

## Troubleshooting

### Deployment fails with "Artifact not found"

- Verify `UMBRACO_CLOUD_PROJECT_ID` is correct
- Check that the artifact upload step succeeded
- Review artifact upload logs

### Deployment fails with "Unauthorized"

- Verify `UMBRACO_CLOUD_API_KEY` is valid
- Ensure API key has deployment permissions
- Check if API key has expired

### Deployment times out

- Default timeout is 40 minutes (2400 seconds)
- Check Umbraco Cloud portal for deployment status
- Review deployment logs in Umbraco Cloud

## API Documentation

For more details on the Umbraco Cloud Deployment API:
https://docs.umbraco.com/umbraco-cloud/set-up/project-settings/umbraco-cicd/umbracocloudapi/
