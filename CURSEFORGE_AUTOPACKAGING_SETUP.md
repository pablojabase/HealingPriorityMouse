# CurseForge Automatic Packaging Setup

This repository is prepared for CurseForge automatic packaging with:
- TOC version token replacement (`@project-version@`)
- `.pkgmeta` packaging metadata (`package-as: HealingPriorityMouse`)

## Your Project Details
- Project ID: `1481438`
- Packaging token name: `GithubAutoPackaging`
- Flow: `tags only`

## 1. Configure GitHub Webhook
In GitHub for `pablojabase/HealingPriorityMouse`:
1. Open `Settings` -> `Webhooks` -> `Add webhook`
2. Payload URL:

```
https://www.curseforge.com/api/projects/1481438/package?token=ddc83226-b624-42bd-9037-261ad82bffdb
```

3. Content type: `application/json`
4. Leave other settings default
5. Save webhook

## 2. Confirm CurseForge Packaging Mode
In CurseForge project settings, keep packaging set to tags-only behavior.

## 3. Release Tag Conventions
Use the following tags:
- Release: `v1.0.10`
- Beta: `v1.0.11-beta.1`
- Alpha: `v1.0.12-alpha.1`

CurseForge classification rules:
- tag contains `alpha` -> Alpha
- tag contains `beta` -> Beta
- otherwise -> Release

## 4. How to Publish (No direct zip upload needed)
From this repo:

```powershell
git checkout master
git pull
git tag v1.0.10
git push origin master
git push origin v1.0.10
```

For beta/alpha, use matching tag names, for example:

```powershell
git tag v1.0.11-beta.1
git push origin v1.0.11-beta.1
```

## 5. Verify Packaged File Contents
Expected packaged folder name: `HealingPriorityMouse`
Expected TOC version: replaced automatically from `@project-version@`.

## Security Note
If this token was shared publicly, rotate it in CurseForge after setup and update the webhook with the new token.
