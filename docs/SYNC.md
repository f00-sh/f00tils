# Sync

Install truth: root [`install.sh`](../install.sh).  
Deploy copy: `site/install.sh` (must stay byte-identical — `make sync-install` from repo root, or `cmp install.sh site/install.sh`).  
Bootstrap mirror: `scripts/install.sh` should match root when touched (not a third story).