# Netgear EX6110 hard-coded web management credential

## firmware information

vendor: netgear

product: EX6110

affected version: up to firmware version 1.0.1.80

product URL: https://www.netgear.com/support/product/ex6110/#download

## description

In netgear EX6110, hard-coded credential on the Web Interface allows anyone to log in to the firmware directly to perform administrative functions. Malicious attacker can reverse the firmware and use hard-coded credential with username '00E0A6-111' and password '00E0A6-111' for authentication.

## detail

In function `auth_check`(address: 0x18264), of the web service of the firmware, which is `mini_httpd`, the following code handles authentication. The following code reads credential stored inside firmware

![image-20250508181309585](hard-coded-credential.assets/image-20250508181309585.png)

The read credential is then send into function `CalcDigest` to do digest calculation. Note that in the following code, if user's username is "00E0A6-111", then sys_passwd will be automatically replaced with static value "00E0A6-111"

![image-20250508181833738](hard-coded-credential.assets/image-20250508181833738.png)

The login procedure takes `calculated_res` from CalcDigest's result, and compares it against with user input in the `response` field.

Note that CalcDigest (in libssap.so) uses md5 to hash user inputs. Since all inputs are known under this scenario, attackers can easily guess the right digest result.

## timeline

[05/08/2025] report to CVE