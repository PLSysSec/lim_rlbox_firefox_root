# Repo

This is the top level repo for the lim + rlbox integration into Firefox. This repo is self sufficient in that it will pull all required repos as part of the builds.

This repo expects sets up the Firefox inside a docker image. This docker image is then run in simulator that supports LIM. We will refer to these environments as follows

- **lab_host** - Terminal on the machine running the SIMICS software
- **host** - Terminal on the machine running the Docker image
- **guest** - Terminal in the Docker image (inside the SIMICS simulation)
- **simics** - Terminal to run the simics commands like start and stop etc.

**Important** - This repo makefile contains different targets meant for each of the the above enviroments. So all description below will explicitly state which environment to run the command in.

This repo will automatically pull in the following repos
- rlbox_sandboxing_api 
- rlbox_lim_sandbox
- lim_firefox
- lim_simics (SPR's simics repo with LIM wrappers and LIM simics model)

# Loading a build of this repo

## Via checkpoint

The recommended way to load the built code in this repo is to use an exising checkpoint if you have access to these.

To load a checkpoint simply run

```bash
./simics <path to checkpoint>
# Run the following in the simics console
enable-real-time-mode
connect-real-network target-ip = 10.10.0.100
run
```

Now in the terminal that runs is actually a "guest" terminal --- it is connected to the docker instance.

## Building from scratch

1. First clone this repo in a fresh directory and in your lab_host machine.

2. Next, it is probably a good idea to build the full repo in you lab_host machine, as this will be your dev environment. You can do this by running the command in a lab_host terminal

    ```
    make build_guest
    ```

    or alternately, you can just pull the source code with 

    ```
    make get_source
    ```

3. Make sure you have enabled VMP in your lab_host machine for simics acceleration. If you haven't already set this up, you can do this by running the following command in a lab_host terminal

    ```
    make setup_simics_host
    ```

4. Launch simics with a fresh QSP image by running the following in a lab_host terminal

    ```
    ./lim_rlbox_firefox_root/lim_simics/simics targets/qsp-x86/qsp-clear-linux.simics
    ```

5. Setup the qsp image by running the following commands in the guest_terminal.

    ```
    sudo swupd update
    sudo swupd bundle-add c-basic containers-basic
    sudo systemctl start docker
    ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa <<< y
    echo 'Add current SSH key in ~/.ssh/id_rsa to access github repos. You can do this by adding this key to you gitlab/github accounts'
    ```

6. Clone this repository in the **host** terminal with the commands

    ```
    git clone <git root>/lim/lim_rlbox_firefox_root.git
    cd lim_rlbox_firefox_root
    ```

7. Next in the host terminal run the command  `make build_host` (It took overnight to finish the builds). This basically runs a docker inside simics, pulls all the source files/directories inside docker. Then runs docker/Dockerfile script, which build debug and release firefox. Once the build is finished, you’ll see ‘build successfully finished’. Please ignore error messages like ‘channel error’

8. You can now save your checkpoint with the command shown below. You can use this checkpoint going forward.

    ```
    write-configuration -independent-checkpoint ../path_to_save/lim_firefox.ckpt
    ```

# Updating the firefox build with latest src

In the guest terminal (terminal with the green font) --- note that this is connected to the docker instance. Here you can just pull the latest code for all repos and build. Note that initial builds of Firefox take a long time, but incremental builds are quite fast.

```bash
# get latest code
make pull
```
Then either run

```
# build debug firefox that uses lim
make build_guest_debug
```

or 

```
# build release firefox  that uses lim
make build_guest_release
```

**Optional** You can also build versions of Firefox that do not use lim, but instead uses WASM or Firefox that uses neither wasm or lim. Note that these builds are not created by default when "Building from scratch", so the first time you run this command, will be very slow as it has to do a full build.

To build Firefox that uses Wasm instead of LIM, use the below commands. Note that gdb will not understand WASM modules, so debugging WASM'd code can be painful without symbols.

```
# Firefox that uses WASM instead of LIM
make build_guest_nolim_debug
make build_guest_nolim_release
```

If you want to build Firefox without Wasm or LIM, then use

```
# Firefox that does not use WASM or LIM
make build_guest_nosbx_debug
make build_guest_nosbx_release
```

# Running the png benchmark and saving a screenshot

After building the debug or release version of firefox, you can run the benchmark.

First enable the lim model in SIMICS with the compartment id extension with the SIMICS command shown below.

```
new-lim-model -connect-all -use-compartment-id
```

You can then run the below command in the **guest** terminal to run the png benchmark. Note that this benchmark runs on whichever firefox was built last --- debug or release.

```bash
make test_guest_png
```
- If it’s successful, you’ll see the following in the guest terminal

   ```
   !!!!!!!!!!!!!!!Finished rendering PNG (file:///usr/src/lim_rlbox_firefox_root/lim_firefox/testing/talos/talos/tests/png_perf_test/png_perf_test.png): 800x600
   ```

    Once the image is successfully rendered, if you want to take screenshot, run the below command in a fresh **lab_host** terminal 

    ```bash
    make guest_get_screenshot
    ```

    This will save the image to the **lab_host** file system under `$(SRC_DIR)/lim_rlbox_firefox_root/screenshots`. 

- If firefox fails with a segfault you will see a stack trace. If this happens see the section on "debugging below".

After this you will have to force close Firefox as this does not auto close. You can use CTRL+C for this. Note that Firefox may leave zombie processes, so make sure to kill all processes by looking at the output of the command `ps aux | grep firefox` in the guest environment.


# Making changes to Firefox

## First test on lab-host enviroment
To make changes, it is recommended you first test changes in the **lab_host** environment --- i.e. test changes without LIM. To do this, simply go to the file `lim_rlbox_firefox_root/rlbox_lim_sandbox/c_src/lim_sandbox_wrapper.c` and change the line

```cpp
const bool ACTUALLY_USE_LIM = true; // Make this false to disable lim
```

Do not push this! This for local debugging on the lab_host machine.

If you see any crashes in the lab_host machine (without lim) fix that first. To debug firefox, I recommend the `rr` reversible debugger. Since Firefox is multi-process and multi-thread, this is the best way to debug this.

After fixing this, push your changes.

## Update and test the build in your guest environment with LIM

See updating the build section to build the debug version of firefox.

Then test the png benchmark as described in "Running the png benchmark and saving a screenshot". If this is unsuccessful, see "Debugging a crash" below.

# Debugging a crash

If you make a change to Firefox that causes a crash in the guest environment, we can attach gdb to look at the current backtrace with symbols. We will not use the SIMICS debuggger but rather the one inside the **guest** environment.

**Important** - Make sure to use the debug build of firefox for the next steps. You can debug the release build, but symbol support etc. is not great.

## Identify the details of the crash.

Firefox's debug build crashes with a stack trace followed by the message `Sleeping for 300000 seconds`. Additionally you will also see a message similar to 

```
Attach a debugger with the command 'gdb /usr/src/lim_rlbox_firefox_root/build/obj-ff-dbg/dist/bin/firefox 14847'
```

Here 14847 is the PID of Firefox. Note this PID for next step.

## Save and reload a checkpoint without LIM

Stop the current simics session and save the checkpoint. (Do **not** use an independent checkpoint. It takes too long!). Restart SIMICS with the checkpoint by following the instructions in "Loading a build of this repo/Via checkpoint." Make sure to run the connect-real-network command!

Importantly, do **not** load the LIM simics model. The simulation will become too slow to attach the debugger. 

## Attach the debugger

Run the command in a fresh **lab_host** terminal to attach gdb to the firefox running in the guest enviroment.

```bash
make guest_attach_debugger
# Enter the PID observed earlier in step 1 when prompted
```

## Locate the crash

A firefox process has multiple threads, so to find the one that crashed, use the gdb command

```
info threads
```

You will see a list of threads. Any thread that has the top function `nano_sleep` is likely a crashed thread that is sleeping until a debugger is attached. Switch to that thread. If that was thread 12, use gdb command

```
thread 12
```


If you then print the backtrace, you will see the crash. You can tell if it is crash because the first 5 or 6 frames will be various firefox crash handling routines such as the `signal raised`, `ah_crap_handler` etc. You will see your code that caused a crash about 7 frames into the `bt`. You can swich to these frames, query variables etc.

# List of all available makefile targets

(Some targets not listed as there is no need to look at those. Some targets below are run automatically by others as part of the build.)

- **setup_simics_host** - setup some lab_host computer to be ready to run simics by enabling vmp.
- **get_source** - Get the code of all sub repos needed by this repo. Update the code of this and all sub repos pulled in. Can be run in lab_host, or guest env.
- **pull** - Update the code of this and all sub repos pulled in. Can be run in lab_host, or guest env.
- **setup_host** - Sets up the host environment by installing docker etc.
- **setup_guest** - Sets up the guest environment by installing Firefox dependencies etc.
- **build_guest_debug** - Build debug version of Firefox with LIM. Should be run in the guest env. You can this in lab_host also, but a lim build will not be very useful there as you can't run it.
- **build_guest_release** - Build release version of Firefox with LIM. Should be run in the guest env. You can this in lab_host also, but a lim build will not be very useful there as you can't run it.
- **build_guest_nolim_debug** - Build debug version of Firefox with Wasm. Should be run in the lab_host env. You can this in guest also.
- **build_guest_nolim_release** - Build release version of Firefox with Wasm. Should be run in the lab_host env. You can this in guest also.
- **build_guest_nosbx_debug** - Build debug version of Firefox without Wasm & without LIM. Should be run in the lab_host env and useful for basic debugging of Firefox outside of LIM related issues. You can this in guest also.
- **build_guest_nosbx_release** - Build release version of Firefox without Wasm & without LIM. Should be run in the lab_host env and useful for basic debugging of Firefox outside of LIM related issues. You can this in guest also.
- **build_host** - Setup the host, then build the docker image of a guest env that has also been setup. Can be run in the host env.
- **test_guest_graphite** - Run the graphite font library test. I haven't run this in a while, but this was passing when I last checked. Can be run in the lab_host or guest env. Successful completion will say something like "TESTS 5/5 pass".
- **test_guest_png** - Run the png image rendering test. Can be run in the lab_host or guest env. If successful you will see the message "!!!!!!!!!!!!!!!Finished rendering PNG ..."
- **guest_get_screenshot** - Get a screenshot of firefox that is currently running and save it in `$(SRC_DIR)/lim_rlbox_firefox_root/screenshots`. Must be run in lab_host env.
- **guest_attach_debugger** - Attach to the Firefox running in the guest env. Command must be run in lab_host env. The target will prompt for the PID of the guest Firefox process to attach to.
