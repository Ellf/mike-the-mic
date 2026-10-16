#!/bin/sh
# Claude Code Stop hook: forwards the hook payload to the Mike app.
# Silently does nothing if the app isn't running.
curl -s -m 2 -o /dev/null -X POST -H 'Content-Type: application/json' \
  --data-binary @- http://127.0.0.1:5151/hook || true
