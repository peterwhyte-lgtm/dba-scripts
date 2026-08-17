"""Entry point: `python -m sqldba_mcp` (stdio) or `--selftest` to check the install."""
import sys

from .server import describe, main

if __name__ == '__main__':
    if '--selftest' in sys.argv:
        print(describe())
        sys.exit(0)
    main()
