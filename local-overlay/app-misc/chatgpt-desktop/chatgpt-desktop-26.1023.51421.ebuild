# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop pax-utils unpacker xdg

MY_PN=chatgpt

DESCRIPTION="Official ChatGPT desktop app by OpenAI (Chat, Work and Codex)"
HOMEPAGE="https://learn.chatgpt.com/docs/linux/linux-app"
# OpenAI's official .deb from its apt repository. Find new versions with:
# curl -s https://persistent.oaistatic.com/codex-app-prod/linux/deb/dists/stable/main/binary-amd64/Packages | grep ^Version
SRC_URI="https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/${MY_PN}/${MY_PN}_${PV}_amd64.deb"
S="${WORKDIR}"

LICENSE="all-rights-reserved"
SLOT="0"
KEYWORDS="-* ~amd64"
RESTRICT="bindist mirror strip"

# Mirrors the .deb's Depends/Recommends. The bundled Qt shims are dlopen()ed
# only under a Qt desktop, and the musl prebuilds are never loaded on glibc.
RDEPEND="
	app-accessibility/at-spi2-core:2
	app-arch/xz-utils
	app-crypt/tpm2-tss
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	dev-libs/nss
	dev-libs/openssl:0/3
	dev-vcs/git
	media-libs/alsa-lib
	media-libs/libglvnd
	media-libs/mesa
	net-print/cups
	sys-apps/dbus
	virtual/libudev
	virtual/libusb:1
	x11-libs/cairo
	x11-libs/gdk-pixbuf:2
	x11-libs/gtk+:3
	x11-libs/libnotify
	x11-libs/libX11
	x11-libs/libxcb
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libxkbcommon
	x11-libs/libXrandr
	x11-libs/pango
	x11-misc/xdg-utils
"

QA_PREBUILT="*"

src_install() {
	# cp -a keeps the .deb's modes on the many bundled helpers (codex, rg,
	# node, tectonic, ...) instead of listing them for fperms.
	dodir /opt
	cp -a usr/lib/${MY_PN} "${ED}"/opt/ || die
	pax-mark m "${ED}"/opt/${MY_PN}/ChatGPT

	# There is no chrome-sandbox: Chromium needs unprivileged user namespaces
	# (the .deb's AppArmor profile only grants userns, so it isn't needed here).
	dosym -r /opt/${MY_PN}/codex-launcher /usr/bin/${MY_PN}

	domenu usr/share/applications/${MY_PN}.desktop
	doicon usr/share/pixmaps/${MY_PN}.png
	insinto /usr/share/metainfo
	doins usr/share/metainfo/com.openai.chatgpt.metainfo.xml

	dodoc usr/share/doc/${MY_PN}/copyright
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "The .deb's postinst adds OpenAI's apt repository for automatic updates;"
	elog "that is skipped here. Bump this ebuild to the version listed in OpenAI's"
	elog "apt index (see the comment above SRC_URI), e.g. with chatgpt-desktop-bump."
	elog "The desktop entry registers ChatGPT for http/https links; if it takes over"
	elog "as your browser, reset it in GNOME Settings > Default Apps."
}
