# netgear-WNDR4500v2 buffer overflow

<!-- more -->

## affected version

this buffer overflow will affect the following product, version 1.0.0.72

[WNDR4500v2 | N900 WiFi Router | NETGEAR Support](https://www.netgear.com/support/product/wndr4500v2#download)

## description

in `/usr/sbin/upnpd` , the upnp service will receive the ssdp packet through `recvfrom`. The max length of `recvfrom` is 0x1fffu.

![image-20230728113740476](./image-20230728113740476.png)

However, in `ssdp_method_check`, It calls `strcpy` to copy the buffer received (`v84`) into`v27`, which has only the size of 0x5EB. It will cause buffer overflow.
Buffer overflow will cause denial of service or command execution.

![image-20230728113854591](./image-20230728113854591.png)

## timeline
[2023/7/28] report to CVE</br>
[2023/8/21] assigned CVE-2023-39628
