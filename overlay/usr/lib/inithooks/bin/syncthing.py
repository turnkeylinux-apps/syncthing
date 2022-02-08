#!/usr/bin/python3
"""Set Syncthing Default Password and User and Edit Config Files to allow
remote access to web gui

Options:
    --pass=     unless provided, will ask interactively
"""

import sys
import getopt
import bcrypt
import subprocess

from libinithooks.dialog_wrapper import Dialog


def usage(s=None):
    if s:
        print("Error:", s, file=sys.stderr)
    print("Syntax: %s [options]" % sys.argv[0], file=sys.stderr)
    print(__doc__, file=sys.stderr)
    sys.exit(1)


def main():
    try:
        opts, args = getopt.gnu_getopt(sys.argv[1:], "h",
                                       ['help', 'pass='])
    except getopt.GetoptError as e:
        usage(e)

    password = ""
    for opt, val in opts:
        if opt in ('-h', '--help'):
            usage()
        elif opt == '--pass':
            password = val

    if not password:
        d = Dialog('TurnKey Linux - First boot configuration')
        password = d.get_password(
            "Syncthing Password",
            "Enter new password for the 'syncthing' Web UI user.")

    hashpw = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()

    # Assign password to user syncthing based off input & restart
    subprocess.run([
        'sed', '-i',
        '\|<user>syncthing</user>|!b;n;c \\\t<password>%s</password>' % hashpw,
        '/home/syncthing/.config/syncthing/config.xml'])
    subprocess.run(['systemctl', 'restart', 'syncthing@syncthing.service'])


if __name__ == "__main__":
    main()
