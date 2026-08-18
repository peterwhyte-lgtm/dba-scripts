"""Entry point for `python -m sqldba_mcp`.

Delegates to the same main() as the `sqldba-mcp` console script so the two routes cannot
drift apart again. They did once: --selftest worked here and silently did nothing there.

sys.exit() matters for the same reason: setuptools wraps the console script in
`sys.exit(main())`, so without it this route would report success on a bad flag while
the other returned 2.
"""
import sys

from .server import main

if __name__ == '__main__':
    sys.exit(main())
