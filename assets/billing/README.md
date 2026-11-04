# Bundled Billing

`billing32` and `billing64` are copied unchanged from the local Docker reference
project `gstlenv/config/ini.tar.gz`, at commit
`e4df83a3639b7133be88eb6ca41a245b0c26098c`.
The reference archive SHA256 is
`7a4e0ee9f407682cab4f0f5114e57b244f4c8bb04eccc58ef03fe41ed09cd22d`.

The reference project is `yulinzhihou/gstlenv`. Its accompanying license is
preserved in `LICENSE`. These are prebuilt upstream executables, not newly
compiled binaries. Their hashes are recorded in `SHA256SUMS`.

The native environment selects the executable for the Linux host architecture,
not the MySQL version or game server bitness. Bundled binaries support x86
32-bit and x86-64 hosts. Other architectures require a matching user-supplied
`/root/billing.tar.gz`.

The upload takes precedence over existing or bundled programs. Flat `billing`
and nested `billing/billing` package layouts are supported. Only the executable
is installed: archive configuration files never replace runtime credentials.
Deployment does not launch the executable. Run `setini` before `runtlbb`.
