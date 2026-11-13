# Fix slow Wifi

1. Update `/etc/nsswitch.conf` as follows:
   * Replace `hosts:      mymachines resolve [!UNAVAIL=return] files myhostname DNS` with `hosts:      files dns`

# Fix not displaying some Wifi networks

1. Rebuild _wpa_supplicant_ with _USE=tkip_

---

[← Documentation index](README.md) · Prev: [Application Configuration](04-application-configuration.md)
