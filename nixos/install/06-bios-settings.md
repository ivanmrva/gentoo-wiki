# Phase C: HP BIOS settings

Press F10 at power-on for BIOS setup (Esc shows the startup menu, F9 the boot
device menu). Menu names below follow HP business BIOS conventions and can
differ slightly by model and BIOS version.

1. Set a BIOS supervisor (administrator) password (Security). Without it,
   anyone with physical access can disable Secure Boot or replace your keys.
   Store it in your password manager.
1. Storage mode: if an Intel VMD or RAID option exists (often under
   Advanced → System Options), disable it so the NVMe disk is exposed
   directly. If no such option exists, nothing to do.
1. Secure Boot: disable it for the install (Advanced → Secure Boot
   Configuration). The NixOS installer is not signed for Secure Boot. You
   re-enable it with your own keys in [Phase E](08-secure-boot-tpm-hibernation.md).
1. TPM: leave it enabled. Use Clear TPM (Security → TPM Embedded Security)
   so it starts clean; HP asks for confirmation at the next boot.
1. Leave HP Sure Start enabled. It protects the BIOS itself and does not
   interfere with Linux.
1. Sleep: keep the default (Modern Standby / s2idle).
1. DMA protection: enable Kernel/Pre-boot DMA protection if offered. The
   IOMMU then blocks malicious Thunderbolt/USB4 devices from reading memory.
1. Memory encryption: if the BIOS offers Total Memory Encryption (Intel TME,
   a vPro feature), enable it. It protects RAM contents against physical
   extraction.
1. Battery Health Manager: set to "Maximize my battery health" (caps the
   charge level). This is the biggest lever for battery lifespan on a mostly
   plugged-in laptop, and the only charge cap available: Linux has no
   charge-threshold control for ZBooks.
1. Save and exit (F10).

> [!NOTE]
> On HP business laptops, changes to Secure Boot and TPM state usually
> require entering a 4-digit confirmation code displayed at the next boot.
> This is normal.
