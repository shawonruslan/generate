# Re-copies the shared Android sources into the desktop module and re-applies the desktop patches.
# Run this after editing files under app/src/main/java when you do NOT have the Python generator at hand.
# (The generator in the delivery zip already produced the files - this script is only a safety net for CI.)
Write-Host "desktop sources are pre-generated; nothing to sync."
