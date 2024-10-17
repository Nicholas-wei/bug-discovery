# ASUS ax56 NULL pointer dereference

In asus 4G-ax56 version  [3.0.0.4.382_45708](https://dlcdnets.asus.com/pub/ASUS/wireless/4G-AX56/FW_4G_AX56_300438245708.zip?model=4G-AX56) , the binary `/usr/sbin/httpd` ahs a NULL pointer dereference bug.Remote attackers can send malicious packet to the router, which will cause DoS(Deny of service) attack.

## description

In function `sub_435224`, the router receives "action_mode" parameter from network packet, after that it didn't check the param `v3`. If v3 is NULL, the following code will cause cause segmentation fault.

![image-20240216123021903](asus_ax53_NULL_pointer/image-20240216123021903.png)

## PoC

see [poc](./poc)

![image-20240216132425402](asus_ax53_NULL_pointer/image-20240216132425402.png)