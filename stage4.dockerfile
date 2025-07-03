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
	emerge -j dev-lang/rust
	emerge -c
	emerge -W dev-lang/rust
	rm /etc/portage/patches/dev-lang/rust/wtf.patch
EOS
RUN emerge -1j dev-vcs/git sys-devel/mold
RUN <<-EOS
	rm -r /etc/portage
	git clone https://github.com/yamader/gentoo-config /etc/portage
	rm -r /var/db/repos/gentoo
	emerge --sync
	eselect profile set yamad:llvm-desktop

	emerge -1 sys-devel/gcc:11
	emerge -1 sys-devel/gcc
EOS
RUN <<-EOS
	USE=-* emerge -1 \
		app-text/xmlto \
		dev-lang/python{,:3.14t} \
		media-libs/harfbuzz \
		media-libs/libwebp

	emerge -uDN @world
EOS
