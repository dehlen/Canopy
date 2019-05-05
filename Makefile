.PHONY: all

image = canopy
host = ubuntu@canopy.mxcl.dev

all: libs
	docker run --rm \
		--tty \
	    --volume "$(shell pwd):/package" \
	    --workdir "/package" \
	    $(image) \
	    /bin/bash -c \
	    "swift --version && swift build --build-path .build-linux -Xswiftc -suppress-warnings -c release"
	git checkout Package.resolved
	scp -i ~/.ssh/znc.pem -C .build-linux/x86_64-unknown-linux/release/debris ubuntu@canopy.mxcl.dev:src/debris.new
	ssh -i ~/.ssh/znc.pem $(host) "cd src && mv debris debris.backup && mv debris.new debris && sudo systemctl restart debris && journalctl -fu debris"


define rsync
	docker run \
		--volume $(HOME)/.ssh:/root/ssh \
		$(image) \
		rsync \
			-e "ssh -i /root/ssh/znc.pem -o StrictHostKeyChecking=no" \
			$(1) $(host):$(1) \
			--compress --delete --recursive --links --rsync-path="sudo rsync"
endef

libs:
	$(call rsync,/usr/lib/swift/)
	$(call rsync,/usr/lib/clang/)
