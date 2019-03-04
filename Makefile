.PHONY: all

all:
	docker run --rm \
	    --volume "$(shell pwd):/package" \
	    --workdir "/package" \
	    canopy \
	    /bin/bash -c \
	    "swift build -Xswiftc -suppress-warnings -c release"
	scp .build/x86_64-unknown-linux/release/debris canopy:src
	ssh canopy "sudo systemctl restart debris"
