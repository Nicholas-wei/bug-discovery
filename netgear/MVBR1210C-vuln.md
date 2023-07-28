# MVBR1210C cmdi vulnerbility

This vulnerability lies in the `diagCgiDnslookup` function which influences the latest version of Netgear MVBR1210C.

## vulnerbility description

There is a stack-based buffer overflow and command injection vulnerbility in function `diagCgiDnslookup`
In function `diagCgiDnslookup`, it reads user ptovided parameter `host_name` into `v4`, this variable is passed into function `sprintf` and `system` without any length check, which may cause stack based overflow of `v4` and command injection.

![image](https://github.com/Nicholas-wei/bug-discovery/assets/63231742/b3be1387-e8b7-4da8-82f5-a1238c23927c)

## timeline

[2023/7/28] report to CVE
