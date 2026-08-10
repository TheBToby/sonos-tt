#!/usr/bin/env python3
"""Waveshare circular display backlight brightness control.

Controls the backlight of Waveshare HDMI displays (e.g., 7" Round LCD).

This script uses TWO methods to set brightness, trying each in order:

1. **hidraw** (preferred): Writes via /dev/hidraw* — the kernel's raw HID
   interface. This does NOT detach or interfere with any kernel drivers,
   so the touchscreen keeps working at all times.

2. **pyusb** (fallback): Uses libusb to send a USB interrupt transfer. This
   requires temporarily detaching the kernel driver from the USB interface.
   The driver is reattached afterward, but this method is less reliable.

Protocol (provided by Waveshare tech support):
  - USB VID: 0x0712, PID: 0x000a
  - Command: [0x09, 0x08, 0xF7, raw_level, checksum]
  - raw_level: 1–240 (maps from 0–100% brightness)
  - checksum: bitwise NOT of raw_level, masked to 0xFF
  - Sent twice for reliability

Prerequisites:
  sudo apt install python3-usb    # for pyusb fallback

Usage:
  python3 brightness.py 80    # Set brightness to 80%
"""

import os
import sys

VID = "0712"
PID = "000a"
RAW_MIN = 1
RAW_MAX = 240


def find_hidraw_device():
    """Find the /dev/hidraw* device path for the Waveshare display.

    Walks /sys/class/hidraw/ to find a device whose parent USB device
    matches our VID:PID. Returns the /dev/hidraw* path or None.
    """
    try:
        import glob
    except ImportError:
        return None

    for sysfs_path in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        try:
            # Walk up the sysfs tree to find idVendor/idProduct
            current = os.path.join(sysfs_path, "device")
            for _ in range(10):
                vid_file = os.path.join(current, "idVendor")
                pid_file = os.path.join(current, "idProduct")
                if os.path.isfile(vid_file) and os.path.isfile(pid_file):
                    with open(vid_file) as f:
                        vid = f.read().strip()
                    with open(pid_file) as f:
                        pid = f.read().strip()
                    if vid.lower() == VID.lower() and pid.lower() == PID.lower():
                        # Return the /dev/hidrawN name
                        name = os.path.basename(sysfs_path.rstrip("/"))
                        return f"/dev/{name}"
                    break
                current = os.path.dirname(current)
        except (IOError, OSError):
            continue
    return None


def set_brightness_hidraw(raw_level):
    """Set brightness via /dev/hidraw* — does NOT interfere with kernel drivers.

    The kernel HID driver stays bound and the touchscreen keeps working.
    """
    dev_path = find_hidraw_device()
    if dev_path is None:
        return False

    try:
        checksum = (~raw_level) & 0xFF
        data = bytes([0x09, 0x08, 0xF7, raw_level, checksum])

        # Open hidraw device for writing. O_NONBLOCK avoids blocking if the
        # device isn't ready, but we use a blocking write for reliability.
        fd = os.open(dev_path, os.O_WRONLY)
        try:
            os.write(fd, data)
            os.write(fd, data)  # Send twice for reliability
        finally:
            os.close(fd)
        return True
    except (IOError, OSError):
        return False


def set_brightness_pyusb(raw_level):
    """Fallback: set brightness via pyusb (libusb).

    This requires detaching the kernel driver from the USB interface.
    The driver is reattached afterward, but this method may cause
    temporary touchscreen disruption.
    """
    try:
        import usb.core
        import usb.util
    except ImportError:
        return False

    dev = usb.core.find(idVendor=int(VID, 16), idProduct=int(PID, 16))
    if dev is None:
        return False

    # Track kernel driver state for proper cleanup.
    detached_interfaces = []

    try:
        cfg = dev.get_active_configuration()

        # Iterate ALL interfaces. Prefer interfaces WITHOUT a kernel driver
        # (the brightness control interface typically has no kernel driver,
        # while the touchscreen interface does). This avoids detaching the
        # touchscreen driver entirely.
        target_intf = None
        for intf in cfg:
            try:
                iface_num = intf.bInterfaceNumber
                has_driver = dev.is_kernel_driver_active(iface_num)
            except Exception:
                has_driver = False

            # Look for an OUT endpoint on this interface.
            ep = usb.util.find_descriptor(
                intf,
                custom_match=lambda e: usb.util.endpoint_direction(e.bEndpointAddress)
                == usb.util.ENDPOINT_OUT,
            )
            if ep is not None:
                if not has_driver:
                    # Perfect — this interface has an OUT endpoint and no
                    # kernel driver. Use it without detaching anything.
                    target_intf = (intf, ep, iface_num)
                    break
                elif target_intf is None:
                    # Fallback — interface has a driver but also an OUT endpoint.
                    target_intf = (intf, ep, iface_num)

        if target_intf is None:
            return False

        intf, ep, iface_num = target_intf

        # Detach kernel driver ONLY if necessary (i.e., this interface has one).
        try:
            if dev.is_kernel_driver_active(iface_num):
                dev.detach_kernel_driver(iface_num)
                detached_interfaces.append(iface_num)
        except Exception:
            pass

        # Claim the interface.
        try:
            usb.util.claim_interface(dev, iface_num)
        except Exception:
            pass

        # Send the brightness command (twice for reliability).
        checksum = (~raw_level) & 0xFF
        data = [0x09, 0x08, 0xF7, raw_level, checksum]
        ep.write(data)
        ep.write(data)
        return True

    except Exception:
        return False
    finally:
        # Release claimed interfaces.
        try:
            for iface_num in detached_interfaces:
                usb.util.release_interface(dev, iface_num)
        except Exception:
            pass
        try:
            usb.util.dispose_resources(dev)
        except Exception:
            pass
        # Reattach ALL kernel drivers we detached.
        for iface_num in detached_interfaces:
            try:
                dev.attach_kernel_driver(iface_num)
            except Exception:
                pass


def main():
    if len(sys.argv) != 2:
        print("Usage: python3 brightness.py <0-100>", file=sys.stderr)
        print("Example: python3 brightness.py 80", file=sys.stderr)
        sys.exit(1)

    try:
        percent = max(0, min(100, int(sys.argv[1])))
    except ValueError:
        print("Error: brightness must be an integer 0–100", file=sys.stderr)
        sys.exit(1)

    raw_level = max(RAW_MIN, min(RAW_MAX, int((percent / 100) * (RAW_MAX - RAW_MIN))))

    # Try hidraw first (touchscreen-safe), then fall back to pyusb.
    if set_brightness_hidraw(raw_level):
        return

    if set_brightness_pyusb(raw_level):
        return

    # Neither method worked — silent exit (hardware dimming is best-effort).


if __name__ == "__main__":
    main()