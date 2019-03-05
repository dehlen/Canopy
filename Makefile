.PHONY: all

all:
	docker run --rm \
	    --volume "$(shell pwd):/package" \
	    --workdir "/package" \
	    canopy \
	    /bin/bash -c \
	    "swift build -Xswiftc -suppress-warnings -c release"
	scp -i ~/.ssh/znc.pem -C .build/x86_64-unknown-linux/release/debris ubuntu@canopy.codebasesaga.com:src/debris.new
	ssh -i ~/.ssh/znc.pem ubuntu@canopy.codebasesaga.com "cd src && mv debris debris.backup && mv debris.new debris && sudo systemctl restart debris"
