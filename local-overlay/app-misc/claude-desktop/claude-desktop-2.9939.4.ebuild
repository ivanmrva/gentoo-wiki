# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop pax-utils unpacker xdg

DESCRIPTION="Official Claude desktop app by Anthropic (Chat, Cowork and Claude Code)"
HOMEPAGE="https://code.claude.com/docs/en/desktop-linux"
# Anthropic's official .deb from its apt repository. Find new versions with:
# curl -s https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-amd64/Packages | grep ^Version
SRC_URI="https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/${PN}/${PN}_${PV}_amd64.deb"
S="${WORKDIR}"

LICENSE="all-rights-reserved"
SLOT="0"
KEYWORDS="-* ~amd64"
IUSE="+cowork"
RESTRICT="bindist mirror strip"

# Mirrors the .deb's Depends, plus the libraries its ELF files link against.
# OVMF comes from qemu[qemu_softmmu_targets_x86_64], which installs edk2(-bin)
# at the version it pins; depending on edk2-bin here would fight that pin.
RDEPEND="
	app-accessibility/at-spi2-core:2
	app-crypt/libsecret
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	dev-libs/nss
	media-libs/alsa-lib
	media-libs/mesa
	net-print/cups
	sys-apps/dbus
	sys-apps/util-linux
	sys-apps/xdg-desktop-portal
	|| (
		sys-apps/xdg-desktop-portal-gnome
		sys-apps/xdg-desktop-portal-gtk
		kde-plasma/xdg-desktop-portal-kde
	)
	virtual/libudev
	x11-libs/cairo
	x11-libs/gtk+:3
	x11-libs/libdrm
	x11-libs/libnotify
	x11-libs/libX11
	x11-libs/libxcb
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libxkbcommon
	x11-libs/libXrandr
	x11-libs/libXtst
	x11-libs/pango
	x11-misc/xdg-utils
	cowork? (
		app-emulation/qemu[qemu_softmmu_targets_x86_64,seccomp,slirp]
		app-emulation/virtiofsd
		sys-libs/libcap-ng
		sys-libs/libseccomp
	)
"

QA_PREBUILT="*"

src_prepare() {
	default

	# Debian packaging leftovers; Gentoo has no lintian.
	rm -r usr/share/lintian || die

	# The GNOME search provider service points at the Debian install path.
	sed -i "s|/usr/lib/${PN}|/opt/${PN}|" \
		usr/lib/${PN}/resources/gnome-search-provider/com.anthropic.Claude.SearchProvider.service || die
}

src_install() {
	insinto /opt
	doins -r usr/lib/${PN}

	local f
	for f in ${PN} chrome_crashpad_handler chrome-sandbox \
		resources/{chrome-native-host,claude-browser-shim.js,cowork-linux-helper,virtiofsd} \
		resources/app.asar.unpacked/resources/github-mcp/github-mcp-server; do
		fperms +x /opt/${PN}/${f}
	done
	# Same setuid fallback sandbox as the .deb and app-editors/vscode; Chromium
	# only uses it when unprivileged user namespaces are unavailable.
	fperms 4711 /opt/${PN}/chrome-sandbox
	pax-mark m "${ED}"/opt/${PN}/${PN}

	dosym -r /opt/${PN}/${PN} /usr/bin/${PN}

	domenu usr/share/applications/com.anthropic.Claude.desktop
	local size
	for size in 16 32 48 128 256; do
		doicon -s ${size} usr/share/icons/hicolor/${size}x${size}/apps/${PN}.png
	done

	# The .deb's postinst copies these into place; do it at install time instead.
	local sp=usr/lib/${PN}/resources/gnome-search-provider
	insinto /usr/share/gnome-shell/search-providers
	doins ${sp}/com.anthropic.Claude.search-provider.ini
	insinto /usr/share/dbus-1/services
	doins ${sp}/com.anthropic.Claude.SearchProvider.service

	if use cowork; then
		# Cowork only probes Debian's OVMF paths and derives the VARS template
		# by replacing CODE with VARS. Point both at Gentoo's raw 2M pair (the
		# 4M edk2 images are qcow2, which Cowork's raw pflash drives can't use).
		dosym -r /usr/share/edk2/OvmfX64/OVMF_CODE.fd /usr/share/OVMF/OVMF_CODE.fd
		dosym -r /usr/share/edk2/OvmfX64/OVMF_VARS.fd /usr/share/OVMF/OVMF_VARS.fd
	fi

	dodoc usr/share/doc/${PN}/copyright
}

pkg_postinst() {
	xdg_pkg_postinst

	if use cowork; then
		elog "Cowork runs its VM with QEMU/KVM. qemu's 65-kvm.rules makes /dev/kvm"
		elog "and /dev/vhost-vsock 0660 root:kvm, so add your user to the kvm group"
		elog "(usermod -aG kvm <user>) and log in again."
	fi
	elog "Updates are not automatic: bump this ebuild to the version listed in"
	elog "Anthropic's apt index (see the comment above SRC_URI)."
}
