# Phase A: Preparation in Windows

Windows is the easiest place to update HP firmware and to capture what you
need to restore the machine later. Do this before anything else.

## A1. Update all firmware

1. Connect AC power. Open HP Support Assistant (preinstalled) or download HP
   Image Assistant from hp.com. Install every BIOS, firmware and driver
   update offered: BIOS, embedded controller, Intel ME, Thunderbolt,
   touchpad, dock firmware.
1. Update the SSD firmware: identify the SSD in Device Manager (Disk drives)
   and use the vendor tool (e.g. Samsung Magician, WD Dashboard, Kioxia SSD
   Utility), if HP's tool did not already cover it.
1. If BitLocker is active, the HP tools normally suspend it during BIOS
   updates. If you are prompted for a BitLocker recovery key afterwards, use
   the one from step A2.

## A2. Capture what you need for a later restore

1. BitLocker recovery key (only relevant if you ever restore Windows from an
   image): account.microsoft.com/devices/recoverykey, or in an admin
   terminal: `manage-bde -protectors -get C:`
1. HP recovery USB: run the HP Cloud Recovery Tool (Microsoft Store or
   hp.com) with a 32 GB+ USB stick. It downloads the factory image for your
   serial number. Label the stick and keep it.
1. Optional full disk image: boot Clonezilla from a USB stick and image the
   whole NVMe disk to an external drive. This is the byte-exact fallback,
   including HP's recovery partition.
1. Note the product name and serial number (sticker or BIOS Main page).

## A3. Hardware inventory

What is already known for A3ZU5ET#ABD (from HP QuickSpecs, the Ubuntu
certification and kernel source; details in `docs/hardware.md` of the repo):

| Part | Known | Still to check |
| --- | --- | --- |
| RAM | 2×32 GB DDR5-5600 SO-DIMM | Nothing: the `spd5118` suspend bug applies, see [B9](03-system-modules.md#b9-moduleshardware-intelnix) |
| Audio | Realtek, board ID `103c:8d94`, missing from the kernel quirk table | Mute and mic-mute LEDs in [Phase H](09-first-boot.md) |
| Wi-Fi | Intel BE201 (`8086:7740`), `iwlwifi` | Nothing |
| Graphics | Arc 140T on i915 (`xe` needs force-probe for Arrow Lake) | Nothing |
| Camera | 5 MP USB (UVC) camera | Confirm "USB Video Device" in Device Manager |
| Fingerprint | Goodix | **USB VID:PID**: look it up in the libfprint supported-devices list |
| WWAN | Not in this SKU | Nothing |
| Storage | NVMe | Whether "Intel RST VMD" is present (then change storage mode in [Phase C](06-bios-settings.md)) |
| Keyboard | `#ABD`: German QWERTZ physical layout | Nothing; you type US and Swiss German |

In Device Manager, use Properties → Details → Hardware Ids for the IDs.

## A4. Live test and hardware report (before wiping anything)

Boot Linux live from USB once while Windows is still intact. It shows how the
hardware behaves under Linux and produces the hardware report the flake
needs.

1. Write a live image to a USB stick: the NixOS graphical ISO (GNOME) for the
   camera/audio test, or your [custom installer ISO](00-prepare-on-gentoo.md#08-custom-installer-iso)
   if the stock ISO's kernel does not bring up Wi-Fi.
1. In the BIOS (F10), temporarily disable Secure Boot (the ISO is not signed
   for it). If BitLocker is active, Windows will ask for the recovery key
   from A2 on its next start; that is expected.
1. Boot the stick (F9), choose the live session, connect Wi-Fi.
1. Test quickly: camera (GNOME Snapshot), speakers and microphone, Wi-Fi,
   external display via USB-C, suspend and resume. Note anything that fails.
1. Generate the report and save it to the USB stick:
   `sudo nix-shell -p nixos-facter --run 'nixos-facter -o facter.json'`
1. Also note the fingerprint reader ID: `lsusb | grep -i goodix`
1. On Gentoo, commit it as `hosts/zbook/facter.json` and push. CI now builds
   the real host.

> [!TIP]
> **Done when:** firmware is current, the HP recovery USB exists,
> `facter.json` is committed, and you know which hardware works in the live
> session.
