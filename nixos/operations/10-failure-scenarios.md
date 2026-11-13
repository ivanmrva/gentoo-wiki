# 10. Failure scenarios: what protects you, how fast you recover

Recovery point objective (RPO): how much recent work can be lost. Recovery
time objective (RTO): how long until you work again. Local snapshots: hourly.
Offsite restic: daily. Configuration: every git push.

| Scenario | Protection | Recovery | RPO / RTO |
| --- | --- | --- | --- |
| Bad update | Generations; pre-update snapshot (`sysup`) | Previous generation; restore affected app data | 0 / minutes |
| Deleted or overwritten file | btrbk hourly snapshots | Copy from `@snapshots` | 1 h / minutes |
| SSD failure | restic on Google Drive | New SSD, disko, `nixos-install --flake`, restic restore | 1 day / ~1–2 h |
| Laptop stolen | LUKS2 + TPM PIN, BIOS password, Secure Boot | Revoke SSH keys, API tokens and the rclone Google access (Google account → Security → third-party access); reinstall on new hardware as above | 1 day / ~1–2 h |
| Laptop compromised (malware as root) | Firewall, sandboxing, no trusted-users; Drive trash (30 days) if backups were deleted | Reinstall from flake (clean by construction); restore data from a backup before the compromise; rotate secrets | depends / hours |
| Ransomware encrypts `/home` | Snapshots are read-only; restic keeps older versions; Drive trash for synced folders | Restore from snapshot or restic | 1 h / ~1 h |
| Backup silently stops | healthchecks.io dead-man's switch; ntfy on failed units | Fix the job; nothing lost yet | 0 / minutes |
| Forgotten TPM PIN | LUKS passphrase, recovery key | Unlock, re-enroll TPM | 0 / minutes |
| Lost password manager access | Must be solved outside this system: the password manager holds the recovery key, age keys and restic password | Your password manager's own recovery (emergency kit, second device) | - |

> [!WARNING]
> **Single points of failure to close:** (1) the password manager: keep its
> emergency kit printed and stored apart from the laptop; (2) Google Drive is
> the only offsite copy (**DECISION**: an immutable second copy or an
> external disk); (3) the git host: the repository is also on the laptop and
> in restic, so a lost GitHub account is recoverable.
