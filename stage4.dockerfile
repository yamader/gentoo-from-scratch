FROM gentoo
RUN emerge-webrsync
RUN <<-EOS
	mkdir -p /etc/portage/patches/dev-lang/rust
	cat > /etc/portage/patches/dev-lang/rust/wtf.patch <<-EOF
		--- a/src/llvm-project/llvm/tools/sancov/sancov.cpp
		+++ b/src/llvm-project/llvm/tools/sancov/sancov.cpp
		@@ -505,7 +505,7 @@
		   static std::unique_ptr<SpecialCaseList> createUserIgnorelist() {
		     if (ClIgnorelist.empty())
		       return std::unique_ptr<SpecialCaseList>();
		-    return SpecialCaseList::createOrDie({{ClIgnorelist}},
		+    return SpecialCaseList::createOrDie({ClIgnorelist},
		                                         *vfs::getRealFileSystem());
		   }
		   std::unique_ptr<SpecialCaseList> DefaultIgnorelist;
	EOF

	USE=mrustc-bootstrap CC=gcc LDFLAGS=-fuse-ld=lld emerge -1j dev-lang/rust:1.74.1
	emerge -1j dev-lang/rust
EOS
RUN <<-EOS
	emerge-webrsync
	emerge -1j dev-vcs/git
	rm -r /etc/portage
	git clone https://github.com/yamader/gentoo-config /etc/portage
	rm -r /var/db/repos/gentoo
	emerge --sync
	eselect profile set yamad:llvm-desktop

	mv /etc/portage/env/mold /tmp
	USE=-* emerge -1 hwloc
	emerge -1 mold
	mv /tmp/mold /etc/portage/env
EOS

RUN <<-EOS
	cat > /etc/portage/package.use/_required <<-EOF
		dev-libs/libpcre -readline
		dev-libs/libpcre2 -readline

		dev-libs/expat abi_x86_32
		dev-libs/icu abi_x86_32
		dev-libs/libedit abi_x86_32
		dev-libs/wayland abi_x86_32
		dev-util/perf libpfm
		dev-util/spirv-tools abi_x86_32
		gui-libs/egl-gbm abi_x86_32
		gui-libs/egl-wayland abi_x86_32
		gui-libs/egl-x11 abi_x86_32
		media-libs/libglvnd abi_x86_32
		media-libs/libva abi_x86_32
		media-libs/mesa abi_x86_32
		sys-libs/gpm abi_x86_32
		x11-libs/libX11 abi_x86_32
		x11-libs/libXau abi_x86_32
		x11-libs/libXdmcp abi_x86_32
		x11-libs/libXext abi_x86_32
		x11-libs/libXfixes abi_x86_32
		x11-libs/libXrandr abi_x86_32
		x11-libs/libXrender abi_x86_32
		x11-libs/libXxf86vm abi_x86_32
		x11-libs/libdrm abi_x86_32
		x11-libs/libvdpau abi_x86_32
		x11-libs/libxcb abi_x86_32
		x11-libs/libxshmfence abi_x86_32
		x11-libs/xcb-util-keysyms abi_x86_32
	EOF

	emerge -1 sys-devel/gcc:11
	emerge -1 sys-devel/gcc:13
	emerge -1 sys-devel/gcc:15
	USE=-* emerge -1 media-libs/libwebp
EOS
