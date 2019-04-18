.PHONY: all

all:
	docker run --rm \
	    --volume "$(shell pwd):/package" \
	    --workdir "/package" \
	    canopy \
	    /bin/bash -c \
	    "swift build --build-path .build-linux -Xswiftc -suppress-warnings -c release"
	git checkout Package.resolved
	scp -i ~/.ssh/znc.pem -C .build-linux/x86_64-unknown-linux/release/debris ubuntu@canopy.mxcl.dev:src/debris.new
	ssh -i ~/.ssh/znc.pem ubuntu@canopy.mxcl.dev "cd src && mv debris debris.backup && mv debris.new debris && sudo systemctl restart debris && journalctl -fu debris"
