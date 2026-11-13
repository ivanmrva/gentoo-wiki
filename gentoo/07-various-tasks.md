# Install custom fonts

1. `mkdir -p ~/.local/share/fonts`
1. `cp ~/Downloads/my-custom-fonts/*.ttf ~/.local/share/fonts/`

# Update BIOS (HP Zbook Firefly G9)

1. Check the current BIOS version:
   * `dmidecode -s bios-version`
1. Download BIOS installation from HP webpage and extract binaries from **.exe** file:
   * `7zz x ~/Downloads/sp156018.exe -obios`
1. Copy the correct binary (according to the current version) to the (the path has to match and the file has to be called **firmware.bin**):
   * `cp /tmp/bios-bin/U70_01070000.bin /boot/EFI/HP/DEVFW/firmware.bin`
1. Restart, start BIOS menu prompt (ESC/F10) and select **Update BIOS/firmware**.

---

[← Documentation index](README.md)
