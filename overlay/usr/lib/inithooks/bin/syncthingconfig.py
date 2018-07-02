#!/usr/bin/python
"""Set Syncthing Default Password and User and Edit Config Files to allow remote access to web gui
Option:
    --pass=     unless provided, will ask interactively
"""

import sys
import getopt
import bcrypt

from executil import system
from dialog_wrapper import Dialog

def usage(s=None):
    if s:
        print >> sys.stderr, "Error:", s
    print >> sys.stderr, "Syntax: %s [options]" % sys.argv[0]
    print >> sys.stderr, __doc__
    sys.exit(1)

def main():
    try:
        opts, args = getopt.gnu_getopt(sys.argv[1:], "h",
                                       ['help', 'pass='])
    except getopt.GetoptError, e:
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
            "Enter Web GUI Password.")

    hashpw = bcrypt.hashpw(password, bcrypt.gensalt())
    system('systemctl', 'enable', 'syncthing@syncthing.service')
    system('systemctl', 'start', 'syncthing@syncthing.service') 
    system('sleep 10')

    """Remove All Users and Password If Any"""
    system('sed', '-i', "/<user>.*/d", '/home/syncthing/.config/syncthing/config.xml')
    system('sed', '-i', "/<password>.*/d", '/home/syncthing/.config/syncthing/config.xml')

    """Edit to Listen On All Interfaces"""
    system('sed', '-i', "s/<address>[0-9].*<\/address>/<address>0.0.0.0:8384<\/address>/g", '/home/syncthing/.config/syncthing/config.xml')
    """Add Default User syncthing"""
    system('sed', '-i', "/<address>[0-9].*<\/address>/ a \\\t<user>syncthing</user>", '/home/syncthing/.config/syncthing/config.xml')
    """Assign password to user syncthing based off input"""
    system('sed', '-i', "/<user>syncthing<\\/user>/ a \\\t<password>%s</password>" % hashpw, '/home/syncthing/.config/syncthing/config.xml')
    """Enable SSL"""
    system('sed', '-i', "s/tls=\"false\"/tls=\"true\"/g", '/home/syncthing/.config/syncthing/config.xml')
    """Restart Syncthing"""
    system('systemctl', 'restart', 'syncthing@syncthing.service')
if __name__ == "__main__":
    main()


