# syntax=docker/dockerfile:1-labs

FROM alpine AS guix-base
ARG GUIX_COMMIT=455805beda4417b329f26522fde4f0a88c2e211e # latest gnu/packages/commencement.scm
RUN <<-EOS
	apk add guix
	# update guix
	apk add autoconf automake gcc gettext-dev git guile-dev guix libc-dev make
	wget -O- https://codeberg.org/guix/guix-mirror/archive/$GUIX_COMMIT.tar.gz | tar xz
	cd guix-mirror
	truncate -s0 doc/local.mk
	./bootstrap
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --disable-daemon
	make -j$(nproc) install
EOS

FROM guix-base AS guix
ARG FULL_BOOTSTRAP
RUN <<-EOS
	[ $FULL_BOOTSTRAP ] && ARGS='--no-substitutes'
	guix-daemon --build-users-group=guixbuild --disable-chroot &
	guix package -p /guix-profile --bootstrap --no-grafts $ARGS -i \
		gcc-toolchain@11 make wget sed xz bzip2 gzip patch m4 bison coreutils findutils tar grep gawk bash
EOS

FROM scratch AS prefix
ARG GENTOO_PREFIX_COMMIT=2f8ee0fa8c22fc1f4d5b0499b3ae97857c5b4d3d # latest scripts/bootstrap-prefix.sh
COPY --from=guix /gnu/store /gnu/store
COPY --from=guix /guix-profile /
COPY --from=guix /guix-profile /usr
RUN <<-EOS
	. /etc/profile
	echo 'root::0:0:::' > /etc/passwd # for stage1 prefix-portage-3.0.56.1

	wget --no-check-certificate \
		https://github.com/gentoo/prefix/raw/$GENTOO_PREFIX_COMMIT/scripts/bootstrap-prefix.sh
	sed -i '
		2712 { /exit 1/d }        # I am root
		2739 { /LIBRARY_PATH/d }  # fix guix
	' bootstrap-prefix.sh

	bash bootstrap-prefix.sh /prefix wget # fix stage2 binutils make segv
	bash bootstrap-prefix.sh /prefix stage1
	# todo:
	#bash bootstrap-prefix.sh /prefix stage2
	#bash bootstrap-prefix.sh /prefix stage3

	# todo: remove
	echo . /etc/profile > .bashrc
	cat > /.bashrc <<-EOF
		. /etc/profile
		alias bootstrap='bash /bootstrap-prefix.sh /prefix'
	EOF
EOS
ENTRYPOINT ["bash"]

# todo: remove
FROM alpine AS stage3-dl
RUN <<-EOS
	DIR=https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-openrc
	BASE=$(wget -O- $DIR/latest-stage3-amd64-openrc.txt | awk '/stage3/ { print $1 }')
	mkdir /stage3
	wget -O stage3.txz $DIR/$BASE
	tar xJf stage3.txz -C /stage3
EOS

FROM scratch AS catalyst-base
COPY --from=stage3-dl /stage3 /
COPY --from=stage3-dl /stage3.txz /var/tmp/catalyst/builds/seed/
RUN <<-EOS
	emerge-webrsync
	emerge --autounmask --autounmask-continue dev-util/catalyst
EOS
RUN <<-EOS
	cat >> /etc/catalyst/catalyst.conf <<-EOF
		jobs = $(nproc)
		load-average = $(nproc)
		var_tmpfs_portage = 16
	EOF
EOS
ENTRYPOINT ["bash"]

FROM catalyst-base AS catalyst
RUN --security=insecure <<-EOS
	catalyst -s stable
	TREEISH=$(git -C /var/tmp/catalyst/repos/gentoo.git rev-parse stable)

	# seed stage4 for llvm
	cat > stage4-llvm-seed.spec <<-EOF
		subarch: amd64
		version_stamp: llvm
		target: stage4
		rel_type: seed
		source_subpath: seed/stage3
		profile: default/linux/amd64/23.0
		snapshot_treeish: $TREEISH
		stage4/packages:
		  llvm-core/clang
		  llvm-core/lld
		  llvm-core/llvm
		  llvm-runtimes/compiler-rt
		  llvm-runtimes/libcxx
		  llvm-runtimes/libcxxabi
		  llvm-runtimes/libunwind
	EOF
	catalyst -f stage4-llvm-seed.spec
EOS

ARG GENTOO_RELENG_COMMIT=c622211a2f847d473199e597d95eaf55cbbe40b2
RUN --security=insecure <<-EOS
	TREEISH=$(git -C /var/tmp/catalyst/repos/gentoo.git rev-parse stable)

	wget -O- https://github.com/gentoo/releng/archive/$GENTOO_RELENG_COMMIT.tar.gz | tar xz
	REPO_DIR=$(pwd)/releng-$GENTOO_RELENG_COMMIT
	SPECS=($REPO_DIR/releases/specs/amd64/llvm/stage?-openrc-23.spec)
	sed -i "
		s|@REPO_DIR@|$REPO_DIR|g
		s|@TIMESTAMP@|$(date -u +%Y%m%dT%H%M%SZ)|g
		s|@TREEISH@|$TREEISH|g
	" ${SPECS[@]}
	sed -i '/source/c\source_subpath: seed/stage4-amd64-llvm' $SPECS
	for i in ${SPECS[@]}; do
		catalyst -f $i
	done
EOS

FROM scratch
COPY --from=catalyst /var/tmp/catalyst/builds /
