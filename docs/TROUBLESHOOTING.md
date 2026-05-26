# Troubleshooting

## Common Issues

| Problem | Solution |
|---------|----------|
| "Cannot mount ext3" | Image file corrupted. Re-run `build_rootfs.sh` |
| No internet in chroot | `echo "nameserver 8.8.8.8" > /etc/resolv.conf` |
| `apt-get` hangs | Wi-Fi dropped. Reconnect and retry |
| kterm won't launch | Check `/mnt/us/extensions/kterm/` exists |
| SSH connection refused | Run `/ssh` first. Check Wi-Fi is connected |
| Out of disk space | Rebuild with `--size 2048` for 2GB |
| Screen rotation fails | Your model may not support `/sys/class/graphics/fb0/rotate` |
| `tar: No space left on device` (Arch) | Use `--size 2048` minimum for Arch |
| Chroot says "exec format error" | `qemu-arm-static` not installed or binfmt not registered |

## Fixing DNS

If packages won't download:

```bash
rm -f /etc/resolv.conf
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf
```

## Resizing an image

If you run out of space, create a bigger image and copy data:

```bash
# On your PC:
dd if=/dev/zero of=bigger.ext3 bs=1M count=2048
mkfs.ext3 -F bigger.ext3

mkdir -p /tmp/old /tmp/new
mount -o loop old.ext3 /tmp/old
mount -o loop bigger.ext3 /tmp/new
cp -a /tmp/old/* /tmp/new/
umount /tmp/old /tmp/new
mv bigger.ext3 debian.ext3
```

## Kindle won't wake up after chroot

If Kindle seems frozen:
1. Hold power button for 40 seconds (hard reset)
2. The chroot doesn't affect Kindle OS boot

## Freeing RAM

Kindle OS uses ~200MB. To free more:

```bash
# Stop the Kindle framework (saves ~100MB but kills GUI)
stop framework
# Restart it later:
start framework
```

## Logs

Check what's happening:

```bash
dmesg | tail -20
cat /proc/mounts | grep ext3
free -m
df -h
```
