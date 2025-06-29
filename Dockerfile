# syntax=docker/dockerfile:1-labs

FROM alpine AS live-bootstrap-src
ARG LIVE_BOOTSTRAP_TREEISH=f2d7fda4601236656c8d3243845375ba1c1ad6d9
RUN <<-EOS
	apk add git

	mkdir live-bootstrap
	cd live-bootstrap
	git init
	git remote add origin https://github.com/fosslinux/live-bootstrap
	git fetch origin $LIVE_BOOTSTRAP_TREEISH
	git reset --hard FETCH_HEAD
	git submodule update --init --recursive

	{
		# todo: ええ感じにする
		mkdir -p distfiles
		wget -P distfiles \
			https://files.bootstrapping.world/coreutils-9.4.tar.xz \
			https://files.bootstrapping.world/gnulib-30820c.tar.gz \
			https://files.bootstrapping.world/gnulib-8e128e.tar.gz \
			https://files.bootstrapping.world/gnulib-d279bc.tar.gz \
			https://files.bootstrapping.world/gnulib-3639c57.tar.gz \
			https://files.bootstrapping.world/gnulib-5651802.tar.gz \
			https://files.bootstrapping.world/gnulib-5d2fe24.tar.gz \
			https://files.bootstrapping.world/gnulib-672663a.tar.gz \
			https://files.bootstrapping.world/gnulib-7daa86f.tar.gz \
			https://files.bootstrapping.world/gnulib-a521820.tar.gz \
			https://files.bootstrapping.world/gnulib-b28236b.tar.gz \
			https://files.bootstrapping.world/gnulib-b81ec69.tar.gz \
			https://files.bootstrapping.world/gnulib-bb5bb43.tar.gz \
			https://files.bootstrapping.world/gnulib-d271f86.tar.gz \
			https://files.bootstrapping.world/gnulib-e017871.tar.gz \
			https://files.bootstrapping.world/gnulib-356a414e.tar.gz \
			https://files.bootstrapping.world/gnulib-52a06cb3.tar.gz \
			https://files.bootstrapping.world/gnulib-8f4538a5.tar.gz \
			https://files.bootstrapping.world/gnulib-901694b9.tar.gz
	}
	sed -i 's/curl.*true$/wget "$url" -O "$dest_path" || true/' download-distfiles.sh
	sh download-distfiles.sh

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
		BARE_METAL=False
		DISK=hoge
		KERNEL_BOOTSTRAP=False
		BUILD_KERNELS=False
		CONFIGURATOR=False
		MIRRORS_LEN=0
	EOF

	mkdir -p /rootfs/external
	mv distfiles /rootfs/external
	mv seed/stage0-posix/* seed/*.* steps /rootfs
	ls /rootfs > /rootfs/srcs
	cat >> /rootfs/srcs <<-EOF
		configurator
		hex0
		kaem
		preseed-jump.kaem
		script-generator
		seed-full.kaem
	EOF
EOS

FROM scratch AS live-bootstrap
COPY --from=live-bootstrap-src /rootfs /
# from 181 bytes hex0-seed
# cf. https://github.com/oriansj/bootstrap-seeds/tree/cedec6b8066d1db229b6c77d42d120a23c6980ed/POSIX/x86
RUN ["/bootstrap-seeds/POSIX/x86/hex0-seed", "/bootstrap-seeds/POSIX/x86/hex0_x86.hex0", "/hex0"]
RUN ["/hex0", "/bootstrap-seeds/POSIX/x86/kaem-minimal.hex0", "/kaem"]
RUN ["/kaem"]
ENTRYPOINT ["/bin/bash"]

#-------------------------------------------------------------------------------------------------------------------------------
# GNU
#-------------------------------------------------------------------------------------------------------------------------------

FROM live-bootstrap AS x86_64-pc-linux-gnu
RUN <<-EOS
	TARGET=x86_64-pc-linux-gnu

	# merge-usr
	ln -s usr/lib64 /lib64

	mkdir bootstrap-64
	(
		cd bootstrap-64

		# 先に32bit環境でコンパイルしておく
		curl -L https://ftp.gnu.org/gnu/wget/wget-1.25.0.tar.gz | tar xz
		cd wget-1.25.0
		./configure --prefix=/usr --with-ssl=openssl --with-libssl-prefix=/usr/ssl
		make -j$(nproc) install
		cd -

		# todo: fix gcc default search path
		mkdir -p /usr/local/$TARGET
		ln -s /usr/{include,lib,lib64} /usr/local/$TARGET

		tar xf /external/distfiles/binutils-2.41.tar.xz
		cd binutils-2.41
		./configure --target=$TARGET --disable-gprofng
		make -j$(nproc)
		make install
		cd -

		tar xf /external/distfiles/gcc-13.3.0.tar.xz
		mkdir gcc-13.3.0/build-gcc
		cd gcc-13.3.0/build-gcc
		# --disable-shared and --disable-threads are for libgcc
		../configure --target=$TARGET \
			--enable-languages=c,c++ \
			--disable-libatomic \
			--disable-libgomp \
			--disable-libquadmath \
			--disable-libssp \
			--disable-libstdcxx \
			--disable-libvtv \
			--disable-shared \
			--disable-threads
		make -j$(nproc)
		make install
		cd -

		curl -L https://ftp.gnu.org/gnu/glibc/glibc-2.41.tar.xz | tar xJ
		mkdir glibc-2.41/build-32
		cd glibc-2.41/build-32
		../configure --prefix=/usr --host=i686-pc-linux-gnu \
			CC="$TARGET-gcc -m32" CXX="$TARGET-g++ -m32"
		make -j$(nproc)
		make install
		cd -
		mkdir glibc-2.41/build-64
		cd glibc-2.41/build-64
		../configure --prefix=/usr --host=$TARGET
		make -j$(nproc)
		make install
		cd -

		mkdir gcc-13.3.0/build-libstdc++
		cd gcc-13.3.0/build-libstdc++
		../libstdc++-v3/configure --prefix=/usr --host=$TARGET --disable-multilib
		make -j$(nproc) install
		cd -
	)
	rm -r bootstrap-64

	xargs -i rm -r "{}" < srcs
EOS

FROM x86_64-pc-linux-gnu AS gentoo-gnu
ARG GENTOO_BOOTSTRAP_TREEISH=fb43ec2626a129459b87e33cc57fb62759226ba6 # 2025-06-28 07:22:46 UTC
ARG PORTAGE_BOOTSTRAP_TREEISH=portage-3.0.68
RUN <<-EOS
	mkdir -p /var/db/repos/gentoo
	curl -L https://github.com/gentoo-mirror/gentoo/archive/$GENTOO_BOOTSTRAP_TREEISH.tar.gz \
		| tar xzC /var/db/repos/gentoo --strip-components=1

	mkdir -p /etc/portage
	ln -s ../../var/db/repos/gentoo/profiles/default/linux/amd64/23.0 /etc/portage/make.profile

	curl -L https://github.com/gentoo/portage/archive/$PORTAGE_BOOTSTRAP_TREEISH.tar.gz | tar xz
	(
		cd portage-$PORTAGE_BOOTSTRAP_TREEISH

		mkdir /usr/share/portage
		cp -r $(pwd)/cnf /usr/share/portage/config
		useradd portage

		# live-bootstrap's 32bit make is not usable with -jN
		MAKEOPTS=-j1 ./bin/emerge -1O \
			app-portage/elt-patches \
			sys-apps/gentoo-functions \
			app-arch/xz-utils \
			dev-build/make

		USE='-* openmp' ./bin/emerge -1O \
			dev-build/autoconf \
			dev-build/autoconf-wrapper \
			dev-build/automake \
			dev-build/automake-wrapper \
			sys-libs/zlib \
			dev-libs/gmp \
			dev-libs/mpfr \
			dev-libs/mpc \
			net-misc/rsync \
			sys-kernel/linux-headers \
			sys-devel/binutils-config \
			sys-devel/binutils \
			sys-devel/gcc-config \
			sys-devel/gcc
		rm -r /usr/local

		# for python
		mkdir -p /usr/local/bin
		mv /usr/bin/bzip2 /usr/local/bin
		./bin/emerge -1Oj app-arch/bzip2
		rm /usr/local/bin/bzip2

		USE='-* ssl' ./bin/emerge -1O \
			sys-apps/util-linux \
			dev-libs/expat \
			dev-libs/libffi \
			dev-libs/openssl \
			dev-util/pkgconf \
			dev-lang/python \
			dev-lang/python-exec
		./bin/emerge -1O sys-libs/glibc

		# fix sys-apps/coreutils
		rm /usr/include/stropts.h

		# fix profile
		USE=-* ./bin/emerge -1Oj \
			sys-devel/gettext \
			sys-libs/libcap
		./bin/emerge -1Oj \
			sys-libs/libxcrypt

		./bin/emerge -1j sys-apps/portage
	)
	rm -r portage-$PORTAGE_BOOTSTRAP_TREEISH

	# moving to 64bit
	mv /usr/bin/{bc,dc,gunzip,gzip,zcat} /usr/local/bin
	USE=-* emerge -1Oj \
		app-arch/gzip \
		net-misc/wget \
		sys-apps/diffutils \
		sys-apps/gawk \
		sys-apps/shadow \
		sys-devel/bc
	rm /usr/local/bin/{bc,dc,gunzip,gzip,zcat}

	# diet
	rm -r \
		/var/cache/* \
		/usr/lib/i386-unknown-linux-musl \
		/usr/libexec/gcc/i386-unknown-linux-musl \
		/usr/lib/python3.11
EOS

FROM gentoo-gnu AS gentoo-gnu-tarball
RUN <<-EOS
	emerge -1j \
		llvm-core/clang \
		llvm-core/lld \
		llvm-core/llvm \
		llvm-runtimes/compiler-rt \
		llvm-runtimes/libcxx \
		llvm-runtimes/libcxxabi \
		llvm-runtimes/libunwind
	rm -r /var/cache/*

	tar cJf /gentoo-gnu.txz \
		--exclude /dev \
		--exclude /proc \
		--exclude /sys \
		--exclude /var/db/repos/* \
		/*
EOS

FROM gentoo-gnu AS catalyst-base-gnu
RUN emerge -j --autounmask --autounmask-continue dev-util/catalyst
COPY --from=gentoo-gnu-tarball /gentoo-gnu.txz /var/tmp/catalyst/builds/seed/

FROM catalyst-base-gnu AS catalyst-gnu
ARG GENTOO_RELENG_TREEISH=8d228cd6a6912d15e7d0a669fadf9732ab3c1018 # latest specs and confdir
RUN --security=insecure <<-EOS
	cat >> /etc/catalyst/catalyst.conf <<-EOF
		jobs = $(nproc)
		load-average = $(nproc)
		var_tmpfs_portage = 16
	EOF

	catalyst -s stable
	TREEISH=$(git -C /var/tmp/catalyst/repos/gentoo.git rev-parse stable)

	wget -O- https://github.com/gentoo/releng/archive/$GENTOO_RELENG_TREEISH.tar.gz | tar xz
	REPO_DIR=$(pwd)/releng-$GENTOO_RELENG_TREEISH
	SPECS=($REPO_DIR/releases/specs/amd64/llvm/stage?-openrc-23.spec)

	sed -i '/source/c\source_subpath: seed/gentoo-gnu' $SPECS
	sed -i "
		s|@REPO_DIR@|$REPO_DIR|g
		s|@TIMESTAMP@|$(date -u +%Y%m%dT%H%M%SZ)|g
		s|@TREEISH@|$TREEISH|g
	" ${SPECS[@]}

	for i in ${SPECS[@]}; do
		catalyst -f $i
	done
EOS

FROM scratch AS target-gnu
COPY --from=catalyst-gnu /var/tmp/catalyst/builds /

#-------------------------------------------------------------------------------------------------------------------------------
# musl
#-------------------------------------------------------------------------------------------------------------------------------

FROM live-bootstrap AS x86_64-pc-linux-musl
RUN <<-EOS
	TARGET=x86_64-pc-linux-musl

	mkdir bootstrap-64
	(
		cd bootstrap-64

		# 先に32bit環境でコンパイルしておく
		curl -L https://ftp.gnu.org/gnu/wget/wget-1.25.0.tar.gz | tar xz
		cd wget-1.25.0
		./configure --prefix=/usr --with-ssl=openssl --with-libssl-prefix=/usr/ssl
		make -j$(nproc) install
		cd -

		# todo: fix gcc default search path
		mkdir -p /usr/local/$TARGET
		ln -s /usr/{include,lib} /usr/local/$TARGET

		tar xf /external/distfiles/binutils-2.41.tar.xz
		cd binutils-2.41
		./configure --target=$TARGET --disable-gprofng
		make -j$(nproc)
		make install
		cd -

		tar xf /external/distfiles/gcc-13.3.0.tar.xz
		mkdir gcc-13.3.0/build-gcc
		cd gcc-13.3.0/build-gcc
		# --disable-shared and --disable-threads are for libgcc
		../configure --target=$TARGET \
			--enable-languages=c,c++ \
			--disable-libatomic \
			--disable-libgomp \
			--disable-libquadmath \
			--disable-libssp \
			--disable-libstdcxx \
			--disable-libvtv \
			--disable-shared \
			--disable-threads
		make -j$(nproc)
		make install
		cd -

		tar xf /external/distfiles/musl-1.2.5.tar.gz
		cd musl-1.2.5
		./configure --prefix=/usr --host=$TARGET
		make -j$(nproc) install
		cd -

		mkdir gcc-13.3.0/build-libstdc++
		cd gcc-13.3.0/build-libstdc++
		../libstdc++-v3/configure --prefix=/usr --host=$TARGET --disable-multilib
		make -j$(nproc) install
		mv /usr/lib64/libs??c++* /usr/lib # for bfd
		cd -
	)
	rm -r bootstrap-64

	xargs -i rm -r "{}" < srcs
EOS

FROM x86_64-pc-linux-musl AS gentoo-musl
ARG GENTOO_BOOTSTRAP_TREEISH=fb43ec2626a129459b87e33cc57fb62759226ba6 # 2025-06-28 07:22:46 UTC
ARG PORTAGE_BOOTSTRAP_TREEISH=portage-3.0.68
RUN <<-EOS
	mkdir -p /var/db/repos/gentoo
	curl -L https://github.com/gentoo-mirror/gentoo/archive/$GENTOO_BOOTSTRAP_TREEISH.tar.gz \
		| tar xzC /var/db/repos/gentoo --strip-components=1

	mkdir -p /etc/portage
	ln -s ../../var/db/repos/gentoo/profiles/default/linux/amd64/23.0/musl /etc/portage/make.profile

	curl -L https://github.com/gentoo/portage/archive/$PORTAGE_BOOTSTRAP_TREEISH.tar.gz | tar xz
	(
		cd portage-$PORTAGE_BOOTSTRAP_TREEISH

		mkdir /usr/share/portage
		cp -r $(pwd)/cnf /usr/share/portage/config
		useradd portage

		# live-bootstrap's 32bit make is not usable with -jN
		MAKEOPTS=-j1 ./bin/emerge -1O \
			app-portage/elt-patches \
			sys-apps/gentoo-functions \
			app-arch/xz-utils \
			dev-build/make

		USE='-* openmp' ./bin/emerge -1O \
			sys-libs/musl \
			sys-libs/zlib \
			dev-libs/gmp \
			dev-libs/mpfr \
			dev-libs/mpc \
			sys-devel/binutils-config \
			sys-devel/binutils \
			sys-devel/gcc-config \
			sys-devel/gcc
		rm -r /usr/local
		rm /usr/lib/libs??c++*

		# for python
		mkdir -p /usr/local/bin
		mv /usr/bin/bzip2 /usr/local/bin
		./bin/emerge -1O app-arch/bzip2
		rm /usr/local/bin/bzip2

		# fix profile
		USE=-* ./bin/emerge -1O \
			dev-build/autoconf \
			dev-build/autoconf-wrapper \
			dev-build/automake \
			dev-build/automake-wrapper \
			net-misc/rsync \
			sys-kernel/linux-headers \
			sys-apps/util-linux \
			sys-devel/gettext

		./bin/emerge -1j sys-apps/portage
	)
	rm -r portage-$PORTAGE_BOOTSTRAP_TREEISH

	# moving to 64bit
	mv /usr/bin/{gunzip,gzip,zcat} /usr/local/bin
	USE=-* emerge -1Oj \
		app-arch/gzip \
		net-misc/wget \
		sys-apps/diffutils \
		sys-apps/shadow
	rm /usr/local/bin/{gunzip,gzip,zcat}

	# diet
	rm -r \
		/var/cache/* \
		/usr/lib/i386-unknown-linux-musl \
		/usr/libexec/gcc/i386-unknown-linux-musl \
		/usr/lib/python3.11
EOS

FROM gentoo-musl AS gentoo-musl-llvm-tarball
RUN <<-EOS
	emerge -1j \
		llvm-core/clang \
		llvm-core/lld \
		llvm-core/llvm \
		llvm-runtimes/compiler-rt \
		llvm-runtimes/libcxx \
		llvm-runtimes/libcxxabi \
		llvm-runtimes/libunwind
	rm -r /var/cache/*

	tar cJf /gentoo-musl.txz \
		--exclude /dev \
		--exclude /proc \
		--exclude /sys \
		--exclude /var/db/repos/* \
		/*
EOS

FROM gentoo-musl AS catalyst-musl
RUN emerge -j --autounmask --autounmask-continue dev-util/catalyst
COPY --from=gentoo-musl-llvm-tarball /gentoo-musl.txz /var/tmp/catalyst/builds/seed/

ARG GENTOO_RELENG_TREEISH=8d228cd6a6912d15e7d0a669fadf9732ab3c1018 # latest specs and confdir
RUN --security=insecure <<-EOS
	cat >> /etc/catalyst/catalyst.conf <<-EOF
		jobs = $(nproc)
		load-average = $(nproc)
		var_tmpfs_portage = 16
	EOF

	catalyst -s stable
	TREEISH=$(git -C /var/tmp/catalyst/repos/gentoo.git rev-parse stable)

	wget -O- https://github.com/gentoo/releng/archive/$GENTOO_RELENG_TREEISH.tar.gz | tar xz
	REPO_DIR=$(pwd)/releng-$GENTOO_RELENG_TREEISH
	SPECS=($REPO_DIR/releases/specs/amd64/musl-llvm/stage?-23.spec)

	sed -i '/source/c\source_subpath: seed/gentoo-musl' $SPECS
	sed -i "
		s|@REPO_DIR@|$REPO_DIR|g
		s|@TIMESTAMP@|$(date -u +%Y%m%dT%H%M%SZ)|g
		s|@TREEISH@|$TREEISH|g
	" ${SPECS[@]}

	for i in ${SPECS[@]}; do
		catalyst -f $i
	done
EOS

FROM scratch AS target-musl
COPY --from=catalyst-musl /var/tmp/catalyst/builds /
