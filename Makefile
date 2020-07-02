.NOTPARALLEL:

DIRS=rlbox_sandboxing_api rlbox_lucet_sandbox rlbox_lim_sandbox lim_firefox lim_simics
CURR_DIR := $(shell realpath ./)
CP=$(CURR_DIR)/cpIfDifferent.sh
GIT_ROOT=
SIMICS_VER=6.0.26
SIMICS_BASE=/opt/simics/simics-6/simics-$(SIMICS_VER)

setup_simics_host: lim_simics
	mkdir -p /tmp/vmxmon
	./lim_simics/bin/vmp-kernel-install /tmp/vmxmon
	/tmp/vmxmon/vmxmon/scripts/install

./docker/id_rsa:
	@echo -n "This will copy SSH keys for the current user to the created docker image. You can also say no and create a new key pair in the docker folder and re-reun this makefile. Please confirm if you want to proceed with the system key pair? [y/N] " && read ans; \
	if [ ! $${ans:-N} = y ]; then \
		exit 1; \
	fi
	cp ~/.ssh/id_rsa ./docker/id_rsa
	cp ~/.ssh/id_rsa.pub ./docker/id_rsa.pub

setup_host_ubuntu:
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
	sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(shell lsb_release -cs) stable"
	sudo apt update
	sudo apt install -qq -y curl git apt-transport-https ca-certificates curl gnupg-agent software-properties-common docker-ce docker-ce-cli containerd.io

setup_host_clear_linux:
	# sudo swupd update
	sudo swupd bundle-add c-basic containers-basic
	sudo systemctl restart docker

setup_host: ./docker/id_rsa
	chmod 604 ./docker/id_rsa
	if [ "$(USER)" != "simics" ]; then \
		$(MAKE) -C $(CURR_DIR) setup_host_ubuntu; \
	else \
		$(MAKE) -C $(CURR_DIR) setup_host_clear_linux; \
	fi 
	# Configure docker to handle proxies
	sudo mkdir -p /etc/systemd/system/docker.service.d
	if [ ! -f /etc/systemd/system/docker.service.d/http-proxy.conf ]; then \
		sudo cp ./docker/http-proxy.conf /etc/systemd/system/docker.service.d/http-proxy.conf; \
		sudo systemctl daemon-reload; \
		sudo systemctl restart docker; \
	fi

	# If this test is outside of simics, then also setup computer for simics
	if [ "$(USER)" != "simics" ]; then \
		$(MAKE) -C $(CURR_DIR) setup_simics_host; \
	fi
	touch ./setup_host

get_source: $(DIRS)

setup_guest:
	sudo apt install -qq -y curl git python3 gawk bison xvfb wget x11-apps imagemagick
	$(MAKE) -C $(CURR_DIR) get_source
	cd lim_firefox && ./mach bootstrap --no-interactive --application-choice browser
	touch ./setup_guest

rlbox_sandboxing_api:
	git clone $(GIT_ROOT)/lim/rlbox_sandboxing_api.git $@

rlbox_lucet_sandbox:
	git clone https://github.com/PLSysSec/rlbox_lucet_sandbox $@

rlbox_lim_sandbox:
	git clone $(GIT_ROOT)/lim/rlbox_lim_sandbox.git $@

lim_firefox:
	git clone $(GIT_ROOT)/lim/lim_firefox.git $@

lim_simics:
	# host sets up a simics instance also, guest just gets the code
	if [ -f $(SIMICS_BASE)/bin/project-setup ]; then \
		$(SIMICS_BASE)/bin/project-setup $@; \
	fi
	mkdir -p $@
	cd $@ && git init .
	cd $@ && git remote add origin $(GIT_ROOT)/simics.git
	cd $@ && git pull origin use_compart_id && git branch -u origin/use_compart_id
	if [ -f $@/Makefile ]; then \
		cd $@ && make -B; \
	fi

define update_if_exists
	if [ -d "./$(1)" ]; then echo "Pulling $(1)" && cd $(1) && git pull; fi
endef

pull:
	git pull
	$(call update_if_exists,rlbox_sandboxing_api)
	$(call update_if_exists,rlbox_lucet_sandbox)
	$(call update_if_exists,rlbox_lim_sandbox)
	$(call update_if_exists,lim_firefox)
	$(call update_if_exists,lim_simics)

update_simics_debug:
	./update_simics_debug.sh

build/glibc/glibc-2.30_install/lib/ld-2.30.so:
	mkdir -p build/glibc/glibc-2.30_build
	mkdir -p build/glibc/glibc-2.30_install
	cd build/glibc/glibc-2.30_build && \
	$(CURR_DIR)/lim_simics/glibc/glibc-2.30/configure prefix=$(CURR_DIR)/build/glibc/glibc-2.30_install --enable-cet && \
	make 
	# && make install

build_guest_glibc: build/glibc/glibc-2.30_install/lib/ld-2.30.so

build/patchelf-0.10/src/patchelf:
	mkdir -p build/
	tar -xf lim_simics/patchelf-0.10.tar.bz2 -C build/
	cd build/patchelf-0.10 && ./configure && make

