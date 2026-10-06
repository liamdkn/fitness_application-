#!/usr/bin/env python3
"""
Talks to the Phoenix / Fitdays+ kitchen scale (BLE name MY_SCALE) from a Mac,
to find out what the scale really sends, using the open-source pyfitdaysplus
library as the reference.

Setup (once):
    cd scripts
    /opt/homebrew/bin/python3.12 -m venv .scale-venv
    source .scale-venv/bin/activate
    pip install pyfitdaysplus bleak

Run (close Fitdays+ and nRF Connect first - the scale talks to one app at a time,
and allow Bluetooth for Terminal when macOS asks). Keep a weight (a tin, 100 g or
more) next to the scale and follow the on-screen prompts:

    python scale_probe.py           # the library: connect, listen for weight
    python scale_probe.py --food    # the same, but first start a food-weigh session
                                    # (what Fitdays+ does when you pick a food)
    python scale_probe.py --raw     # plain Bluetooth: print every message
    python scale_probe.py --probe   # plain Bluetooth: try "set user" commands, one at a time,
                                    # with the weight left ON the scale

Send back everything it prints.
"""
import asyncio
import sys
import time

from bleak import BleakClient, BleakScanner

NAME = "MY_SCALE"
WRITE = "0000ffb1-0000-1000-8000-00805f9b34fb"
NOTIFY = "0000ffb2-0000-1000-8000-00805f9b34fb"
HANDSHAKE = bytes.fromhex("ac42000200a000d173")
HISTORY = bytes.fromhex("ac42000000d4d4")

# (seconds from the start, what to tell the person)
PROMPTS = [
    (0, "Scale empty - leave it alone for a few seconds"),
    (6, ">>> PUT THE WEIGHT ON THE SCALE NOW <<<"),
    (16, ">>> TAKE IT OFF <<<"),
    (22, ">>> PUT IT BACK ON <<<"),
    (32, ">>> PRESS TARE ON THE SCALE <<<"),
    (40, "Finishing ..."),
]


async def prompts(started):
    for at, text in PROMPTS:
        await asyncio.sleep(max(0, started + at - time.time()))
        print(f"\n[{time.time() - started:5.1f}s] {text}\n", flush=True)


async def find():
    print(f"Looking for {NAME} ...")
    device = await BleakScanner.find_device_by_name(NAME, timeout=20)
    if device is None:
        sys.exit("Not found. Is the scale awake and free of other apps?")
    print(f"Found {device.name} at {device.address}")
    return device


async def with_library(food: bool):
    from pyfitdaysplus import Device
    from pyfitdaysplus.events import Event
    from pyfitdaysplus.models import CommonFood

    device = await find()
    scale = Device(device)
    started = time.time()
    count = 0

    def on_weight(reading):
        nonlocal count
        count += 1
        print(f"[{time.time() - started:5.1f}s] WEIGHT {reading.grams:.1f} g stable={reading.stable} "
              f"tare={reading.is_tare} unit={reading.unit.name} raw={reading.raw_payload.hex(' ')}", flush=True)

    async with scale:
        scale.subscribe(Event.WEIGHT, on_weight)
        print("Connected.", flush=True)
        if food:
            print("Starting a food-weigh session for 'oats' ...", flush=True)
            await scale.start_food_weigh(CommonFood(food_id=42, name="oats", weight=100, facts=()))
        started = time.time()
        await asyncio.gather(prompts(started), asyncio.sleep(42))
        print(f"\nDone. Weight messages received: {count}")


async def raw():
    device = await find()
    started = time.time()
    count = 0

    def show(_, data: bytearray):
        nonlocal count
        count += 1
        print(f"[{time.time() - started:5.1f}s] FFB2: {data.hex(' ')}", flush=True)

    async with BleakClient(device) as client:
        print("Connected. Subscribing to FFB2 ...")
        await client.start_notify(NOTIFY, show)
        await asyncio.sleep(3)
        print("Sending the handshake:", HANDSHAKE.hex(" "))
        await client.write_gatt_char(WRITE, HANDSHAKE, response=True)
        await asyncio.sleep(1)
        print("Asking for stored weights:", HISTORY.hex(" "))
        await client.write_gatt_char(WRITE, HISTORY, response=True)
        started = time.time()
        await asyncio.gather(prompts(started), asyncio.sleep(42))
        print(f"\nDone. Messages received on FFB2: {count}")


def frame(payload: bytes, cmd: int) -> bytes:
    """AC 42 [payload] [cmd] [checksum], checksum = sum of everything after the 42."""
    body = payload + bytes([cmd])
    return bytes([0xAC, 0x42]) + body + bytes([sum(body) & 0xFF])


def split(data: bytes) -> bytes:
    """The scale's 'split data' wrapper: total length (2 bytes), sequence 0, then the data."""
    return len(data).to_bytes(2, "big") + b"\x00" + data


# Guesses at the "tell the scale who is weighing" command. The library's notes say
# user info is command 0xDB (newer firmware, includes a user id) or 0xD0 (older).
# A command the scale understands is acknowledged with an A1 message.
CANDIDATES = [
    # Worked on a KN2432LB: the scale acknowledges it and starts streaming weight.
    ("user info DB: id 1", frame(split(bytes.fromhex("00000001")), 0xDB)),
    ("user info DB: id 1 + 8 zero bytes", frame(split(bytes.fromhex("00000001") + bytes(8)), 0xDB)),
    ("user info D0: index 1", frame(split(bytes.fromhex("01")), 0xD0)),
    ("user info D0: id 1", frame(split(bytes.fromhex("00000001")), 0xD0)),
]


async def probe():
    device = await find()
    started = time.time()
    count = 0

    def show(_, data: bytearray):
        nonlocal count
        count += 1
        print(f"[{time.time() - started:5.1f}s]   <- FFB2: {data.hex(' ')}", flush=True)

    async with BleakClient(device) as client:
        await client.start_notify(NOTIFY, show)
        print("Connected. Leave a weight ON the scale and keep nudging it.\n")
        await asyncio.sleep(2)
        print("Handshake:", HANDSHAKE.hex(" "))
        await client.write_gatt_char(WRITE, HANDSHAKE, response=True)
        await asyncio.sleep(3)
        for name, data in CANDIDATES:
            started_at = time.time() - started
            print(f"\n[{started_at:5.1f}s] -> {name}: {data.hex(' ')}", flush=True)
            await client.write_gatt_char(WRITE, data, response=True)
            await asyncio.sleep(5)
        print(f"\nDone. Messages received on FFB2: {count}")


if __name__ == "__main__":
    if "--probe" in sys.argv:
        asyncio.run(probe())
        sys.exit()
    if "--raw" in sys.argv:
        asyncio.run(raw())
    else:
        asyncio.run(with_library("--food" in sys.argv))
