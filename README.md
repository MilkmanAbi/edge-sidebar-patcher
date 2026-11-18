# Edge Sidebar Patcher

Brings back the classic Microsoft Edge sidebar (the right-hand app strip) on profiles signed in with a personal Microsoft account. It doesn't touch Edge's own files.

## What's going on

Edge 157 still ships the whole sidebar. It just hides the strip unless the profile's account is a work/school (Entra ID / AAD) account. Edge reads the account type from the profile's `Preferences` file:

```
account_info[0].edge_account_type    1 = personal Microsoft account   2 = work/school
```

How this was found, on Edge 157.0.4341.60 (Windows, and Linux in WSL):

- A fresh Edge 157 profile has no strip. Edge 114 has it by default.
- Copying a work profile's `Preferences` into a clean Edge 157 install on Linux brings the strip back.
- Swapping groups of keys between a work and a personal profile narrowed it down to `account_info`, then to `edge_account_type`. Setting it to `2` on a personal profile restores the strip with that profile's own apps. Setting it to `1` on a work profile removes the strip.
- `HubApps` (the sidebar's app manifest, the file that used to be transplanted to repair broken installs) is identical across profiles and doesn't control this.

Closing the sidebar with its own button switches `browser.hub_apps_tower_visible` off. On a personal profile, Edge then also hides the Settings toggle that would turn it back on. The patcher turns that pref back on too.

## Use

Edge gets closed while patching. Your tabs come back if "restore pages" is on.

```
Patch-EdgeSidebar.cmd                                   # double-click: pick a profile from a list
.\EdgeSidebarPatcher.ps1 -List
.\EdgeSidebarPatcher.ps1 -Profile Default
.\EdgeSidebarPatcher.ps1 -Profile Default -Revert
.\EdgeSidebarPatcher.ps1 -Channel Beta -Profile "Profile 2"
```

Each patch:

- saves `Preferences.sidebar-backup-<time>` in the profile folder first
- records the original value in `sidebar-patch.json`, so `-Revert` puts back exactly that value
- edits the file as text, so nothing else in it changes. The account-type change is a single character
- checks that the file still parses before swapping it in

The patcher doesn't touch `sync.edge_account_type`, `Secure Preferences`, `Local State`, or Edge's program files.

## Not yet confirmed

- Whether Edge sets `edge_account_type` back to `1` the next time it refreshes the account from Windows sign-in. If the strip disappears again, run the patch again.
- Whether reporting a personal account as work/school changes anything else, such as Copilot mode or sign-in prompts. `-Revert` undoes the change.
- It only works on profiles signed in with a Microsoft account. Profiles with no account are refused.
