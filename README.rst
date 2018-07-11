Syncthing - Open, trustworthy and decentralized file sync
=========================================================

Syncthing_ replaces proprietary sync and cloud services with something open,
trustworthy and decentralized. Your data is your data alone and you deserve
to choose where it is stored, if it is shared with some third party and how
it's transmitted over the Internet.

This appliance includes all the standard features in `TurnKey Core`_,
and on top of that:

- Syncthing:
  
  - Installed from the `Stable Release Channel`_ via the official Syncthing
    apt package repository.

  - Pre-configured for remote access, with password set on firstboot.

  - SSL/TLS pre-enabled - uses default system SSL/TLS certificate.

  - Syncthing reverse proxied via Nginx:

    - Port 80 redirects to port 443 (http -> https).
    - Syncthing default port 8384 (http/https) redirects to 443 (https).

  - **Security note**: Updates to Syncthing may require supervision so
    they **ARE NOT** configured to install automatically.


Supervised Manual Syncthing Update
----------------------------------

To upgrade to the latest version of Syncthing from the command line::

    apt-get update
    apt-get install syncthing


Credentials *(passwords set at first boot)*
-------------------------------------------

-  Webmin, SSH: username **root**
-  Syncthing Web GUI: username **syncthing**

.. _Syncthing: https://syncthing.net/
.. _Stable Release Channel: https://docs.syncthing.net/users/releases.html
