#!/usr/bin/env python3
"""Waveshare circular display backlight brightness control.

Controls the backlight of Waveshare HDMI displays (e.g., 7" Round LCD).

This script tries ALL /dev/hidraw* device nodes to find the brightness
controller. We do NOT filter by USB VID/PID because different Waveshare
models (and revisions) use different USB controller chips with different
VID/PID combinations.

The script NEVER uses pyusb/libusb, because detaching the kernel driver
disrupts the touchscreen on composite USB devices.

Protocol (Waveshare tech support, applies to most models):
  Command: [0x09, 0x08, 0xF7, raw_level, checksum]
  raw_level: 1–240 (maps from 0–100% brightness)
  checksum: bitwise NOT of raw_level, masked to 0xFF
  Sent twice for reliability

Usage:
  python3 brightness.py 80    # Set brightness to 80%
  python3 brightness.py 0     # Backlight off
"""

import glob
import os
import sys

RAW_MIN = 1
RAW_MAX = 240

# Brightness command bytes (Waveshare protocol).
# These are written to each hidraw node; non-matching devices simply
# ignore the data.
_CMD_PREFIX = bytes([0x09, 0x08, 0xF7])


def _build_command(raw_level):
    """Build the brightness command payload for a given raw level."""
    checksum = (~raw_level) & 0xFF
    return _CMD_PREFIX + bytes([raw_level, checksum])


def _is_touchscreen(sysfs_path):
    """Check if a hidraw node is bound to a touchscreen driver.

    We avoid writing to touchscreen interfaces to prevent corrupting
    touch input. However, if only one hidraw node exists and it IS the
    touchscreen, we try it anyway (some displays multiplex touch and
    brightness on a single HID interface).
    """
    driver_link = os.path.join(sysfs_path, "device", "driver")
    try:
        if os.path.islink(driver_link):
            driver = os.path.basename(os.readlink(driver_link))
            touch_drivers = ("multitouch", "usbtouchscreen", "egalax",
                             "penmount", "elo", "wacom", "gt683r")
            if any(td in driver.lower() for td in touch_drivers):
                return True, driver
    except (OSError, IOError):
        pass
    return False, None


def _get_usb_ids(sysfs_path):
    """Try to read idVendor/idProduct for diagnostics."""
    current = os.path.join(sysfs_path, "device")
    for _ in range(10):
        vid_file = os.path.join(current, "idVendor")
        pid_file = os.path.join(current, "idProduct")
        if os.path.isfile(vid_file) and os.path.isfile(pid_file):
            try:
                with open(vid_file) as f:
                    vid = f.read().strip()
                with open(pid_file) as f:
                    pid = f.read().strip()
                return vid, pid
            except (IOError, OSError):
                pass
        current = os.path.dirname(current)
    return None, None


def find_all_hidraw():
    """Return all /dev/hidraw* device paths, sorted."""
    nodes = []
    for sysfs_path in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        name = os.path.basename(sysfs_path.rstrip("/"))
        nodes.append((f"/dev/{name}", sysfs_path))
    return nodes


def set_brightness(raw_level):
    """Set brightness by trying all hidraw devices.

    Strategy:
    1. Find all /dev/hidraw* nodes.
    2. Sort: non-touchscreen nodes first, touchscreen nodes last.
    3. Try each in order. Return on first success.

    Returns the device path on success, or None on failure.
    """
    all_nodes = find_all_hidraw()
    if not all_nodes:
        return None

    # Separate non-touch and touch nodes. Try non-touch first.
    non_touch = []
    touch = []
    for dev_path, sysfs_path in all_nodes:
        is_touch, _ = _is_touchscreen(sysfs_path)
        if is_touch:
            touch.append((dev_path, sysfs_path))
        else:
            non_touch.append((dev_path, sysfs_path))

    # Try non-touch nodes first, then touch nodes as last resort.
    ordered = non_touch + touch
    data = _build_command(raw_level)

    for dev_path, _ in ordered:
        try:
            fd = os.open(dev_path, os.O_WRONLY | os.O_NONBLOCK)
            try:
                os.write(fd, data)
                os.write(fd, data)  # Send twice for reliability
            finally:
                os.close(fd)
            return dev_path
        except (IOError, OSError):
            continue

    return None


def print_diagnostics():
    """Print comprehensive diagnostics to stderr."""
    print(f"  Running as: {os.environ.get('USER', '?')} uid={os.getuid()}",
          file=sys.stderr)

    all_nodes = find_all_hidraw()
    print(f"  All /dev/hidraw* nodes ({len(all_nodes)}):", file=sys.stderr)
    for dev_path, sysfs_path in all_nodes:
        vid, pid = _get_usb_ids(sysfs_path)
        is_touch, driver = _is_touchscreen(sysfs_path)
        try:
            stat = os.stat(dev_path)
            mode = oct(stat.st_mode & 0o777)
        except OSError:
            mode = "(stat failed)"
        ids = f"VID={vid} PID={pid}" if vid else "VID/PID unknown"
        drv = f"driver={driver}" if driver else "(no driver link)"
        touch_tag = " [TOUCH]" if is_touch else ""
        print(f"    {dev_path} {ids} {drv} mode={mode}{touch_tag}",
              file=sys.stderr)

    if not all_nodes:
        print("  NOTE: No /dev/hidraw* nodes found at all.", file=sys.stderr)
        print("        The display USB cable may be disconnected.", file=sys.stderr)


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

    # 0% turns the backlight off entirely (raw level 0). Any positive
    # percentage maps into the supported 1–240 raw range.
    if percent <= 0:
        raw_level = 0
    else:
        raw_level = max(RAW_MIN, min(RAW_MAX, int((percent / 100) * (RAW_MAX - RAW_MIN))))

    result_dev = set_brightness(raw_level)
    if result_dev is not None:
        print(f"brightness: {percent}% (raw={raw_level}) via {result_dev}")
        return

    print(f"brightness: FAILED to set {percent}% (raw={raw_level})", file=sys.stderr)
    print_diagnostics()
    sys.exit(1)


if __name__ == "__main__":
    main()