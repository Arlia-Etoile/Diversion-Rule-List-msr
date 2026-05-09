# Diversion-Rule-List: MRS generator

An automated tool to download, process, and convert various network rule lists, generating rule files in Mihomo Rule Set (MRS) format.

## Project Structure

```text
.
|-- LICENSE
|-- README.md
|-- config.yaml   # Configuration file
`-- start.sh      # Main script
```

## Output Files

Each task generates rule files in plain text and mrs (mihomo) formats across their respective branches.

## Currently Configured Rule Sets

> This section is automatically updated by GitHub Actions. You can directly copy the links below to your proxy clients.

## Dependencies

`yq jq curl wget gunzip sha256sum python`

## GitHub Actions

The project is configured with an automated workflow [`.github/workflows/mrs.yml`](.github/workflows/mrs.yml):

- Runs automatically every day at 03:45 (UTC+8). It can also be triggered manually via the GitHub interface. The number of retained historical runs is configurable.

## License

This project uses the GPL-3.0 License. See the [LICENSE](LICENSE) file for details.

### 🔴 Mandatory Requirements

- **Must be Open Source**: Any software using this project's code must be open source.
- **Same License**: Derivative works must use the GPL-3.0 or a compatible license.
- **Provide Source Code**: When distributing binary files, the source code must also be provided.
- **Retain Copyright**: The original copyright notice and license text must be retained.

### 🚫 Prohibited Actions

- ❌ Using this project's code in closed-source commercial software.
- ❌ Deleting or modifying the license declaration.
- ❌ Claiming proprietary rights to this project.
- ❌ Statically linking this project's code in proprietary software.

### ✅ Permitted Actions

- ✅ Free to use, modify, and distribute.
- ✅ Use in open-source projects.
- ✅ Commercial use (but must remain open source).
- ✅ Call via network API (the caller does not need to be open source).

## Rule Sources

The rules currently aggregated in this project are sourced from the following projects:

- [ShuntRules](https://github.com/luestr/ShuntRules)
- [Diversion-Rule-List](https://github.com/Arlia-Etoile/Diversion-Rule-List/tree/legacy)

## Credits & Acknowledgements

Special thanks to the upstream maintainer [NuoFang6](https://github.com/NuoFang6) and the [original project](https://github.com/OOM-WG/RuleList) for their outstanding work and maintenance.
