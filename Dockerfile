FROM alpine AS guix
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

	# build env
	guix-daemon --build-users-group=guixbuild --disable-chroot &
	# todo: --no-substitutes
	guix package -p /guix-profile --bootstrap --no-grafts -i \
		gcc-toolchain@11 make wget sed xz bzip2 gzip patch m4 bison coreutils findutils tar grep gawk bash
EOS

FROM scratch AS prefix
COPY --from=guix /gnu/store /gnu/store
COPY --from=guix /guix-profile /
COPY --from=guix /guix-profile /usr
RUN <<-EOS
	. /etc/profile
	echo 'root::0:0:::' > /etc/passwd # for stage1 prefix-portage-3.0.56.1

	wget --no-check-certificate https://github.com/gentoo/prefix/raw/d11117546f6/scripts/bootstrap-prefix.sh
	sed -i '
		2712 { /exit 1/d }        # I am root
		2739 { /LIBRARY_PATH/d }  # fix guix
	' bootstrap-prefix.sh

	bash bootstrap-prefix.sh /prefix wget # fix stage2 binutils make segv
	bash bootstrap-prefix.sh /prefix stage1
	# todo:
	#bash bootstrap-prefix.sh /prefix stage2
	#bash bootstrap-prefix.sh /prefix stage3
EOS

RUN <<-EOS
	echo . /etc/profile > .bashrc
	cat > /.bashrc <<-EOF
		. /etc/profile
		alias bootstrap='bash /bootstrap-prefix.sh /prefix'
	EOF
EOS

ENTRYPOINT ["bash"]
