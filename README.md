# pkmn-wfc-server

Docker image that contains [CoWFC](https://github.com/EnergyCube/CoWFC) and [pkmnFoundation Server](https://github.com/mm201/pkmn-classic-framework)

**Only tested on Battle Tower (Gen4)** and **Mystery Gifts are disabled** by default.

## How to use

You need a Wi-Fi access point compatible with the NDS. Refer to guides for wiimmfi etc.

Also need to open ports listed [here](https://github.com/barronwaffles/dwc_network_server_emulator/wiki/Troubleshooting#port-forwarding).

1. Edit "args" in `docker-compose.yml`
2. `docker-compose up`
3. Access the admin page `localhost/?page=admin&section=Dashboard`
4. Add your game to whitelist

### Game code (Gen4)

| title | code |
| --- | --- |
| Diamond | ADA |
| Pearl | APA |
| Platinum | CPU |
| HeartGold | IPK |
| SoulSilver | IPG |

## Caution

Since enabled weak-enough SSL auth on purpose, this container doesn't intended to be published via internet.

## Reference

- [dwc_network_server_emulator](https://github.com/EnergyCube/dwc_network_server_emulator)
- [CoWFC](https://github.com/EnergyCube/CoWFC)
- [pkmnFoundation Server](https://github.com/mm201/pkmn-classic-framework)
- [nds-constrain't](https://github.com/KaeruTeam/nds-constraint)
