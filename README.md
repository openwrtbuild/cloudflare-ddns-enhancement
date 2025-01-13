# Cloudflare Dynamic DNS IP Updater Enhancement

<img alt="GitHub" src="https://img.shields.io/github/license/openwrtbuild/cloudflare-ddns-enhancement?color=black"> <img alt="GitHub last commit (branch)" src="https://img.shields.io/github/last-commit/openwrtbuild/cloudflare-ddns-enhancement/main"> <img alt="GitHub contributors" src="https://img.shields.io/github/contributors/openwrtbuild/cloudflare-ddns-enhancement">

This script is used to update Dynamic DNS (DDNS) service based on Cloudflare! Access your home network remotely via a custom domain name without a static IP! Written in pure BASH.

## Support Me



## Installation

```bash
git clone https://github.com/openwrtbuild/cloudflare-ddns-enhancement.git
```

## Usage

This script is used with crontab. Specify the frequency of execution through crontab.

```bash
# ┌───────────── minute (0 - 59)
# │ ┌───────────── hour (0 - 23)
# │ │ ┌───────────── day of the month (1 - 31)
# │ │ │ ┌───────────── month (1 - 12)
# │ │ │ │ ┌───────────── day of the week (0 - 6) (Sunday to Saturday 7 is also Sunday on some systems)
# │ │ │ │ │ ┌───────────── command to issue                               
# │ │ │ │ │ │
# │ │ │ │ │ │
# * * * * * /bin/bash {Location of the script}
```

## Enhancement

1. Add $1 as ip. (Easy to use it manually.)

   ```bash
   ./cloudflare-ddns.sh x.x.x.x
   # or ./cloudflare-ddnsv6.sh ipv6_address_value
   ```

2. Support only when local ip changes, does it check and update record on Cloudflare.  (Reduce the times calling api of Cloudflare and make it faster). Configure last_ipv4_info or last_ipv6_info to use this function.

3. When the dns record is new, it can be created automatically by setting auto_create to true. (new function: create dns record)

4. Modify log head including PID. When to use crontab (e.g. per minute), it is more convenient for logs. (Optimise log record for crontab per minute)

5. Support multiple records. (set record_names with the record separated by space if there are multiple record name)

6. ...

## Tested Environments:

CentOS 7.9 (Linux kernel: 5.9.0 | aarch64) 

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## Reference

This script was made with reference from [cloudflare-ddns-updater](https://github.com/K0p1-Git/cloudflare-ddns-updater) repo.

## License

[MIT](https://github.com/openwrtbuild/cloudflare-ddns-enhancement/blob/main/LICENSE)
