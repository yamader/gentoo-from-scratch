FROM alpine AS guix

WORKDIR /work

RUN <<-EOS
	apk add guix

	# update guix
	apk add autoconf automake gcc gettext-dev git guile-dev libc-dev make
	wget -O- https://codeberg.org/guix/guix-mirror/archive/master.tar.gz | tar xz
	(
		cd guix-mirror
		truncate -s0 doc/local.mk
		./bootstrap
		./configure --disable-daemon
		make -j$(nproc) install
	)
EOS

RUN <<-EOS
	guix-daemon --build-users-group=guixbuild --disable-chroot &
	# todo: --no-substitutes
	guix build --no-grafts \
		gcc-toolchain@11 make wget sed xz bzip2 gzip patch m4 bison coreutils findutils tar grep gawk bash
EOS

#FROM scratch AS prefix

RUN <<-EOS
	wget https://github.com/gentoo/prefix/raw/d11117546f6/scripts/bootstrap-prefix.sh
	sed -i '2739 { /LIBRARY_PATH/d }' bootstrap-prefix.sh # fix guix
	bash bootstrap-prefix.sh /prefix stage1
EOS
