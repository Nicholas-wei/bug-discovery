# totolink nr1800x hard-coded telnet password

## firmware info

Vendor: Totolink

Firmware: Nr1800x

Version: nr1800x-v9.1.0u.6681_b20230703

Support & Download URL: https://www.totolink.net/data/upload/20230830/3f37d49f50b33c3cf8ab241570728d39.zip

## Description

totolink nr1800x contains hard-coded telnet password, which allows any user to log into the telnet service of the device with root ptivilege.

## Detail

In binary `www/cgi-bin/cstecgi.cgi`, The following code controls the telnet service. The following code is at address `0x437D40`.

![image-20250212112119777](telnet_hardcode_passwd.assets/image-20250212112119777.png)

Form the code above, we can find that the password used for telnet service is from `nvram_safe_get("telnet_key_custom")`.

During initialization, the following code fills nvram with key `telnet_key_custom`. The following code is from `usr/sbin/custom_info_to_nvram` at address `0x401DD0`

![image-20250212112258959](telnet_hardcode_passwd.assets/image-20250212112258959.png)

An unauthenticated attacker can start and log into the telnet service by using key "KL@UHeZ0". 