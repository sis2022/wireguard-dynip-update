# Wireguard Dynamic DNS Update

* Using ISC binds dynamic DNS to resolve your wg endpoint DNS names to IPv4
  addresses requires updating Wireguards endpoint configuration on a tight
  schedule. Otherwise Wireguard endpoint may not be available @boot or in
  between (manual) updates.
* 'wg-dynip-update.sh' remedies what Wireguard should offer off the bat:
  updating the endpoint DNS name with the most recent IPv4 address -- if necessary
  and available.
* Cronjob every five minutes:
```
*/5 * * * * root test -x /usr/local/sbin/wg-dynip-update.sh && /usr/local/sbin/wg-dynip-update.sh
```
* Pro tip: Change or add your favourite DNS servers IPv4 addresses in 'DNS_SRV'
  array.
* License: GPLv2
