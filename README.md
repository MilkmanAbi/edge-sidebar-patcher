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

Edge is closed while patching. The patcher asks it to close normally first, then force-closes anything still running (including Startup Boost). Edge offers to restore your tabs the next time it opens.

Windows (PowerShell 5.1 or 7):

```
Patch-EdgeSidebar.cmd                                   # double-click: pick a profile from a list
.\EdgeSidebarPatcher.ps1 -List
.\EdgeSidebarPatcher.ps1 -Profile Default
.\EdgeSidebarPatcher.ps1 -Profile Default -Revert
.\EdgeSidebarPatcher.ps1 -Channel Beta -Profile "Profile 2"
```

Linux / macOS (needs PowerShell 7, `pwsh`). It finds `~/.config/microsoft-edge` or `~/Library/Application Support/Microsoft Edge` on its own:

```
pwsh ./EdgeSidebarPatcher.ps1 -List
pwsh ./EdgeSidebarPatcher.ps1 -Profile Default
```

`-UserDataDir <path>` points it at any other Edge data folder. In that mode it only closes Edge instances running on that folder, which is handy for testing on a copy.

## Tested

- Windows 11 with Edge 157: copies of a real personal profile, run under PowerShell 5.1 and 7. Checks covered patch, re-patch, revert (file back to byte-identical), the "sidebar was closed" case, and refusing a profile with no account.
- Linux with Edge 157.0.4341.60 (Ubuntu 24.04 under WSL, pwsh 7.7): Edge's default profile folder, with Edge running. The patcher closed Edge, the value stayed at `2` across a relaunch and Edge's own exit, and the strip came back with the profile's own apps.
- macOS: path and process matching are written, but it has never been run.

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
