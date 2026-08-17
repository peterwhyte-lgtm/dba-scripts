"""Entry point for `python -m sqldba_mcp`.

Delegates to the same main() as the `sqldba-mcp` console script so the two routes cannot
drift apart again. They did once: --selftest worked here and silently did nothing there.
"""
from .server import main

if __name__ == '__main__':
    main()
