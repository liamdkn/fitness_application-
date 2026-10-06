#!/usr/bin/env python3
"""
Talks to the Phoenix / Fitdays+ kitchen scale (BLE name MY_SCALE) from a Mac,
to find out what the scale really sends, using the open-source pyfitdaysplus
library as the reference.

Setup (once):
    cd scripts
    python3 -m venv .scale-venv
    source .scale-venv/bin/activate
    pip install pyfitdaysplus bleak

Run (close Fitdays+ and nRF Connect first - the scale talks to one app at a time,
and allow Bluetooth for Terminal when macOS asks):
    python scale_probe.py           # the library: connect and read weight for 20 s
    python scale_probe.py --raw     # plain Bluetooth: subscribe, handshake, print every message

Put a weight on the scale while it runs, then send back everything it prints.
"""
import asyncio
import logging
import sys
import time

from bleak import BleakClient, BleakScanner

NAME = "MY_SCALE"
WRITE = "0000ffb1-0000-1000-8000-00805f9b34fb"
NOTIFY = "0000ffb2-0000-1000-8000-00805f9b34fb"
HANDSHAKE = bytes.fromhex("ac42000200a000d173")
HISTORY = bytes.fromhex("ac42000000d4d4")


async def find():
    print(f"Looking for {NAME} ...")
    device = await BleakScanner.find_device_by_name(NAME, timeout=20)
    if device is None:
        sys.exit("Not found. Is the scale awake and free of other apps?")
    print(f"Found {device.name} at {device.address}")
    return device


async def with_library():
    from pyfitdaysplus import Device

    logging.basicConfig(level=logging.DEBUG)
    device = await find()
    scale = Device(device)
    async with scale:
        print("Connected. Put something on the scale.")
        end = time.time() + 20
        while time.time() < end:
            try:
                reading = await asyncio.wait_for(scale.async_get_weight(), timeout=3)
                print(f"weight: {reading}")
            except asyncio.TimeoutError:
                print("(no weight message in 3 s)")


async def raw():
    device = await find()
    started = time.time()

    def show(_, data: bytearray):
        print(f"[{time.time() - started:6.2f}s] FFB2: {data.hex(' ')}")

    async with BleakClient(device) as client:
        print("Connected. Subscribing to FFB2 ...")
        await client.start_notify(NOTIFY, show)
        print("Waiting 3 s for the scale to announce itself ...")
        await asyncio.sleep(3)
        print("Sending the handshake:", HANDSHAKE.hex(" "))
        await client.write_gatt_char(WRITE, HANDSHAKE, response=True)
        await asyncio.sleep(2)
        print("Asking for stored weights:", HISTORY.hex(" "))
        await client.write_gatt_char(WRITE, HISTORY, response=True)
        print("Listening for 20 s - put a weight on the scale ...")
        await asyncio.sleep(20)


if __name__ == "__main__":
    asyncio.run(raw() if "--raw" in sys.argv else with_library())
