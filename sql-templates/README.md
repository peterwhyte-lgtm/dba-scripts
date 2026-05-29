# SQL Templates

This folder is the operational runbook layer for DBA tasks that are best started as repeatable SQL templates.

Use these files as production-grade starting points for:
- routine maintenance and statistics updates
- feature enablement such as CDC and TDE
- upgrade readiness checks and operational validation

Recommended workflow:
1. Copy the template into a change ticket or runbook.
2. Replace placeholder values with your environment-specific settings.
3. Test in a non-production instance before using in production.
4. Store the executed version under output-files/ or your formal runbook repository.
