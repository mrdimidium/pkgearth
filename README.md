# Zorian — tiny packages caching proxy

Soon humanity will go to Mars and in order for the colonists to be able to
program, we will need a local mirror of packages.

## Installation

At the moment, there are no packages prepared; only installation from source is
available.

```sh
git clone --depth 1 --branch nightly https://github.com/mrdimidium/Zorian.git
cd Zorian

# Don't use ReleaseFast.
# Memory errors are the main vulnerability class for network services.
# A few percent of performance will not pay for the captured server.
zig build -Doptimize=ReleaseSafe

# Create an unprivileged user for the daemon
sudo useradd -r -M -s /sbin/nologin zoriand

# Copy the executable file (if you choose a different path, update the daemon file)
sudo install -m 755 -o root ./zig-out/bin/zorian /usr/local/bin

# Copy the configuration file
sudo install -m 700 -o zorian ./pkg/zorian.zon /etc/

# Copy the systemd daemon config.
# Note that it specifies the paths to the executable and configuration files.
# Use `systemctl edit` rather than editing the unit to specify different paths.
sudo install -m 755 -o root ./pkg/zorian.service /usr/lib/systemd/system

# Add to startup and start the daemon
sudo systemctl enable --now zorian

# Check the status
sudo systemctl status zorian
```

## License

Copyright (C) 2025 Nikolay Govorov

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU Affero General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option) any
later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License along
with this program. If not, see <https://www.gnu.org/licenses/>.
