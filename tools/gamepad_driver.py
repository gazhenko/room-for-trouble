#!/usr/bin/env python3
"""Creates kernel gamepads (uinput/evdev) and operates them for the exported
game's --gamepad-test harness (src/dev/gamepad_test.gd). Linux only; needs
python3-evdev and write access to /dev/uinput. Follows the harness phases
written to <dir>/phase.txt.
    python3 tools/gamepad_driver.py <dir>
"""
import os, sys, time
from evdev import UInput, AbsInfo, ecodes as e

OUT = sys.argv[1]
STICK = AbsInfo(0, -32768, 32767, 16, 128, 0)
TRIG = AbsInfo(0, 0, 255, 0, 0, 0)
HAT = AbsInfo(0, -1, 1, 0, 0, 0)
AXES = [(e.ABS_X, STICK), (e.ABS_Y, STICK), (e.ABS_Z, TRIG), (e.ABS_RX, STICK), (e.ABS_RY, STICK),
        (e.ABS_RZ, TRIG), (e.ABS_HAT0X, HAT), (e.ABS_HAT0Y, HAT)]
XBOX = dict(name="Microsoft X-Box 360 pad", vendor=0x045e, product=0x028e, version=0x110,
            keys=[e.BTN_SOUTH, e.BTN_EAST, e.BTN_NORTH, e.BTN_WEST, e.BTN_TL, e.BTN_TR, e.BTN_SELECT,
                  e.BTN_START, e.BTN_MODE, e.BTN_THUMBL, e.BTN_THUMBR])
DS4 = dict(name="Sony Interactive Entertainment Wireless Controller", vendor=0x054c, product=0x09cc, version=0x8111,
           keys=[e.BTN_SOUTH, e.BTN_EAST, e.BTN_NORTH, e.BTN_WEST, e.BTN_TL, e.BTN_TR, e.BTN_TL2, e.BTN_TR2,
                 e.BTN_SELECT, e.BTN_START, e.BTN_MODE, e.BTN_THUMBL, e.BTN_THUMBR])

def pad(model):
    return UInput({e.EV_KEY: model["keys"], e.EV_ABS: AXES}, name=model["name"], vendor=model["vendor"],
                  product=model["product"], version=model["version"], bustype=e.BUS_USB)

def press(p, key, hold=0.12):
    p.write(e.EV_KEY, key, 1); p.syn(); time.sleep(hold)
    p.write(e.EV_KEY, key, 0); p.syn(); time.sleep(0.25)

def stick(p, x, y):
    p.write(e.EV_ABS, e.ABS_X, x); p.write(e.EV_ABS, e.ABS_Y, y); p.syn()

def phase():
    try:
        return open(os.path.join(OUT, "phase.txt")).read().strip()
    except OSError:
        return ""

def wait_phase(name, timeout=120):
    t = time.time()
    while phase() != name:
        if phase() == "done" or time.time() - t > timeout:
            print("driver: gave up waiting for", name, "at", phase(), flush=True)
            sys.exit(1)
        time.sleep(0.1)
    print("driver: phase", name, flush=True)

def hat_down(p):
    p.write(e.EV_ABS, e.ABS_HAT0Y, 1); p.syn(); time.sleep(0.12)
    p.write(e.EV_ABS, e.ABS_HAT0Y, 0); p.syn(); time.sleep(0.25)

pads = [pad(XBOX), pad(XBOX), pad(DS4), pad(XBOX)]
wait_phase("menu")
time.sleep(0.5)
hat_down(pads[0])          # pad 1 drives the menu, so the lobby seats it first
wait_phase("join")
time.sleep(0.8)
for p in pads[1:]:
    press(p, e.BTN_SOUTH)
    time.sleep(0.4)
wait_phase("move")
moves = [(32767, 0), (-32767, 0), (0, 32767), (0, -32767)]
for p, (x, y) in zip(pads, moves):
    stick(p, x, y)
time.sleep(2.0)
for p in pads:
    stick(p, 0, 0)
wait_phase("pause")
press(pads[2], e.BTN_START)
wait_phase("resume")
press(pads[2], e.BTN_EAST)
wait_phase("unplug")
time.sleep(0.5)
pads[1].close()
wait_phase("replug")
time.sleep(0.5)
pads[1] = pad(DS4)
time.sleep(2.5)  # let the game notice the new device
press(pads[1], e.BTN_SOUTH)
wait_phase("resume2")
time.sleep(0.5)
press(pads[0], e.BTN_EAST)
wait_phase("done", timeout=60)
for p in pads:
    p.close()
print("driver: finished", flush=True)