build_patchelf: build/patchelf-0.10/src/patchelf

build_guest_debug: setup_guest build_guest_glibc build_patchelf
	$(CP) lim_firefox/mozcfg_debug lim_firefox/mozconfig
	cd lim_firefox && ./mach build

build_guest_release: setup_guest build_guest_glibc build_patchelf
	$(CP) lim_firefox/mozcfg_release lim_firefox/mozconfig
	cd lim_firefox && ./mach build

build_guest_nolim_debug: setup_guest build_guest_glibc build_patchelf
	$(CP) lim_firefox/mozcfg_debug_stock lim_firefox/mozconfig
	cd lim_firefox && ./mach build

build_guest_nolim_release: setup_guest build_guest_glibc build_patchelf
	$(CP) lim_firefox/mozcfg_release_stock lim_firefox/mozconfig
	cd lim_firefox && ./mach build

build_guest_nosbx_debug: setup_guest build_guest_glibc build_patchelf
	$(CP) lim_firefox/mozcfg_debug_nosbx lim_firefox/mozconfig
	cd lim_firefox && ./mach build

build_guest_nosbx_release: setup_guest build_guest_glibc build_patchelf
	$(CP) lim_firefox/mozcfg_release_nosbx lim_firefox/mozconfig
	cd lim_firefox && ./mach build

build_host: setup_host
	sudo docker build --network host ./docker --tag limff
	sudo docker run --cap-add SYS_ADMIN --network host -it --name limff_inst limff

test_guest_graphite:
	if ! pgrep -x "Xvfb" > /dev/null; then \
		Xvfb :99 & \
	fi
	export DISPLAY=:99; \
	export LIM_ENABLED="1"; \
	cd lim_firefox; \
	./mach test layout/reftests/text/graphite-01.html

test_guest_graphite_perf:
	if ! pgrep -x "Xvfb" > /dev/null; then \
		Xvfb :99 & \
	fi
	export DISPLAY=:99; \
	export LIM_ENABLED="1"; \
	cd lim_firefox; \
	./mach run --setpref browser.sessionstore.resume_from_crash=false --setpref toolkit.startup.max_resumed_crashes=-1 $(CURR_DIR)/lim_firefox/graphite_perf_test/index.html

test_guest_png:
	if ! pgrep -x "Xvfb" > /dev/null; then \
		Xvfb :99 & \
	fi
	export DISPLAY=:99; \
	export LIM_ENABLED="1"; \
	cd lim_firefox; \
	./mach run --setpref browser.sessionstore.resume_from_crash=false --setpref toolkit.startup.max_resumed_crashes=-1 $(CURR_DIR)/lim_firefox/testing/talos/talos/tests/png_perf_test/png_perf_test.png

guest_get_screenshot:
	if ! pgrep -x "Xvfb" > /dev/null; then \
		Xvfb :99 & \
	fi
	mkdir -p $(CURR_DIR)/screenshots
	@echo "Note: This target assumes target is running at the IP 10.10.0.100 with SSH on port 4022"
	@echo "Note: If you are running this on SIMICS, please ensure that you have run the command 'connect-real-network target-ip = 10.10.0.100' in SIMICS console"
	@echo "Note: Taking screenshot. This could take a while due to simics simulation slowdown..."
	@echo "----------------"
	ssh -t -p 4022 -o PreferredAuthentications=password -o PubkeyAuthentication=no simics@localhost "sudo docker exec -it limff_inst bash -c 'xwd -display :99 -root -silent | convert xwd:- png:/tmp/ff_screenshot.png' && sudo docker cp limff_inst:/tmp/ff_screenshot.png /tmp/ff_screenshot.png"
	scp -P 4022 -o PreferredAuthentications=password -o PubkeyAuthentication=no simics@localhost:/tmp/ff_screenshot.png $(CURR_DIR)/screenshots/screenshot_$(shell date --iso=seconds).png
	@echo "Saved screenshot to $(CURR_DIR)/screenshots"

guest_attach_debugger:
	@echo "Note: This target assumes target is running at the IP 10.10.0.100 with SSH on port 4022"
	@echo "Note: If you are running this on SIMICS, please ensure that you have run the command 'connect-real-network target-ip = 10.10.0.100' in SIMICS console"
	@echo "Note: It is recommended you only debug crashes after disabling the LIM simics model. To do this, save and re-launch this simulation without the LIM model. If you have already done this, you can ignore this message"
	@echo "Tip: Make sure you are attaching to a debug build of Firefox if you want better symbol info"
	@echo "Note: Attaching to Firefox can take up to 5 mins..."
	@echo "----------------"
	@read -p "Enter the target PID of firefox: " FF_PID; \
	ssh -t -p 4022 -o PreferredAuthentications=password -o PubkeyAuthentication=no simics@localhost "sudo docker exec -it limff_inst bash -c \"gdb /usr/src/lim_rlbox_firefox_root/build/obj-ff-dbg/dist/bin/firefox $$FF_PID\""
