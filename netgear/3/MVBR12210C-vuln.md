# MVBR1210C cmdi vulnerbility

This vulnerability lies in the `diagCgiPingMain` function which influences the latest version of Netgear MVBR1210C [link](https://www.netgear.com/support/product/mvbr1210c#download)

## vulnerbility description

There is a stack-based buffer overflow and command injection vulnerbility in function `diagCgiPingMain` in `/usr/sbin/httpd` </br>
In function `diagCgiPingMain`, it reads user ptovided parameter `ping_IPAddr` into `v4`, this variable is passed into function `sprintf` and `system` without any length check, which may cause stack based overflow of `v4` and command injection.

![image](https://github.com/Nicholas-wei/bug-discovery/assets/63231742/ddd3f267-5d78-4905-b653-c14fae858f59)


## timeline

[2023/7/28] report to CVE</br>
[2023/8/21] assigned CVE-2023-39630
