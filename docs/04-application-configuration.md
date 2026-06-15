# Docker

1. `sudo emerge docker docker-compose`
1. `sudo systemctl enable docker.service`
1. `sudo usermod -aG docker <user>` (this guide's example: `ivmr`)

# IntelliJ IDEA

* Install additional plugins:
  * `ASCIIDOC`
  * `Markdown` community plugin (instead of the default one)
    * If preview mode is not working add `ide.browser.jcef.gpu.disable=true` under _Edit Custom Properties_ menu.
* Disable plugins not being used

---

[← Documentation index](README.md) · Prev: [After Installation](03-after-installation.md) · Next: [Troubleshooting →](05-troubleshooting.md)
