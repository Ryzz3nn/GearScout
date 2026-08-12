GearScout Installer
====================

What this is
------------
A small app that installs or updates the GearScout addon for World of
Warcraft. It does not install anything on your computer, it just copies
the addon into your WoW folder. Delete this folder when you are done and
nothing is left behind.

How to use it
--------------
1. Double click GearScoutInstaller.cmd.
2. The app looks for World of Warcraft on your computer and lists what it
   finds. Pick the one you play on.
3. Click Install.
4. Start or restart World of Warcraft.

If nothing was found automatically, click "Browse for a different folder"
and pick your WoW folder (or the Interface\AddOns folder inside it).

GearScout_Lead
--------------
This is the officer only half of the addon, it lets you see other
players' gear from the raid lead console. Most people do not need it.
The checkbox for it only appears when it is available to install.

If something goes wrong
-------------------------
Any problem is shown in the app itself, in plain language. This app never
touches files outside the GearScout and GearScout_Lead folders it manages,
and it will never overwrite a folder that is set up for addon development
(it will tell you plainly if that is what it found instead).

Files in this folder
---------------------
GearScoutInstaller.cmd   - double click this one
GearScoutInstaller.ps1   - the app itself
GearScoutInstaller.xaml  - the window layout
lib\Detect.ps1           - finds World of Warcraft on your computer
lib\InstallLogic.ps1     - copies the addon files
