# syntax=docker/dockerfile:1-labs

FROM alpine AS live-bootstrap-src
COPY live-bootstrap.patch /
RUN --mount=type=cache,target=/live-bootstrap/distfiles <<-EOS
	set -eux

	mkdir -p live-bootstrap
	cd live-bootstrap

	# 2026-01-11
	wget -O- https://github.com/fosslinux/live-bootstrap/archive/59e5a4341a959971bc58b4a043accd8c5bec8c22.tar.gz \
		| tee >(tar xz --strip-components=1) \
		| sha256sum -c <(echo f7332c92badbf662a5a5ab08604eaa2bfeca77bb38aee89f85ae7a847ffdc71f -)
	wget -O- https://github.com/ironmeld/builder-hex0/archive/a2781242d19e6be891b453d8fa827137ab5db31a.tar.gz \
		| tee >(tar xzC builder-hex0 --strip-components=1) \
		| sha256sum -c <(echo cc42c9e40b14505cd79165b49750d54959bbfb21d738fab5e7d5762a98b1d7cb -)
	wget -O- https://github.com/oriansj/stage0-posix/releases/download/Release_1.9.1/stage0-posix-1.9.1.tar.gz \
		| tee >(tar xzC seed/stage0-posix --strip-components=1) \
		| sha256sum -c <(echo f4fdda675de90ab034fd3467ef43cddff61b3d372f8e0e5c2d25d145f224226f -)

	# fix live-bootstrap
	apk add patch
	patch -p1 < /live-bootstrap.patch

	# download distfiles using mirror.sh
	apk add curl git xz
	mkdir -p distfiles
	sh mirror.sh distfiles

	# cf. rootfs.py
	cat > steps/bootstrap.cfg <<-EOF
		ARCH=x86
		ARCH_DIR=x86
		FORCE_TIMESTAMPS=False
		CHROOT=True
		UPDATE_CHECKSUMS=False
		JOBS=$(nproc)
		SWAP_SIZE=0
		FINAL_JOBS=$(nproc)
		INTERNAL_CI=False
		INTERACTIVE=False
		QEMU=False
		BARE_METAL=False
		DISK=hoge
		KERNEL_BOOTSTRAP=False
		BUILD_KERNELS=False
		CONFIGURATOR=False
		MIRRORS_LEN=0
	EOF

	# setup new root
	mkdir -p /rootfs/external
	cp -r distfiles /rootfs/external/
	mv seed/stage0-posix/* seed/*.* steps /rootfs/
	rm -r /rootfs/High\ Level\ Prototypes

	# cleanup after
	ls /rootfs > /rootfs/srcs
	cat >> /rootfs/srcs <<-EOF
		configurator
		preseed-jump.kaem
		script-generator
		seed-full.kaem
	EOF
EOS

FROM scratch AS live-bootstrap
COPY --from=live-bootstrap-src /rootfs /
# from 181 bytes hex0-seed
RUN ["./bootstrap-seeds/POSIX/x86/hex0-seed", "./x86/hex0_x86.hex0", "./x86/artifact/hex0"]
RUN ["./x86/artifact/hex0", "./x86/kaem-minimal.hex0", "./x86/artifact/kaem-0"]
RUN ["./x86/artifact/kaem-0"]
RUN rm -r $(cat srcs) /tmp/*
ENTRYPOINT ["/bin/bash"]

# GNU --------------------------------------------------------------------------------------------------------------------------

FROM live-bootstrap AS x86_64-pc-linux-gnu
RUN <<-EOS
	set -eux

	TARGET=x86_64-pc-linux-gnu
	BINUTILS=binutils-2.45
	GCC=gcc-15.2.0
	GLIBC=glibc-2.41
	WGET=wget-1.25.0

	mkdir bootstrap-64
	cd bootstrap-64

	curl https://ftp.gnu.org/gnu/binutils/$BINUTILS.tar.xz | tar xJ
	curl https://ftp.gnu.org/gnu/gcc/$GCC/$GCC.tar.xz | tar xJ
	curl https://ftp.gnu.org/gnu/glibc/$GLIBC.tar.xz | tar xJ
	curl https://ftp.gnu.org/gnu/wget/$WGET.tar.lz | tar xJ

	# merge-usr for glibc
	ln -s usr/lib64 /

	# wget w/ openssl for portage
	cd $WGET
	./configure --prefix=/usr --with-ssl=openssl --with-libssl-prefix=/usr/ssl
	make -j$(nproc) install
	cd -

	cd $BINUTILS
	./configure --target=$TARGET --disable-gprofng
	make -j$(nproc)
	make install
	cd -

	mkdir $GCC/build-gcc
	cd $GCC/build-gcc
	# --disable-fixincludes: prevent /usr/local/lib/gcc/x86_64-pc-linux-gnu/15.2.0/include-fixed/stdio.h for glibc
	# --with-newlib: cf. https://ryanstan.com/gcc-without-headers-flag.html
	../configure \
		--target=$TARGET \
		--enable-languages=c,c++ \
		--disable-libatomic \
		--disable-libgomp \
		--disable-libquadmath \
		--disable-libssp \
		--disable-libstdcxx \
		--disable-libvtv \
		--disable-shared \
		--disable-threads \
		--disable-fixincludes \
		--with-sysroot=/ \
		--without-headers \
		--with-newlib
	make -j$(nproc)
	make install
	cd -

	mkdir $GLIBC/build-64
	cd $GLIBC/build-64
	../configure --prefix=/usr --host=$TARGET
	make -j$(nproc)
	make install
	cd -
	mkdir $GLIBC/build-32
	cd $GLIBC/build-32
	../configure --prefix=/usr --host=i686-pc-linux-gnu CC="$TARGET-gcc -m32" CXX="$TARGET-g++ -m32"
	make -j$(nproc)
	make install
	cd -

	mkdir $GCC/build-libstdc++
	cd $GCC/build-libstdc++
	../libstdc++-v3/configure \
		--prefix=/usr/local/$TARGET \
		--host=$TARGET \
		--disable-multilib
	make -j$(nproc) install
	cd -

	cd ..
	rm -r bootstrap-64

	# for gcc
	ln -s /lib64/libm.so.6 /usr/local/$TARGET/lib64
	ln -s /usr/local/bin/$TARGET-cpp /lib/cpp

	# for coreutils
	rm /usr/include/stropts.h
EOS

FROM x86_64-pc-linux-gnu AS gentoo-gnu
ARG GENTOO_STAGE0=c929c47f09339eb3bb4ff108ba8ca6a722680d19 # 2026-01-06; latest sys-apps/portage
RUN --mount=type=cache,target=/var/cache/distfiles <<-EOS
	set -eux

	# portage-3.0.70: find: invalid predicate `-files0-from'
	PORTAGE=portage-3.0.69.3

	mkdir -p /etc/portage /var/db/repos/gentoo
	curl -L https://github.com/gentoo/gentoo/archive/$GENTOO_STAGE0.tar.gz | tar xzC /var/db/repos/gentoo --strip-components=1
	ln -s ../../var/db/repos/gentoo/profiles/default/linux/amd64/23.0 /etc/portage/make.profile

	curl -L https://github.com/gentoo/portage/archive/$PORTAGE.tar.gz | tar xz
	cd portage-$PORTAGE

	mkdir /usr/share/portage
	cp -r cnf /usr/share/portage/config
	useradd portage

	# for portage
	ln -s tar /usr/bin/gtar

	# fix make; live-bootstrap's is not usable with -jN
	MAKEOPTS=-j1 ./bin/emerge -1O \
		app-portage/elt-patches \
		sys-apps/gentoo-functions \
		app-arch/xz-utils \
		dev-build/make

	# fix toolchain
	USE=-* ./bin/emerge -1O \
		sys-libs/zlib \
		sys-devel/binutils-config \
		sys-devel/binutils \
		dev-build/autoconf \
		dev-build/automake \
		net-misc/rsync \
		sys-kernel/linux-headers \
		dev-libs/gmp \
		dev-libs/mpfr \
		dev-libs/mpc \
		sys-devel/gcc-config \
		sys-devel/gcc

	# fix collisions
	mv /bin/{bzip2,bc,dc,gunzip,gzip,zcat} /usr/local/bin
	USE=-* ./bin/emerge -1Oj \
		app-arch/bzip2 \
		app-arch/gzip \
		sys-devel/bc

	rm -r /usr/local

	# fix profile
	USE=-* ./bin/emerge -1Oj \
		app-crypt/libb2 \
		sys-apps/util-linux \
		sys-devel/gettext \
		sys-libs/libxcrypt \
		virtual/libcrypt

	./bin/emerge -1j sys-apps/portage

	cd -
	rm -r portage-$PORTAGE

	# diet
	echo shadow:x:42: >> /etc/group
	USE=-* emerge -1Oj \
		net-misc/wget \
		sys-apps/grep \
		sys-apps/shadow
	rm -r \
		/usr/bin/perl5.{1..3}* \
		/usr/i686-unknown-linux-musl \
		/usr/include/c++ \
		/usr/lib/i686-unknown-linux-musl \
		/usr/lib/perl5 \
		/usr/lib/python2.5 \
		/usr/lib/python3.11 \
		/usr/libexec/gcc/i686-unknown-linux-musl
	emerge -1Oj dev-lang/perl
EOS

FROM gentoo-gnu AS stage0-amd64-gnu
RUN --mount=type=cache,target=/var/cache/distfiles <<-EOS
	set -eux

	# fix systemd
	sed -i 's/nogroup/nobody/' /etc/group
	emerge -1j sys-apps/diffutils
	emerge -1j sys-libs/pam

	USE='default-compiler-rt default-libcxx default-lld llvm-libunwind' \
	emerge -1j --autounmask-continue \
		llvm-core/clang \
		llvm-core/lld \
		llvm-core/llvm \
		llvm-runtimes/compiler-rt \
		llvm-runtimes/libcxx \
		llvm-runtimes/libcxxabi \
		llvm-runtimes/libunwind

	tar cJf /stage0-amd64-gnu.txz \
		--exclude /dev \
		--exclude /proc \
		--exclude /sys \
		--exclude /var/db/repos/gentoo \
		/*
EOS

# musl -------------------------------------------------------------------------------------------------------------------------

FROM live-bootstrap AS x86_64-pc-linux-musl
RUN <<-EOS
	set -eux

	TARGET=x86_64-pc-linux-musl
	BINUTILS=binutils-2.45
	GCC=gcc-15.2.0
	MUSL=musl-1.2.5
	WGET=wget-1.25.0

	mkdir bootstrap-64
	cd bootstrap-64

	curl https://ftp.gnu.org/gnu/binutils/$BINUTILS.tar.xz | tar xJ
	curl https://ftp.gnu.org/gnu/gcc/$GCC/$GCC.tar.xz | tar xJ
	curl https://musl.libc.org/releases/$MUSL.tar.gz | tar xz
	curl https://ftp.gnu.org/gnu/wget/$WGET.tar.lz | tar xJ

	cd $WGET
	./configure --prefix=/usr --with-ssl=openssl --with-libssl-prefix=/usr/ssl
	make -j$(nproc) install
	cd -

	cd $BINUTILS
	./configure --target=$TARGET --disable-gprofng
	make -j$(nproc)
	make install
	cd -

	mkdir $GCC/build-gcc
	cd $GCC/build-gcc
	../configure \
		--target=$TARGET \
		--enable-languages=c,c++ \
		--disable-libatomic \
		--disable-libgomp \
		--disable-libquadmath \
		--disable-libssp \
		--disable-libstdcxx \
		--disable-libvtv \
		--disable-shared \
		--disable-threads \
		--with-sysroot=/ \
		--without-headers \
		--with-newlib
	make -j$(nproc)
	make install
	cd -

	cd $MUSL
	./configure --prefix=/usr --target=$TARGET
	make -j$(nproc) install
	cd -

	mkdir $GCC/build-libstdc++
	cd $GCC/build-libstdc++
	../libstdc++-v3/configure \
		--prefix=/usr/local/$TARGET \
		--host=$TARGET \
		--disable-multilib
	make -j$(nproc) install
	cd -

	cd ..
	rm -r bootstrap-64
EOS

FROM x86_64-pc-linux-musl AS gentoo-musl
ARG GENTOO_STAGE0=c929c47f09339eb3bb4ff108ba8ca6a722680d19
RUN --mount=type=cache,target=/var/cache/distfiles <<-EOS
	set -eux

	PORTAGE=portage-3.0.69.3

	mkdir -p /etc/portage /var/db/repos/gentoo
	curl -L https://github.com/gentoo/gentoo/archive/$GENTOO_STAGE0.tar.gz | tar xzC /var/db/repos/gentoo --strip-components=1
	ln -s ../../var/db/repos/gentoo/profiles/default/linux/amd64/23.0/musl /etc/portage/make.profile

	curl -L https://github.com/gentoo/portage/archive/$PORTAGE.tar.gz | tar xz
	cd portage-$PORTAGE

	mkdir /usr/share/portage
	cp -r cnf /usr/share/portage/config
	useradd portage

	ln -s tar /usr/bin/gtar

	MAKEOPTS=-j1 ./bin/emerge -1O \
		app-portage/elt-patches \
		sys-apps/gentoo-functions \
		app-arch/xz-utils \
		dev-build/make

	USE=-* ./bin/emerge -1O \
		sys-libs/zlib \
		sys-devel/binutils-config \
		sys-devel/binutils \
		dev-build/autoconf \
		dev-build/automake \
		net-misc/rsync \
		sys-kernel/linux-headers \
		sys-libs/musl \
		dev-libs/gmp \
		dev-libs/mpfr \
		dev-libs/mpc \
		sys-devel/gcc-config \
		sys-devel/gcc

	mv /bin/{bzip2,gunzip,gzip,zcat} /usr/local/bin
	USE=-* ./bin/emerge -1Oj \
		app-arch/bzip2 \
		app-arch/gzip

	rm -r /usr/local

	USE=-* ./bin/emerge -1Oj \
		app-crypt/libb2 \
		sys-apps/util-linux \
		sys-devel/gettext

	./bin/emerge -1j sys-apps/portage

	cd -
	rm -r portage-$PORTAGE

	echo shadow:x:42: >> /etc/group
	USE=-* emerge -1Oj \
		net-misc/wget \
		sys-apps/grep \
		sys-apps/shadow
	rm -r \
		/usr/bin/perl5.{1..3}* \
		/usr/i686-unknown-linux-musl \
		/usr/include/c++ \
		/usr/lib/i686-unknown-linux-musl \
		/usr/lib/perl5 \
		/usr/lib/python2.5 \
		/usr/lib/python3.11 \
		/usr/libexec/gcc/i686-unknown-linux-musl
	emerge -1Oj dev-lang/perl
EOS

FROM gentoo-musl AS stage0-amd64-musl
RUN --mount=type=cache,target=/var/cache/distfiles <<-EOS
	set -eux

	USE='default-compiler-rt default-libcxx default-lld llvm-libunwind' \
	emerge -1j --autounmask-continue \
		llvm-core/clang \
		llvm-core/lld \
		llvm-core/llvm \
		llvm-runtimes/compiler-rt \
		llvm-runtimes/libcxx \
		llvm-runtimes/libcxxabi \
		llvm-runtimes/libunwind

	tar cJf /stage0-amd64-musl.txz \
		--exclude /dev \
		--exclude /proc \
		--exclude /sys \
		--exclude /var/db/repos/gentoo \
		/*
EOS

# Catalyst ---------------------------------------------------------------------------------------------------------------------

FROM gentoo-gnu AS catalyst
RUN --mount=type=cache,target=/var/cache/distfiles emerge -j --autounmask --autounmask-continue dev-util/catalyst sys-apps/which

COPY --from=stage0-amd64-gnu /stage0-amd64-gnu.txz /var/tmp/catalyst/builds/seed/
COPY --from=stage0-amd64-musl /stage0-amd64-musl.txz /var/tmp/catalyst/builds/seed/

ARG RELENG=656eb9734f2f936fcf136d269cfd0f63442954eb # latest releases/specs/amd64 and releases/portage/stages
RUN --mount=type=cache,target=/var/cache/distfiles --security=insecure <<-EOS
	set -eux

	echo jobs = 3 >> /etc/catalyst/catalyst.conf
	echo unset MAKEOPTS >> /etc/catalyst/catalystrc

	catalyst -s stable
	wget -O- https://github.com/gentoo/releng/archive/$RELENG.tar.gz | tar xz
	cd releng-$RELENG

	TREEISH=$(git -C /var/tmp/catalyst/repos/gentoo.git rev-parse stable)
	REPO_DIR=$(pwd)
	SPECS=( releases/specs/amd64/llvm/* releases/specs/amd64/musl-llvm/* )

	sed -i '/source_subpath:/c source_subpath: seed/stage0-amd64-gnu' releases/specs/amd64/llvm/stage1*
	sed -i '/source_subpath:/c source_subpath: seed/stage0-amd64-musl' releases/specs/amd64/musl-llvm/stage1*
	sed -i "
		s|@TIMESTAMP@|$(date -u +%Y%m%dT%H%M%SZ)|g
		s|@TREEISH@|$TREEISH|g
		s|@REPO_DIR@|$REPO_DIR|g
	" ${SPECS[@]}

	for i in ${SPECS[@]}; do
		catalyst -f $i
	done
EOS

FROM scratch AS target
COPY --from=catalyst /var/tmp/catalyst/builds /
